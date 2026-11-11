//! audio-ports -- 1:1 port of scripts/audio-ports.py (raw output-port enumeration for VolumePopup).
//!
//!   list                 one-shot JSON on stdout
//!   listen               same JSON, re-emitted on pactl card/sink/server events
//!                        (trailing-debounced, duplicate payloads suppressed)
//!   set <card> <port>    activate a port: switch card profile if needed, set the sink's active port,
//!                        make it the default sink, and move existing streams onto it
//!   debug                human-readable dump of what the parser sees
//!
//! JSON shape: {"defaultSink","activeKey","ports":[entry],"pinned":[entry]}, entry =
//!   key, card, cardIndex, cardLabel, port, label, type, avail, present, active, sink, sinkDesc, profiles
//! "ports" entries whose port is "not available" are dropped; "pinned" (built-in speaker) never are.

use crate::pyjson::dumps;
use crate::util::{cmd, out, partition, pactl, sleep_secs, splitlines};
use serde_json::{json, Value};
use std::io::{BufRead, BufReader};
use std::os::unix::process::CommandExt;
use std::process::Stdio;
use std::sync::mpsc::{self, RecvTimeoutError};
use std::thread;
use std::time::{Duration, Instant};

// ── Card/port classification ─────────────────────────────────────────────
const HIDE_CARD_PREFIXES: [&str; 1] = ["bluez_card."];
const PINNED_PORT_NAMES: [&str; 2] = ["analog-output-speaker", "analog-output-speaker-always"];
const INPUT_NAME_HINTS: [&str; 5] = ["input", "mic", "capture", "line-in", "linein"];
const OUTPUT_NAME_HINTS: [&str; 10] = [
    "output", "hdmi", "displayport", "speaker", "headphone", "lineout", "line-out", "iec958", "spdif", "digital",
];
const INPUT_TYPES: [&str; 2] = ["mic", "microphone"];

struct Profile {
    desc: String,
    priority: i64,
    available: bool,
}

struct Port {
    name: String,
    desc: String,
    ty: String,
    priority: i64,
    avail: &'static str,
    profiles: Vec<String>,
}

struct Card {
    index: i64,
    name: String,
    desc: String,
    active_profile: String,
    profiles: Vec<(String, Profile)>, // insertion-ordered dict
    ports: Vec<Port>,
}

struct Sink {
    name: String,
    desc: String,
    card: i64,
    alsa_card: i64,
    active_port: String,
    ports: Vec<String>,
}

struct Entry {
    key: String,
    card: String,
    card_index: i64,
    card_label: String,
    port: String,
    label: String,
    ty: String,
    avail: &'static str,
    present: bool,
    active: bool,
    sink: String,
    sink_desc: String,
    profiles: Vec<String>,
    priority: i64,
}

impl Entry {
    fn to_value(&self) -> Value {
        json!({
            "key": self.key,
            "card": self.card,
            "cardIndex": self.card_index,
            "cardLabel": self.card_label,
            "port": self.port,
            "label": self.label,
            "type": self.ty,
            "avail": self.avail,
            "present": self.present,
            "active": self.active,
            "sink": self.sink,
            "sinkDesc": self.sink_desc,
            "profiles": self.profiles,
        })
    }
}

// ───────────────────────────── text helpers ──────────────────────────────

/// pactl indents with tabs; some builds/locales use 4 spaces.
fn indent_of(line: &str) -> usize {
    let t = line.trim_start_matches('\t');
    if t.len() != line.len() {
        return line.len() - t.len();
    }
    let s = line.trim_start_matches(' ');
    (line.len() - s.len()) / 4
}

/// ENTRY_RE = ^(?P<name>\S+):\s+(?P<desc>.*)\((?P<meta>[^()]*)\)\s*$   -> (name, desc, meta)
fn entry_re(s: &str) -> Option<(String, String, String)> {
    let tok_end = s.find(char::is_whitespace)?;
    let tok = &s[..tok_end];
    if tok.len() < 2 || !tok.ends_with(':') {
        return None;
    }
    let name = &tok[..tok.len() - 1];
    let rest = s[tok_end..].trim_start();
    let inner = rest.trim_end().strip_suffix(')')?;
    let idx = inner.rfind('(')?;
    let meta = &inner[idx + 1..];
    if meta.contains(')') {
        return None;
    }
    Some((name.to_string(), inner[..idx].to_string(), meta.to_string()))
}

/// re.search(re.escape(key) + r":\s*([^,)]+)", meta) -> stripped group, "" when no match
fn meta_field(meta: &str, key: &str) -> String {
    let pat = format!("{key}:");
    for (i, _) in meta.match_indices(&pat) {
        let rest = &meta[i + pat.len()..];
        let ws = rest.len() - rest.trim_start().len();
        let after = &rest[ws..];
        let run_end = after.find(|c| c == ',' || c == ')').unwrap_or(after.len());
        if run_end > 0 {
            return after[..run_end].trim().to_string();
        }
        if ws > 0 {
            return String::new(); // regex backtracks: the group is one whitespace char -> ""
        }
    }
    String::new()
}

fn parse_int(s: &str) -> i64 {
    s.trim().parse().unwrap_or(0)
}

fn availability(meta: &str) -> &'static str {
    for tok in meta.split(',').map(|t| t.trim().to_lowercase()) {
        match tok.as_str() {
            "not available" => return "no",
            "available" => return "yes",
            "availability unknown" => return "unknown",
            _ => {}
        }
    }
    "unknown"
}

/// re.match(r"<word>\s+#(\d+)", s) -> the number
fn hash_index(s: &str, word: &str) -> Option<i64> {
    let rest = s.strip_prefix(word)?;
    let t = rest.trim_start();
    if t.len() == rest.len() {
        return None;
    }
    let t = t.strip_prefix('#')?;
    let d: String = t.chars().take_while(|c| c.is_ascii_digit()).collect();
    if d.is_empty() {
        None
    } else {
        d.parse().ok()
    }
}

/// 'alsa_card.pci-0000_00_1f.3' -> 'pci-0000_00_1f.3'
fn card_stem(card_name: &str) -> &str {
    match card_name.split_once('.') {
        Some((_, b)) => b,
        None => card_name,
    }
}

// ─────────────────────────────── parsing ────────────────────────────────

#[derive(PartialEq, Clone, Copy)]
enum Sect {
    None,
    CardProps,
    Profiles,
    Ports,
    SinkProps,
}

fn parse_cards() -> Vec<Card> {
    let mut cards: Vec<Card> = Vec::new();
    let mut section = Sect::None;
    let text = pactl(&["list", "cards"]);

    for raw in splitlines(&text) {
        if raw.trim().is_empty() {
            continue;
        }
        let (ind, s) = (indent_of(raw), raw.trim());

        if ind == 0 {
            if let Some(n) = hash_index(s, "Card") {
                cards.push(Card {
                    index: n,
                    name: String::new(),
                           desc: String::new(),
                           active_profile: String::new(),
                           profiles: Vec::new(),
                           ports: Vec::new(),
                });
                section = Sect::None;
            }
            continue;
        }

        let Some(cur) = cards.last_mut() else { continue };

        if ind == 1 {
            let (key, val) = partition(s, ':');
            let (key, val) = (key.trim(), val.trim());
            section = Sect::None;
            match key {
                "Name" => cur.name = val.to_string(),
                "Active Profile" => cur.active_profile = val.to_string(),
                "Properties" => section = Sect::CardProps,
                "Profiles" => section = Sect::Profiles,
                "Ports" => section = Sect::Ports,
                _ => {}
            }
            continue;
        }

        if ind == 2 {
            match section {
                Sect::CardProps => {
                    let (k, v) = partition(s, '=');
                    if (k.trim() == "device.description" || k.trim() == "alsa.card_name") && cur.desc.is_empty() {
                        cur.desc = v.trim().trim_matches('"').to_string();
                    }
                }
                Sect::Profiles => {
                    if let Some((name, desc, meta)) = entry_re(s) {
                        let name = name.trim_end_matches(':').to_string();
                        let p = Profile {
                            desc: desc.trim().to_string(),
                            priority: parse_int(&meta_field(&meta, "priority")),
                            available: meta_field(&meta, "available").to_lowercase() != "no",
                        };
                        match cur.profiles.iter_mut().find(|(n, _)| *n == name) {
                            Some(slot) => slot.1 = p,
                            None => cur.profiles.push((name, p)),
                        }
                    }
                }
                Sect::Ports => {
                    if let Some((name, desc, meta)) = entry_re(s) {
                        cur.ports.push(Port {
                            name: name.trim_end_matches(':').to_string(),
                                       desc: desc.trim().to_string(),
                                       ty: meta_field(&meta, "type"),
                                       priority: parse_int(&meta_field(&meta, "priority")),
                                       avail: availability(&meta),
                                       profiles: Vec::new(),
                        });
                    }
                }
                _ => {}
            }
            continue;
        }

        if ind == 3 && section == Sect::Ports && !cur.ports.is_empty() {
            if s.starts_with("Part of profile(s):") {
                let lst = s.split_once(':').map(|x| x.1).unwrap_or("");
                let last = cur.ports.len() - 1;
                cur.ports[last].profiles =
                lst.split(',').map(|p| p.trim().to_string()).filter(|p| !p.is_empty()).collect();
            }
        }
    }
    cards
}

fn is_digits(v: &str) -> bool {
    !v.is_empty() && v.chars().all(|c| c.is_ascii_digit())
}

fn parse_sinks() -> Vec<Sink> {
    let mut sinks: Vec<Sink> = Vec::new();
    let mut section = Sect::None;
    let text = pactl(&["list", "sinks"]);

    for raw in splitlines(&text) {
        if raw.trim().is_empty() {
            continue;
        }
        let (ind, s) = (indent_of(raw), raw.trim());

        if ind == 0 {
            if hash_index(s, "Sink").is_some() {
                sinks.push(Sink {
                    name: String::new(),
                           desc: String::new(),
                           card: -1,
                           alsa_card: -1,
                           active_port: String::new(),
                           ports: Vec::new(),
                });
                section = Sect::None;
            }
            continue;
        }

        let Some(cur) = sinks.last_mut() else { continue };

        if ind == 1 {
            let (key, val) = partition(s, ':');
            let (key, val) = (key.trim(), val.trim());
            section = Sect::None;
            match key {
                "Name" => cur.name = val.to_string(),
                "Description" => cur.desc = val.to_string(),
                "Card" => {
                    // PulseAudio only
                    let digits: String = val.chars().filter(|c| c.is_ascii_digit()).collect();
                    cur.card = if digits.is_empty() { -1 } else { digits.parse().unwrap_or(-1) };
                }
                "Active Port" => cur.active_port = val.trim_matches('"').to_string(),
                "Ports" => section = Sect::Ports,
                "Properties" => section = Sect::SinkProps,
                _ => {}
            }
            continue;
        }

        if ind >= 2 && section == Sect::SinkProps {
            let (k, v) = partition(s, '=');
            let (k, v) = (k.trim(), v.trim().trim_matches('"'));
            if k == "device.id" && cur.card == -1 && is_digits(v) {
                cur.card = v.parse().unwrap_or(-1);
            } else if k == "alsa.card" && is_digits(v) {
                cur.alsa_card = v.parse().unwrap_or(-1);
            }
            continue;
        }

        if ind >= 2 && section == Sect::Ports {
            // tolerate both "name: Desc (meta)" and a bare "name: Desc"
            let pname = match entry_re(s) {
                Some((n, _, _)) => n,
                None => partition(s, ':').0.to_string(),
            };
            let pname = pname.trim().trim_end_matches(':');
            if !pname.is_empty() {
                cur.ports.push(pname.to_string());
            }
            continue;
        }
    }
    sinks
}

// ──────────────────────────────── model ─────────────────────────────────

fn is_output_port(port: &Port) -> bool {
    let n = port.name.to_lowercase();
    if INPUT_NAME_HINTS.iter().any(|h| n.contains(h)) && !["output", "lineout"].iter().any(|h| n.contains(h)) {
        return false;
    }
    if INPUT_TYPES.contains(&port.ty.to_lowercase().as_str()) {
        return false;
    }
    if OUTPUT_NAME_HINTS.iter().any(|h| n.contains(h)) {
        return true;
    }
    // last resort: belongs to a profile that is output-only
    port.profiles.iter().any(|p| p.starts_with("output:") && !p.contains("+input:"))
}

/// Active profile as a set: the whole string plus each +-joined half.
fn profile_parts(card: &Card) -> Vec<String> {
    let ap = &card.active_profile;
    let mut parts = vec![ap.clone()];
    for p in ap.split('+').filter(|p| !p.is_empty()) {
        if !parts.iter().any(|x| x == p) {
            parts.push(p.to_string());
        }
    }
    parts
}

fn sinks_of_card<'a>(card: &Card, sinks: &'a [Sink]) -> Vec<&'a Sink> {
    let owned: Vec<&Sink> = sinks.iter().filter(|s| s.card == card.index && s.card != -1).collect();
    if !owned.is_empty() {
        return owned;
    }
    let stem = card_stem(&card.name);
    sinks.iter().filter(|s| !stem.is_empty() && s.name.contains(stem)).collect()
}

fn make_entry(c: &Card, p: &Port, card_sinks: &[&Sink], active_profiles: &[String], default_sink: &str) -> (Entry, bool) {
    let present = if p.profiles.is_empty() {
        false
    } else {
        p.profiles.iter().any(|pf| active_profiles.contains(pf))
    };

    let sink = card_sinks
    .iter()
    .find(|s| s.ports.contains(&p.name))
    .or_else(|| card_sinks.iter().find(|s| s.active_port == p.name))
    .copied();

    let port_is_active = match sink {
        Some(s) => {
            if !s.active_port.is_empty() {
                s.active_port == p.name
            } else {
                s.ports.len() <= 1
            }
        }
        None => false,
    };

    let is_active = present && sink.map_or(false, |s| s.name == default_sink) && port_is_active;

    (
        Entry {
            key: format!("{}|{}", c.name, p.name),
     card: c.name.clone(),
     card_index: c.index,
     card_label: c.desc.clone(),
     port: p.name.clone(),
     label: if p.desc.is_empty() { p.name.clone() } else { p.desc.clone() },
     ty: p.ty.clone(),
     avail: p.avail,
     present,
     active: is_active,
     sink: sink.map(|s| s.name.clone()).unwrap_or_default(),
     sink_desc: sink.map(|s| s.desc.clone()).unwrap_or_default(),
     profiles: p.profiles.clone(),
     priority: p.priority,
        },
     is_active,
    )
}

fn build() -> Value {
    let cards = parse_cards();
    let sinks = parse_sinks();
    let default_sink = pactl(&["get-default-sink"]).trim().to_string();

    let mut ports: Vec<Entry> = Vec::new();
    let mut pinned: Vec<Entry> = Vec::new();
    let mut active_key = String::new();

    for c in &cards {
        if HIDE_CARD_PREFIXES.iter().any(|p| c.name.starts_with(p)) {
            continue;
        }
        let card_sinks = sinks_of_card(c, &sinks);
        let active_profiles = profile_parts(c);

        for p in &c.ports {
            if p.avail == "no" || !is_output_port(p) {
                continue;
            }
            let (entry, is_active) = make_entry(c, p, &card_sinks, &active_profiles, &default_sink);
            if is_active {
                active_key = entry.key.clone();
            }
            if PINNED_PORT_NAMES.contains(&p.name.as_str()) {
                pinned.push(entry);
            } else {
                ports.push(entry);
            }
        }
    }

    // plugged-in things first, then card order, then port priority
    ports.sort_by_key(|e| (e.avail != "yes", e.card_index, -e.priority));
    pinned.sort_by_key(|e| (e.card_index, -e.priority));

    json!({
        "defaultSink": default_sink,
        "activeKey": active_key,
        "ports": ports.iter().map(Entry::to_value).collect::<Vec<_>>(),
          "pinned": pinned.iter().map(Entry::to_value).collect::<Vec<_>>(),
    })
}

// ────────────────────────────── activation ──────────────────────────────

/// Best profile that exposes this port, preserving the current input half.
fn choose_profile(card: &Card, port: &Port) -> String {
    let find = |n: &str| card.profiles.iter().find(|(k, _)| k == n).map(|(_, p)| p);
    let usable: Vec<&String> = port.profiles.iter().filter(|p| find(p).is_some()).collect();
    let avail: Vec<&String> = usable.iter().copied().filter(|p| find(p).unwrap().available).collect();
    let cands = if avail.is_empty() { usable } else { avail };
    if cands.is_empty() {
        return String::new();
    }

    // Prefer a pure output profile with the highest priority, then try to re-attach whatever input half
    // the card is currently using so switching to HDMI doesn't silently kill the microphone.
    let mut pure: Vec<&String> = cands.iter().copied().filter(|p| !p.contains("+input:")).collect();
    if pure.is_empty() {
        pure = cands.clone();
    }
    pure.sort_by_key(|p| (-find(p).unwrap().priority, p.len()));
    let best = pure[0];

    let inputs: Vec<&str> = card.active_profile.split('+').filter(|p| p.starts_with("input:")).collect();
    if !inputs.is_empty() && !best.contains("+input:") {
        let combined = format!("{}+{}", best, inputs[0]);
        if let Some(p) = find(&combined) {
            if p.available {
                return combined;
            }
        }
    }
    best.clone()
}

fn activate(card_name: &str, port_name: &str) -> i32 {
    let cards = parse_cards();
    let Some(card) = cards.iter().find(|c| c.name == card_name) else {
        eprintln!("audio-ports: no such card: {card_name}");
        return 1;
    };
    let Some(port) = card.ports.iter().find(|p| p.name == port_name) else {
        eprintln!("audio-ports: no such port: {port_name}");
        return 1;
    };

    let parts = profile_parts(card);
    if !port.profiles.iter().any(|pf| parts.contains(pf)) {
        let prof = choose_profile(card, port);
        if !prof.is_empty() {
            pactl(&["set-card-profile", card_name, &prof]);
        }
    }

    // the sink may take a moment to appear after a profile switch
    let mut sink_name: Option<String> = None;
    let deadline = Instant::now() + Duration::from_secs_f64(3.0);
    while Instant::now() < deadline {
        let all = parse_sinks();
        let on_card = sinks_of_card(card, &all);
        let mut sink = on_card.iter().find(|s| s.ports.iter().any(|p| p == port_name)).copied();
        if sink.is_none() && on_card.len() == 1 {
            sink = Some(on_card[0]);
        }
        if let Some(s) = sink {
            sink_name = Some(s.name.clone());
            break;
        }
        sleep_secs(0.1);
    }

    let Some(sink) = sink_name else {
        eprintln!("audio-ports: no sink exposes {port_name}");
        return 1;
    };

    pactl(&["set-sink-port", &sink, port_name]);
    pactl(&["set-default-sink", &sink]);

    // drag anything already playing over to the new output
    let inputs = pactl(&["list", "short", "sink-inputs"]);
    for line in splitlines(&inputs) {
        let sid = line.split('\t').next().unwrap_or("").trim();
        if !sid.is_empty() && sid.chars().all(|c| c.is_ascii_digit()) {
            pactl(&["move-sink-input", sid, &sink]);
        }
    }
    0
}

// ─────────────────────────────── entry point ────────────────────────────

fn emit() -> bool {
    out(&dumps(&build(), true))
}

/// re.search(r"\b(card|sink|server)\b", line)
fn interesting(line: &str) -> bool {
    line.split(|c: char| !(c.is_alphanumeric() || c == '_'))
    .any(|w| w == "card" || w == "sink" || w == "server")
}

fn listen() -> i32 {
    if !emit() {
        return 0;
    }
    let mut c = cmd("pactl");
    c.arg("subscribe").stdout(Stdio::piped());
    unsafe {
        // don't leave `pactl subscribe` behind if we get killed
        c.pre_exec(|| {
            libc::prctl(libc::PR_SET_PDEATHSIG, libc::SIGTERM);
            Ok(())
        });
    }
    let mut child = match c.spawn() {
        Ok(ch) => ch,
        Err(e) => {
            eprintln!("audio-ports: cannot run pactl subscribe: {e}");
            return 1;
        }
    };
    let stdout = child.stdout.take().unwrap();
    let (tx, rx) = mpsc::channel::<String>();
    thread::spawn(move || {
        let mut r = BufReader::new(stdout);
        let mut buf = Vec::new();
        loop {
            buf.clear();
            match r.read_until(b'\n', &mut buf) {
                Ok(0) | Err(_) => break,
                  Ok(_) => {
                      if tx.send(String::from_utf8_lossy(&buf).into_owned()).is_err() {
                          break;
                      }
                  }
            }
        }
    });

    let mut last: Option<String> = None;
    let mut pending = false;
    loop {
        let ev = if pending {
            rx.recv_timeout(Duration::from_millis(200))
        } else {
            rx.recv().map_err(|_| RecvTimeoutError::Disconnected)
        };
        match ev {
            Ok(line) => {
                if interesting(&line) {
                    pending = true;
                }
            }
            Err(RecvTimeoutError::Timeout) => {
                pending = false;
                let payload = dumps(&build(), true);
                if last.as_deref() != Some(payload.as_str()) {
                    // suppress no-op churn
                    if !out(&payload) {
                        break;
                    }
                    last = Some(payload);
                }
            }
            Err(RecvTimeoutError::Disconnected) => break,
        }
    }
    0
}

fn debug() {
    let cards = parse_cards();
    let sinks = parse_sinks();
    for c in &cards {
        let hidden = HIDE_CARD_PREFIXES.iter().any(|p| c.name.starts_with(p));
        println!(
            "Card #{}  {}  ({}){}",
                 c.index,
                 c.name,
                 c.desc,
                 if hidden { "  [CARD HIDDEN]" } else { "" }
        );
        println!("  active profile: {}", c.active_profile);
        let matched: Vec<&str> = sinks_of_card(c, &sinks).iter().map(|s| s.name.as_str()).collect();
        println!("  sinks matched : {}", if matched.is_empty() { "(none)".to_string() } else { matched.join(", ") });
        for p in &c.ports {
            let mut flags: Vec<&str> = Vec::new();
            if !is_output_port(p) {
                flags.push("INPUT");
            }
            if PINNED_PORT_NAMES.contains(&p.name.as_str()) {
                flags.push("PINNED");
            }
            if p.avail == "no" {
                flags.push("UNPLUGGED");
            }
            println!(
                "    {:<28} {:<26} avail={:<7} type={:<10} {}",
                p.name,
                p.desc,
                p.avail,
                p.ty,
                if flags.is_empty() { "[SHOWN]".to_string() } else { format!("[{}]", flags.join(",")) }
            );
        }
    }
    println!();
    for s in &sinks {
        println!(
            "Sink card={:<4} alsa={:<3} {:<52} activePort={:<26} ports={}",
            s.card,
            s.alsa_card,
            s.name,
            s.active_port,
            if s.ports.is_empty() { "(none parsed)".to_string() } else { s.ports.join(",") }
        );
    }
    println!();
    println!("default sink: {}", pactl(&["get-default-sink"]).trim());
}

const USAGE: &str = "audio-ports: list | listen | set <card> <port> | debug";

pub fn main(a: &[String]) -> i32 {
    let mode = a.first().map(String::as_str).unwrap_or("list");
    match mode {
        "list" => {
            emit();
            0
        }
        "listen" => listen(),
        "set" => {
            if a.len() < 3 {
                eprintln!("{USAGE}");
                return 1;
            }
            activate(&a[1], &a[2])
        }
        "debug" => {
            debug();
            0
        }
        _ => {
            println!("{USAGE}");
            2
        }
    }
}
