//! sound-devices -- 1:1 port of scripts/sound-devices.py (Settings > Sounds). Talks to PipeWire/PulseAudio
//! through pactl, exactly like the script did.
//!
//!   list                                  JSON: every output (sink) and input (source) with its card's profiles
//!   set-profile <card> <profile>          pactl set-card-profile
//!   set-port <sink|source> <n> <port>     pactl set-sink-port / set-source-port
//!   set-default <sink|source> <n>         pactl set-default-sink / -source   (moves playing streams too)
//!   volume <sink|source> <n> <pct>...     one value = all channels, N values = per channel (left, right, ...)
//!   mute <sink|source> <n> <0|1|toggle>
//!   combine on <sink>...                  play to several outputs at once (module-combine-sink named qs_combined)
//!   combine off                           stop combining; sound goes back to where it was before combining
//!   delay <ms>                            delay of the WIRED outputs, -10..500 ms, inside the combined output
//!   restore                               re-create the combined output saved in state/sound-combine.txt
//!   sync-loop                             (started by `combine on`) keeps the Bluetooth outputs in step
//!
//! Delays inside the combined output (nothing outside it is touched):
//!   * Wired outputs are all delayed by the slider value, together. Every delayed output carries
//!     DELAY_BASE_MS of buffer: real delay = slider + 10 ms (slider -10 = no buffer, +500 = 510 ms).
//!   * Bluetooth outputs do NOT follow the slider. With two or more of them, each one is held back by
//!     (slowest Bluetooth latency - its own latency), re-measured every SYNC_EVERY seconds and corrected live
//!     whenever it is off by SYNC_STEP_MS or more.
//! Each delayed output goes through a small PipeWire filter-chain (one `pipewire -c` process, one hidden sink
//! "qs_delay_<n>" per output) that holds the sound back and plays it on the real device.

use crate::pyjson::dumps;
use crate::util::{
    cmd, out, pactl, pactl_js, py_str, round_half_even, run_timeout, sleep_secs, spawn_detached, splitlines, truthy,
    RunErr,
};
use serde_json::{json, Map, Value};
use std::collections::HashMap;
use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::OnceLock;
use std::time::Duration;

const COMB: &str = "qs_combined";
const DELAY_PREFIX: &str = "qs_delay_";
const OLD_MONO: &str = "qs_mono."; // leftovers of the removed Mono mode
const DELAY_MIN: i64 = -10;
const DELAY_MAX: i64 = 500;
const DELAY_BASE_MS: i64 = 10;
const DELAY_BUFFER_S: f64 = 0.6; // filter-chain buffer: bigger than (DELAY_MAX + DELAY_BASE_MS) / 1000
const SYNC_EVERY: f64 = 10.0; // seconds between Bluetooth latency checks
const SYNC_STEP_MS: f64 = 15.0; // only correct a Bluetooth delay when it is off by at least this much (no clicks)

struct Paths {
    state_dir: PathBuf,
    state: PathBuf,       // sound-combine.txt
    prev: PathBuf,        // the output sound came from before combining
    delay_file: PathBuf,  // slider value in ms (wired outputs)
    delay_conf: PathBuf,
    delay_map: PathBuf,   // [{target, kind, s, node}]: what is delayed, by how much
    bt_status: PathBuf,   // what the sync loop measured (shown in Settings)
}

fn paths() -> &'static Paths {
    static P: OnceLock<Paths> = OnceLock::new();
    P.get_or_init(|| {
        let home = env::var("HOME").unwrap_or_else(|_| ".".into());
        let state_dir = Path::new(&home).join(".config/quickshell/state");
        Paths {
            state: state_dir.join("sound-combine.txt"),
                  prev: state_dir.join("sound-combine-prev.txt"),
                  delay_file: state_dir.join("sound-delay.txt"),
                  delay_conf: state_dir.join("qs-speaker-delay.conf"),
                  delay_map: state_dir.join("sound-delay-map.json"),
                  bt_status: state_dir.join("sound-bt-sync.json"),
                  state_dir,
        }
    })
}

// ───────────────────────────── json helpers ──────────────────────────────

fn gs<'a>(v: &'a Value, k: &str) -> &'a str {
    v.get(k).and_then(Value::as_str).unwrap_or("")
}

fn get_or(v: &Value, k: &str, d: Value) -> Value {
    v.get(k).cloned().unwrap_or(d)
}

fn props_of(v: &Value) -> Option<&Map<String, Value>> {
    v.get("properties").and_then(Value::as_object)
}

fn prop<'a>(v: &'a Value, k: &str) -> &'a str {
    props_of(v).and_then(|p| p.get(k)).and_then(Value::as_str).unwrap_or("")
}

fn pct_of(v: &Value) -> i64 {
    if let Some(p) = v.get("value_percent").and_then(Value::as_str) {
        let t = p.trim();
        if t.ends_with('%') {
            if let Ok(n) = t[..t.len() - 1].trim().parse::<i64>() {
                return n;
            }
        }
    }
    round_half_even(v.get("value").and_then(Value::as_f64).unwrap_or(0.0) * 100.0 / 65536.0) as i64
}

fn channels_of(dev: &Value) -> Vec<Value> {
    let Some(vol) = dev.get("volume").and_then(Value::as_object) else { return Vec::new() };
    let order: Vec<&str> = dev
    .get("channel_map")
    .and_then(Value::as_str)
    .unwrap_or("")
    .split(',')
    .filter(|c| !c.is_empty())
    .collect();
    let mut names: Vec<&str> = order.into_iter().filter(|c| vol.contains_key(*c)).collect();
    if names.is_empty() {
        names = vol.keys().map(|k| k.as_str()).collect();
    }
    names.iter().map(|c| json!({"ch": c, "pct": pct_of(&vol[*c])})).collect()
}

fn avail(p: &Value) -> &'static str {
    let a = gs(p, "availability").to_lowercase();
    if a.contains("not") {
        "no"
    } else if a == "available" {
        "yes"
    } else {
        "unknown"
    }
}

fn kind_of(dev: &Value, active_port: &str) -> &'static str {
    let blob = [
        gs(dev, "name"),
        prop(dev, "device.api"),
        prop(dev, "device.bus"),
        prop(dev, "device.form_factor"),
        active_port,
    ]
    .join(" ")
    .to_lowercase();
    let has = |s: &str| blob.contains(s);
    if has("bluez") || has("bluetooth") {
        "bluetooth"
    } else if has("hdmi") || has("displayport") {
        "hdmi"
    } else if has("usb") {
        "usb"
    } else if has("headphone") || has("headset") {
        "headphones"
    } else if has("speaker") || has("internal") {
        "speaker"
    } else if has("lineout") || has("line-out") || has("linein") || has("line-in") {
        "line"
    } else if has("mic") {
        "mic"
    } else {
        "audio"
    }
}

fn card_of<'a>(dev: &Value, cards: &'a [Value]) -> Option<&'a Value> {
    let did = prop_value(dev, "device.id");
    for c in cards {
        if let Some(d) = &did {
            if py_str(&get_or(c, "index", Value::Null)) == py_str(d) {
                return Some(c);
            }
        }
    }
    let name = gs(dev, "name");
    for c in cards {
        let cn = gs(c, "name");
        let stem = match cn.split_once('.') {
            Some((_, b)) => b,
            None => cn,
        };
        if !stem.is_empty() && name.contains(stem) {
            return Some(c);
        }
    }
    None
}

fn prop_value(v: &Value, k: &str) -> Option<Value> {
    props_of(v).and_then(|p| p.get(k)).cloned()
}

fn profiles_of(card: Option<&Value>) -> Vec<Value> {
    let Some(card) = card else { return Vec::new() };
    let Some(profiles) = card.get("profiles").and_then(Value::as_object) else { return Vec::new() };
    struct P {
        name: String,
        desc: Value,
        avail: bool,
        prio: f64,
    }
    let mut out: Vec<P> = Vec::new();
    for (n, p) in profiles {
        if n == "off" {
            continue;
        }
        out.push(P {
            name: n.clone(),
                 desc: get_or(p, "description", json!(n)),
                 avail: p.get("available") != Some(&Value::Bool(false)),
                 prio: p.get("priority").and_then(Value::as_f64).unwrap_or(0.0),
        });
    }
    out.sort_by(|a, b| {
        (!a.avail)
        .cmp(&(!b.avail))
        .then(b.prio.partial_cmp(&a.prio).unwrap_or(std::cmp::Ordering::Equal))
    });
    out.into_iter().map(|p| json!({"name": p.name, "desc": p.desc, "avail": p.avail})).collect()
}

fn entry(dev: &Value, cards: &[Value], default: &str) -> Value {
    let card = card_of(dev, cards);
    let ports: Vec<Value> = dev
    .get("ports")
    .and_then(Value::as_array)
    .map(|a| {
        a.iter()
        .map(|p| {
            json!({
                "name": get_or(p, "name", json!("")),
                  "desc": get_or(p, "description", get_or(p, "name", json!(""))),
                  "avail": avail(p),
            })
        })
        .collect()
    })
    .unwrap_or_default();
    let ap = dev.get("active_port").filter(|v| truthy(v)).cloned().unwrap_or_else(|| json!(""));
    let (card_name, card_desc, active_profile) = match card {
        Some(c) => (
            get_or(c, "name", json!("")),
                    get_or(&json!(props_of(c).cloned().unwrap_or_default()), "device.description", json!("")),
                    get_or(c, "active_profile", json!("")),
        ),
        None => (json!(""), json!(""), json!("")),
    };
    json!({
        "name": get_or(dev, "name", json!("")),
          "desc": get_or(dev, "description", get_or(dev, "name", json!(""))),
          "kind": kind_of(dev, ap.as_str().unwrap_or("")),
          "card": card_name,
          "cardDesc": card_desc,
          "activeProfile": active_profile,
          "profiles": profiles_of(card),
          "ports": ports,
          "activePort": ap,
          "channels": channels_of(dev),
          "muted": dev.get("mute").map_or(false, truthy),
          "isDefault": dev.get("name").and_then(Value::as_str) == Some(default),
          "state": get_or(dev, "state", json!("")),
    })
}

fn hidden(name: &str) -> bool {
    name == COMB || name.starts_with(DELAY_PREFIX) || name.starts_with(OLD_MONO)
}

fn is_bt(dev: &Value) -> bool {
    gs(dev, "name").starts_with("bluez_output.") || prop(dev, "device.api").to_lowercase().contains("bluez")
}

// ───────────────────────────── state files ──────────────────────────────

fn read_lines(p: &Path) -> Vec<String> {
    match fs::read(p) {
        Ok(b) => String::from_utf8_lossy(&b)
        .replace("\r\n", "\n")
        .replace('\r', "\n")
        .split('\n')
        .map(|l| l.trim().to_string())
        .filter(|l| !l.is_empty())
        .collect(),
        Err(_) => Vec::new(),
    }
}

fn read_json(p: &Path) -> Option<Value> {
    serde_json::from_str(&fs::read_to_string(p).ok()?).ok()
}

fn make_state_dir() {
    let _ = fs::create_dir_all(&paths().state_dir);
}

fn write_json(p: &Path, data: &Value) {
    make_state_dir();
    let mut tmp = p.as_os_str().to_owned();
    tmp.push(".tmp");
    let tmp = PathBuf::from(tmp);
    if let Err(e) = fs::write(&tmp, dumps(data, false)).and_then(|_| fs::rename(&tmp, p)) {
        eprintln!("sound-devices: cannot write {}: {e}", p.display());
    }
}

fn remove(p: &Path) {
    let _ = fs::remove_file(p);
}

fn read_state() -> Vec<String> {
    read_lines(&paths().state)
}

fn write_state(names: &[String]) {
    make_state_dir();
    let mut set: Vec<&String> = names.iter().collect();
    set.sort();
    set.dedup();
    let body = set.iter().map(|s| s.as_str()).collect::<Vec<_>>().join("\n") + if names.is_empty() { "" } else { "\n" };
    let _ = fs::write(&paths().state, body);
}

fn json_list(p: &Path) -> Vec<Value> {
    match read_json(p) {
        Some(Value::Array(a)) => a,
        _ => Vec::new(),
    }
}

// ───────────────────────────── pactl helpers ──────────────────────────────

fn sinks_js() -> Vec<Value> {
    pactl_js(&["list", "sinks"]).unwrap_or_default()
}

/// Distinct sink names, in the order pactl listed them.
fn sink_names() -> Vec<String> {
    let mut out: Vec<String> = Vec::new();
    for s in sinks_js() {
        if let Some(n) = s.get("name").and_then(Value::as_str) {
            if !out.iter().any(|x| x == n) {
                out.push(n.to_string());
            }
        }
    }
    out
}

fn src_index(sink_name: &str) -> String {
    for line in splitlines(&pactl(&["list", "short", "sinks"])) {
        let f: Vec<&str> = line.split('\t').collect();
        if f.len() > 1 && f[1] == sink_name {
            return f[0].to_string();
        }
    }
    String::new()
}

fn move_streams(src: &str, dst: &str) {
    // the sink's index is looked up once (the script re-asked pactl for every stream; same answer)
    let mut idx: Option<String> = None;
    for line in splitlines(&pactl(&["list", "short", "sink-inputs"])) {
        let f: Vec<&str> = line.split('\t').collect();
        if f.len() > 1 {
            let i = idx.get_or_insert_with(|| src_index(src));
            if f[1] == i.as_str() {
                pactl(&["move-sink-input", f[0], dst]);
            }
        }
    }
}

/// Mono mode is gone: unload any qs_mono.* sinks an earlier version left behind.
fn drop_old_mono(sinks: &[Value]) -> bool {
    let old: Vec<&str> = sinks.iter().map(|x| gs(x, "name")).filter(|n| n.starts_with(OLD_MONO)).collect();
    if old.is_empty() {
        return false;
    }
    let dflt = pactl(&["get-default-sink"]).trim().to_string();
    for n in old {
        let master = &n[OLD_MONO.len()..];
        if dflt == n {
            pactl(&["set-default-sink", master]);
            move_streams(n, master);
        }
        for line in splitlines(&pactl(&["list", "short", "modules"])) {
            let f: Vec<&str> = line.split('\t').collect();
            if f.len() > 2 && f[1] == "module-remap-sink" && f[2].contains(&format!("sink_name={n}")) {
                pactl(&["unload-module", f[0]]);
            }
        }
    }
    remove(&paths().state_dir.join("sound-mono.txt"));
    true
}

// ───────────────────────────── list ──────────────────────────────

fn do_list() -> i32 {
    let mut sinks = pactl_js(&["list", "sinks"]);
    if let Some(s) = &sinks {
        if !s.is_empty() && drop_old_mono(s) {
            sinks = pactl_js(&["list", "sinks"]);
        }
    }
    let sources = pactl_js(&["list", "sources"]);
    let cards = pactl_js(&["list", "cards"]);
    let Some(sinks) = sinks else {
        out(&dumps(&json!({"error": "pactl not found", "outputs": [], "inputs": []}), false));
        return 0;
    };
    let (sources, cards) = (sources.unwrap_or_default(), cards.unwrap_or_default());
    let dsink = pactl(&["get-default-sink"]).trim().to_string();
    let dsrc = pactl(&["get-default-source"]).trim().to_string();
    let comb = sinks.iter().find(|x| gs(x, "name") == COMB);
    let real: Vec<&Value> = sinks.iter().filter(|x| !hidden(gs(x, "name"))).collect();
    let outs: Vec<Value> = real.iter().map(|x| entry(x, &cards, &dsink)).collect();
    let ins: Vec<Value> = sources
    .iter()
    .filter(|x| !x.get("monitor_of_sink").map_or(false, truthy) && !gs(x, "name").ends_with(".monitor"))
    .map(|x| entry(x, &cards, &dsrc))
    .collect();
    let combined = json!({
        "active": comb.is_some(),
                         "isDefault": dsink == COMB,
                         "members": read_state(),
                         "channels": comb.map(channels_of).unwrap_or_default(),
                         "muted": comb.map_or(false, |c| c.get("mute").map_or(false, truthy)),
    });
    let wired = real.iter().filter(|x| !is_bt(x)).count();
    let bt: Value = if comb.is_some() {
        match read_json(&paths().bt_status) {
            Some(Value::Object(o)) => o.get("devices").cloned().unwrap_or_else(|| json!([])),
            _ => json!([]),
        }
    } else {
        json!([])
    };
    let delay = json!({
        "available": wired > 0,
        "wired": wired,
        "ms": read_delay(),
                      "running": sinks.iter().any(|x| gs(x, "name").starts_with(DELAY_PREFIX)),
                      "bt": bt,
    });
    out(&dumps(
        &json!({"outputs": outs, "inputs": ins, "combined": combined, "delay": delay,
            "defaultSink": dsink, "defaultSource": dsrc}),
            false,
    ));
    0
}

// ── finding and unloading the combined output ──

/// Every loaded module-combine-sink that belongs to qs_combined. PipeWire does not always print the
/// arguments the way we gave them, so look at three things: the sink's owner module, the module arguments
/// (with or without quotes), and -- if nothing else matches -- the only combine module there is.
fn combine_module_ids() -> Vec<String> {
    let mut mods: Vec<(String, String)> = Vec::new();
    for line in splitlines(&pactl(&["list", "short", "modules"])) {
        let f: Vec<&str> = line.split('\t').collect();
        if f.len() > 1 && f[1] == "module-combine-sink" {
            let args = if f.len() > 2 { f[2].to_string() } else { String::new() };
            match mods.iter_mut().find(|(k, _)| k == f[0]) {
                Some(slot) => slot.1 = args,
                None => mods.push((f[0].to_string(), args)),
            }
        }
    }
    let mut found: Vec<String> = Vec::new();
    for s in sinks_js() {
        if gs(&s, "name") == COMB {
            let om = py_str(&get_or(&s, "owner_module", Value::Null));
            if mods.iter().any(|(k, _)| *k == om) {
                found.push(om);
            }
        }
    }
    for (mid, args) in &mods {
        if args_name_matches(args) && !found.contains(mid) {
            found.push(mid.clone());
        }
    }
    if found.is_empty() && sink_names().iter().any(|n| n == COMB) && mods.len() == 1 {
        found = mods.iter().map(|(k, _)| k.clone()).collect();
    }
    found
}

/// re.search(r"sink_name=[\"']?" + re.escape(COMB) + r"([\"'\s]|$)", args)
fn args_name_matches(args: &str) -> bool {
    for (i, _) in args.match_indices("sink_name=") {
        let mut rest = &args[i + "sink_name=".len()..];
        if rest.starts_with('"') || rest.starts_with('\'') {
            rest = &rest[1..];
        }
        if let Some(after) = rest.strip_prefix(COMB) {
            match after.chars().next() {
                None => return true,
                Some(c) if c == '"' || c == '\'' || c.is_whitespace() => return true,
                _ => {}
            }
        }
    }
    false
}

fn comb_gone() -> bool {
    !sink_names().iter().any(|n| n == COMB)
}

fn unload_combine() -> bool {
    for _ in 0..3 {
        let ids = combine_module_ids();
        if ids.is_empty() {
            break;
        }
        for mid in &ids {
            pactl(&["unload-module", mid]);
        }
        for _ in 0..10 {
            // wait until the sink is really gone
            if comb_gone() {
                return true;
            }
            sleep_secs(0.05);
        }
    }
    comb_gone()
}

// ── delays ──

fn clamp_delay(ms: f64) -> i64 {
    DELAY_MAX.min(DELAY_MIN.max(round_half_even(ms) as i64)).max(DELAY_MIN)
}

fn read_delay() -> i64 {
    match read_lines(&paths().delay_file).first().and_then(|l| l.parse::<f64>().ok()) {
        Some(f) if f.is_finite() => clamp_delay(f),
        _ => 0,
    }
}

fn wired_delay_s(ms: i64) -> f64 {
    0.max(ms + DELAY_BASE_MS) as f64 / 1000.0
}

fn proc_pids(needle: &str) -> Vec<i32> {
    let me = std::process::id() as i32;
    let mut out = Vec::new();
    if let Ok(rd) = fs::read_dir("/proc") {
        for d in rd.flatten() {
            let name = d.file_name().to_string_lossy().into_owned();
            if name.is_empty() || !name.chars().all(|c| c.is_ascii_digit()) {
                continue;
            }
            let pid: i32 = match name.parse() {
                Ok(p) => p,
                Err(_) => continue,
            };
            if pid == me {
                continue;
            }
            let Ok(raw) = fs::read(format!("/proc/{name}/cmdline")) else { continue };
            let cmdline = String::from_utf8_lossy(&raw).replace('\0', " ");
            if cmdline.contains(needle) {
                out.push(pid);
            }
        }
    }
    out
}

fn kill_all(needle: &str) {
    for pid in proc_pids(needle) {
        unsafe {
            libc::kill(pid, libc::SIGTERM);
        }
    }
}

fn delay_conf_needle() -> String {
    paths().delay_conf.to_string_lossy().into_owned()
}

fn stop_delay_chain() {
    let needle = delay_conf_needle();
    kill_all(&needle);
    for _ in 0..20 {
        if proc_pids(&needle).is_empty() && !sink_names().iter().any(|n| n.starts_with(DELAY_PREFIX)) {
            break;
        }
        sleep_secs(0.05);
    }
    remove(&paths().delay_map);
}

fn stop_sync() {
    kill_all("sound-devices sync-loop");
    kill_all("sound-devices.py sync-loop"); // a sync loop started by the old Python script
    remove(&paths().bt_status);
}

/// targets: [(real sink name, delay in seconds)] -> one filter-chain module per output.
fn delay_conf(targets: &[(String, f64)]) -> String {
    let node = |name: &str, secs: f64| -> String {
        let mut s = String::from("\n                    {\n                        type    = builtin\n                        name    = @NAME@\n                        label   = delay\n                        config  = { \"max-delay\" = @MAX@ }\n                        control = { \"Delay (s)\" = @SECS@ }\n                    }");
        s = s.replace("@NAME@", name);
        s = s.replace("@MAX@", &format!("{:.2}", DELAY_BUFFER_S));
        s.replace("@SECS@", &format!("{:.4}", secs))
    };
    const MODULE: &str = "    { name = libpipewire-module-filter-chain
    args = {
    node.description = \"Delayed output @I@\"
    media.name       = \"Delayed output @I@\"
    filter.graph = {
    nodes = [@DL@@DR@
    ]
    inputs  = [ \"dl:In\" \"dr:In\" ]
    outputs = [ \"dl:Out\" \"dr:Out\" ]
}
capture.props = {
node.name      = \"@PREFIX@@I@\"
media.class    = \"Audio/Sink\"
audio.position = [ FL FR ]
}
playback.props = {
node.name         = \"@PREFIX@@I@_out\"
audio.position    = [ FL FR ]
target.object     = \"@TARGET@\"
stream.dont-remix = true
node.passive      = true
}
}
}
";
let mut mods = String::new();
for (i, (target, secs)) in targets.iter().enumerate() {
    mods += &MODULE
    .replace("@DL@", &node("dl", *secs))
    .replace("@DR@", &node("dr", *secs))
    .replace("@PREFIX@", DELAY_PREFIX)
    .replace("@I@", &i.to_string())
    .replace("@TARGET@", target);
}
"# generated by sound-devices.py -- delays single outputs inside the combined output
context.properties = {
log.level = 0
}

context.spa-libs = {
audio.convert.* = audioconvert/libspa-audioconvert
support.*       = support/libspa-support
}

context.modules = [
{ name = libpipewire-module-rt
args = { }
flags = [ ifexists nofail ]
}
{ name = libpipewire-module-protocol-native }
{ name = libpipewire-module-client-node }
{ name = libpipewire-module-adapter }
@MODS@]
"
.replace("@MODS@", &mods)
}

#[derive(Clone)]
struct Plan {
    target: String,
    kind: &'static str,
    s: f64,
}

/// plan -> starts the chain; returns {real sink: hidden sink} (empty on failure).
fn start_delay_chain(plan: &[Plan]) -> HashMap<String, String> {
    stop_delay_chain();
    make_state_dir();
    let targets: Vec<(String, f64)> = plan.iter().map(|p| (p.target.clone(), p.s)).collect();
    if fs::write(&paths().delay_conf, delay_conf(&targets)).is_err() {
        return HashMap::new();
    }
    let mut c = cmd("pipewire");
    c.arg("-c").arg(&paths().delay_conf);
    if spawn_detached(&mut c).is_err() {
        return HashMap::new();
    }
    let want: Vec<String> = (0..plan.len()).map(|i| format!("{DELAY_PREFIX}{i}")).collect();
    for _ in 0..60 {
        // up to 6 s for the hidden sinks to show up
        sleep_secs(0.1);
        let have = sink_names();
        if want.iter().all(|n| have.contains(n)) {
            let map: Vec<Value> = plan
            .iter()
            .enumerate()
            .map(|(i, p)| json!({"target": p.target, "kind": p.kind, "s": p.s, "node": want[i]}))
            .collect();
            write_json(&paths().delay_map, &Value::Array(map));
            return plan.iter().enumerate().map(|(i, p)| (p.target.clone(), want[i].clone())).collect();
        }
    }
    stop_delay_chain();
    HashMap::new()
}

/// PipeWire node.name -> node id (pw-dump).
fn node_ids() -> HashMap<String, Value> {
    let mut out = HashMap::new();
    if let Ok(o) = cmd("pw-dump").output() {
        let txt = String::from_utf8_lossy(&o.stdout).into_owned();
        let txt = if txt.is_empty() { "[]".to_string() } else { txt };
        if let Ok(Value::Array(a)) = serde_json::from_str::<Value>(&txt) {
            for o in a {
                let name = o
                .get("info")
                .and_then(|i| i.get("props"))
                .and_then(|p| p.get("node.name"))
                .and_then(Value::as_str)
                .unwrap_or("");
                if o.get("type").and_then(Value::as_str) == Some("PipeWire:Interface:Node") && !name.is_empty() {
                    out.insert(name.to_string(), get_or(&o, "id", Value::Null));
                }
            }
        }
    }
    out
}

/// changes: [(hidden sink name, seconds)] -> live parameter change on the running chain.
fn push_delays(changes: &[(String, f64)]) {
    if changes.is_empty() {
        return;
    }
    let ids = node_ids();
    for (node, secs) in changes {
        let Some(nid) = ids.get(node) else { continue };
        let d = format!("{:.4}", secs);
        let params = format!("{{ params = [ \"dl:Delay (s)\" {d} \"dr:Delay (s)\" {d} ] }}");
        let _ = cmd("pw-cli").args(["s", &py_str(nid), "Props", &params]).output();
    }
}

/// The slider: every wired output inside the combined output, together. Bluetooth is left to the sync loop.
fn set_delay(ms: f64) -> i32 {
    let ms = clamp_delay(ms);
    make_state_dir();
    let _ = fs::write(&paths().delay_file, format!("{ms}\n"));
    let mut m = json_list(&paths().delay_map);
    let secs = wired_delay_s(ms);
    let wired: Vec<usize> = (0..m.len()).filter(|&i| gs(&m[i], "kind") == "wired").collect();
    if !wired.is_empty() {
        let changes: Vec<(String, f64)> = wired.iter().map(|&i| (gs(&m[i], "node").to_string(), secs)).collect();
        push_delays(&changes);
        for &i in &wired {
            if let Some(o) = m[i].as_object_mut() {
                o.insert("s".into(), json!(secs));
            }
        }
        write_json(&paths().delay_map, &Value::Array(m));
    }
    0
}

// ── Bluetooth latency ──

/// The speaker's own reported playback delay (AVDTP delay reporting, via BlueZ), if it reports one.
fn bt_delay_report_ms(sink: &str) -> Option<f64> {
    // re.search(r"bluez_output\.([0-9A-Fa-f_]{17})", sink)
    let key = "bluez_output.";
    let mut mac: Option<String> = None;
    for (i, _) in sink.match_indices(key) {
        let rest: Vec<char> = sink[i + key.len()..].chars().take(17).collect();
        if rest.len() == 17 && rest.iter().all(|c| c.is_ascii_hexdigit() || *c == '_') {
            mac = Some(rest.into_iter().collect());
            break;
        }
    }
    let dev = format!("dev_{}", mac?.to_uppercase());
    let mut c = cmd("busctl");
    c.args([
        "--system",
        "--json=short",
        "call",
        "org.bluez",
        "/",
        "org.freedesktop.DBus.ObjectManager",
        "GetManagedObjects",
    ]);
    let (_, stdout, _) = match run_timeout(&mut c, Duration::from_secs(5)) {
        Ok(r) => r,
        Err(RunErr::Spawn) | Err(RunErr::Timeout) => return None,
    };
    let root: Value = serde_json::from_str(&stdout).ok()?;
    let objs = root.get("data")?.get(0)?.as_object()?;
    let mut best = None;
    for (path, ifaces) in objs {
        let t = ifaces.get("org.bluez.MediaTransport1");
        if let Some(t) = t {
            if path.contains(&dev) && truthy(t) && t.get("Delay").is_some() {
                if let Some(v) = t["Delay"].get("data").and_then(Value::as_f64) {
                    best = Some(v / 10.0); // BlueZ reports 1/10 ms
                }
            }
        }
    }
    best
}

/// Best estimate of how late this Bluetooth output plays: the speaker's own delay report when it gives
/// one, plus what PipeWire says is queued in the sink right now.
fn bt_latency_ms(sink: &str, sinks: &[Value]) -> f64 {
    let mut queued = 0.0;
    for s in sinks {
        if gs(s, "name") == sink {
            let mut lat = s.get("latency").cloned();
            if let Some(Value::Object(o)) = &lat {
                lat = Some(o.get("actual").cloned().unwrap_or_else(|| o.get("current").cloned().unwrap_or(json!(0))));
            }
            if let Some(Value::Number(n)) = lat {
                queued = n.as_f64().unwrap_or(0.0) / 1000.0; // usec -> ms
            }
        }
    }
    let rep = bt_delay_report_ms(sink).filter(|x| *x != 0.0).unwrap_or(0.0);
    rep + queued
}

/// What gets a delay chain, and how long each is held back (seconds).
fn plan_for(sinks: &[Value], members: &[String], lat: &HashMap<String, f64>) -> Vec<Plan> {
    let by = |m: &str| sinks.iter().rev().find(|s| gs(s, "name") == m);
    let wired: Vec<&String> = members.iter().filter(|m| by(m).map_or(false, |s| !is_bt(s))).collect();
    let bts: Vec<&String> = members.iter().filter(|m| by(m).map_or(false, is_bt)).collect();
    let mut plan: Vec<Plan> = wired
    .iter()
    .map(|w| Plan { target: (*w).clone(), kind: "wired", s: wired_delay_s(read_delay()) })
    .collect();
    if bts.len() >= 2 {
        let l = |b: &String| lat.get(b).copied().unwrap_or(0.0);
        let slowest = bts.iter().map(|b| l(b)).fold(f64::NEG_INFINITY, f64::max);
        for b in &bts {
            plan.push(Plan {
                target: (*b).clone(),
                      kind: "bt",
                      s: (DELAY_BASE_MS as f64 + slowest - l(b)) / 1000.0,
            });
        }
    }
    plan
}

/// Runs while the combined output exists: re-measures the Bluetooth latencies and corrects the delays.
fn sync_loop() -> i32 {
    let mut ema: HashMap<String, f64> = HashMap::new();
    loop {
        let sinks = sinks_js();
        if !sinks.iter().any(|s| gs(s, "name") == COMB) {
            break;
        }
        let mut m = json_list(&paths().delay_map);
        let bts: Vec<usize> = (0..m.len()).filter(|&i| gs(&m[i], "kind") == "bt").collect();
        let mut changes: Vec<(String, f64)> = Vec::new();
        let mut devices: Vec<Value> = Vec::new();
        if !bts.is_empty() {
            for &i in &bts {
                let target = gs(&m[i], "target").to_string();
                let now = bt_latency_ms(&target, &sinks);
                let v = match ema.get(&target) {
                    None => now,
                    Some(prev) => 0.6 * prev + 0.4 * now,
                };
                ema.insert(target, v);
            }
            let slowest = bts.iter().map(|&i| ema[gs(&m[i], "target")]).fold(f64::NEG_INFINITY, f64::max);
            for &i in &bts {
                let target = gs(&m[i], "target").to_string();
                let want = (DELAY_BASE_MS as f64 + slowest - ema[&target]) / 1000.0;
                let cur = m[i].get("s").and_then(Value::as_f64).unwrap_or(0.0);
                if (want - cur).abs() * 1000.0 >= SYNC_STEP_MS {
                    changes.push((gs(&m[i], "node").to_string(), want));
                    if let Some(o) = m[i].as_object_mut() {
                        o.insert("s".into(), json!(want));
                    }
                }
                let s_now = m[i].get("s").and_then(Value::as_f64).unwrap_or(0.0);
                devices.push(json!({
                    "name": target,
                    "latencyMs": round_half_even(ema[&target]) as i64,
                                   "delayMs": round_half_even(s_now * 1000.0 - DELAY_BASE_MS as f64) as i64,
                }));
            }
        }
        let wired_s = wired_delay_s(read_delay());
        for e in m.iter_mut() {
            if gs(e, "kind") == "wired" {
                let cur = e.get("s").and_then(Value::as_f64).unwrap_or(0.0);
                if (cur - wired_s).abs() > 0.0005 {
                    changes.push((gs(e, "node").to_string(), wired_s));
                    if let Some(o) = e.as_object_mut() {
                        o.insert("s".into(), json!(wired_s));
                    }
                }
            }
        }
        if !changes.is_empty() {
            push_delays(&changes);
            write_json(&paths().delay_map, &Value::Array(m));
        }
        write_json(&paths().bt_status, &json!({"devices": devices}));
        sleep_secs(SYNC_EVERY);
    }
    remove(&paths().bt_status);
    0
}

// ── combine on / off ──

fn combine_on(members: &[String]) -> i32 {
    let sinks = sinks_js();
    let have: Vec<&str> = sinks.iter().map(|x| gs(x, "name")).collect();
    let members: Vec<String> =
    members.iter().filter(|m| have.contains(&m.as_str()) && !hidden(m)).cloned().collect();
    if members.len() < 2 {
        eprintln!("sound-devices: pick at least two outputs");
        return 1;
    }
    let old = pactl(&["get-default-sink"]).trim().to_string();
    if !old.is_empty() && old != COMB && !hidden(&old) {
        make_state_dir();
        let _ = fs::write(&paths().prev, format!("{old}\n"));
    }
    unload_combine();
    stop_sync();
    stop_delay_chain();

    let by = |m: &str| sinks.iter().rev().find(|s| gs(s, "name") == m);
    let lat: HashMap<String, f64> = members
    .iter()
    .filter(|m| by(m).map_or(false, is_bt))
    .map(|m| (m.clone(), bt_latency_ms(m, &sinks)))
    .collect();
    let plan = plan_for(&sinks, &members, &lat);
    let mut slave_of: HashMap<String, String> = HashMap::new();
    if !plan.is_empty() {
        slave_of = start_delay_chain(&plan);
        if slave_of.is_empty() {
            eprintln!("sound-devices: output delay unavailable, combining without it");
        }
    }
    let slaves: Vec<String> = members.iter().map(|m| slave_of.get(m).unwrap_or(m).clone()).collect();

    let loaded = pactl(&[
        "load-module",
        "module-combine-sink",
        &format!("sink_name={COMB}"),
                       &format!("slaves={}", slaves.join(",")),
                       "sink_properties=device.description=Combined-output",
    ]);
    let loaded = loaded.trim();
    if loaded.is_empty() || !loaded.chars().all(|c| c.is_ascii_digit()) {
        stop_delay_chain();
        eprintln!("sound-devices: could not combine the outputs");
        return 1;
    }
    pactl(&["set-default-sink", COMB]);
    if !old.is_empty() && old != COMB {
        move_streams(&old, COMB);
    }
    write_state(&members);
    if !slave_of.is_empty() && plan.iter().any(|p| p.kind == "bt") {
        if let Ok(exe) = env::current_exe() {
            let mut c = cmd(&exe.to_string_lossy());
            c.args(["sound-devices", "sync-loop"]);
            let _ = spawn_detached(&mut c);
        }
    }
    0
}

fn combine_off() -> i32 {
    let members = read_state();
    let have = sink_names();
    let prev = read_lines(&paths().prev).into_iter().next().unwrap_or_default();
    let usable = |n: &String| have.contains(n) && !hidden(n);
    let mut back = if usable(&prev) {
        prev.clone()
    } else {
        members.iter().find(|m| usable(m)).cloned().unwrap_or_default()
    };
    if back.is_empty() {
        back = have.iter().find(|n| !n.is_empty() && !hidden(n)).cloned().unwrap_or_default();
    }
    if pactl(&["get-default-sink"]).trim() == COMB && !back.is_empty() {
        pactl(&["set-default-sink", &back]);
        move_streams(COMB, &back);
    }
    stop_sync();
    unload_combine();
    stop_delay_chain();
    remove(&paths().state);
    remove(&paths().prev);
    0
}

pub fn main(a: &[String]) -> i32 {
    if a.is_empty() {
        return 2;
    }
    let c = a[0].as_str();
    match c {
        "list" => return do_list(),
        "set-profile" if a.len() >= 3 => {
            pactl(&["set-card-profile", &a[1], &a[2]]);
        }
        "set-port" if a.len() >= 4 => {
            pactl(&[&format!("set-{}-port", a[1]), &a[2], &a[3]]);
        }
        "set-default" if a.len() >= 3 => {
            let name = &a[2];
            let old = if a[1] == "sink" { pactl(&["get-default-sink"]).trim().to_string() } else { String::new() };
            pactl(&[&format!("set-default-{}", a[1]), name]);
            if a[1] == "sink" && !old.is_empty() && old != *name {
                move_streams(&old, name);
            } else if a[1] == "source" {
                for line in splitlines(&pactl(&["list", "short", "source-outputs"])) {
                    let first = line.split('\t').next().unwrap_or("");
                    pactl(&["move-source-output", first, name]);
                }
            }
        }
        "volume" if a.len() >= 4 => {
            let vals: Vec<String> = a[3..].iter().map(|v| format!("{}%", v.trim_end_matches('%'))).collect();
            let verb = format!("set-{}-volume", a[1]);
            let mut args: Vec<&str> = vec![&verb, &a[2]];
            args.extend(vals.iter().map(|s| s.as_str()));
            pactl(&args);
        }
        "mute" if a.len() >= 4 => {
            pactl(&[&format!("set-{}-mute", a[1]), &a[2], &a[3]]);
        }
        "combine" if a.len() >= 2 => {
            if a[1] == "on" {
                return combine_on(&a[2..]);
            }
            return combine_off();
        }
        "delay" if a.len() >= 2 => {
            return match a[1].trim().parse::<f64>() {
                Ok(f) if f.is_finite() => set_delay(f),
                _ => 2,
            };
        }
        "sync-loop" => return sync_loop(),
        "restore" => {
            let st = read_state();
            if !st.is_empty() && !sink_names().iter().any(|n| n == COMB) {
                combine_on(&st);
            }
        }
        _ => return 2,
    }
    0
}
