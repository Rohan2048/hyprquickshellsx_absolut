//! battery-info -- 1:1 port of scripts/battery-info.py (Settings > Battery).
//!
//!   info             JSON: percentage, status, power (W), energy (Wh), design capacity, health, cycles,
//!                    manufacturer, model, voltage, time left and the charge-limit capability
//!   sample           log one sample and update the daily totals; also re-applies the saved charge limit
//!                    if the firmware forgot it. Run every ~2 min.
//!   history          JSON: last 24 h of samples + summary, and the last 30 days
//!   limit on|off     stop charging above 80 % (on) or charge to 100 % (off) and remember the choice
//!
//! Files (~/.config/quickshell/state/): battery-history.jsonl, battery-daily.json, battery-limit.json
//! For testing: QS_BATTERY_SYSFS=<dir> replaces /sys/class/power_supply, QS_STATE_DIR=<dir> the state
//! folder, QS_BATTERY=<name> forces the battery.

use crate::pyjson::dumps;
use serde_json::{json, Map, Value};
use std::ffi::{CStr, CString};
use std::fs;
use std::io::{self, Read, Write};
use std::os::unix::ffi::OsStrExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::thread;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};
use std::env;

const KEEP_SAMPLES_S: i64 = 48 * 3600;
const KEEP_DAYS: usize = 60;
const GAP_S: f64 = 900.0; // a hole in the samples longer than this is not counted as use
const LIMIT_PCT: i64 = 80;

// ───────────────────────────── small helpers ──────────────────────────────

fn rd(p: &Path) -> Option<String> {
    fs::read_to_string(p).ok().map(|s| s.trim().to_string())
}

fn num(p: &Path) -> Option<f64> {
    rd(p)?.parse::<f64>().ok()
}

/// Python round(x, n) (exact decimal, half-even), always a float.
fn round_to(x: f64, n: usize) -> f64 {
    format!("{:.*}", n, x).parse().unwrap_or(x)
}

/// Python round(x) with no digits: ties go to the even integer.
fn round_half_even(x: f64) -> f64 {
    if (x - x.trunc()).abs() == 0.5 {
        2.0 * (x / 2.0).round()
    } else {
        x.round()
    }
}

/// Python truthiness of a JSON value.
fn truthy(v: &Value) -> bool {
    match v {
        Value::Null => false,
        Value::Bool(b) => *b,
        Value::Number(n) => n.as_f64().map_or(true, |f| f != 0.0),
        Value::String(s) => !s.is_empty(),
        Value::Array(a) => !a.is_empty(),
        Value::Object(o) => !o.is_empty(),
    }
}

fn fnum(v: &Value, k: &str) -> f64 {
    v.get(k).and_then(Value::as_f64).unwrap_or(0.0)
}

fn fstr<'a>(v: &'a Value, k: &str) -> &'a str {
    v.get(k).and_then(Value::as_str).unwrap_or("")
}

fn unix_now() -> i64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_secs() as i64).unwrap_or(0)
}

extern "C" {
    fn tzset();
}

fn day_of(ts: i64) -> String {
    unsafe {
        tzset();
        let t = ts as libc::time_t;
        let mut tm: libc::tm = std::mem::zeroed();
        libc::localtime_r(&t, &mut tm);
        format!("{:04}-{:02}-{:02}", tm.tm_year + 1900, tm.tm_mon + 1, tm.tm_mday)
    }
}

fn access_x(p: &Path) -> bool {
    match CString::new(p.as_os_str().as_bytes()) {
        Ok(c) => unsafe { libc::access(c.as_ptr(), libc::X_OK) == 0 },
        Err(_) => false,
    }
}

/// shutil.which
fn which(name: &str) -> Option<String> {
    let path = env::var("PATH").unwrap_or_else(|_| "/usr/local/bin:/usr/bin:/bin".into());
    for dir in path.split(':') {
        let p = Path::new(dir).join(name);
        if p.is_file() && access_x(&p) {
            return Some(p.to_string_lossy().into_owned());
        }
    }
    None
}

/// getpass.getuser
fn getuser() -> String {
    for k in ["LOGNAME", "USER", "LNAME", "USERNAME"] {
        if let Ok(v) = env::var(k) {
            if !v.is_empty() {
                return v;
            }
        }
    }
    unsafe {
        let pw = libc::getpwuid(libc::getuid());
        if !pw.is_null() {
            return CStr::from_ptr((*pw).pw_name).to_string_lossy().into_owned();
        }
    }
    String::new()
}

/// str(OSError) for a failed exec: "[Errno 2] No such file or directory: 'sudo'"
fn oserr(e: &io::Error, file: &str) -> String {
    let text = e.to_string();
    let msg = text.split(" (os error").next().unwrap_or(&text);
    format!("[Errno {}] {}: '{}'", e.raw_os_error().unwrap_or(0), msg, file)
}

fn read_json(p: &Path) -> Option<Value> {
    serde_json::from_str(&fs::read_to_string(p).ok()?).ok()
}

// ───────────────────────────── battery reading ──────────────────────────────

struct Battery {
    path: String,
    name: String,
    percent: Option<i64>,
    status: String,
    code: &'static str,
    watts: f64,
    voltage: Option<f64>,
    energy_now: Option<f64>,
    energy_full: Option<f64>,
    energy_design: Option<f64>,
    health: Option<f64>,
    cycles: Option<i64>,
    manufacturer: Option<String>,
    model: Option<String>,
    technology: Option<String>,
    minutes_left: Option<i64>,
}

impl Battery {
    fn to_map(&self) -> Map<String, Value> {
        let mut m = Map::new();
        m.insert("path".into(), json!(self.path));
        m.insert("name".into(), json!(self.name));
        m.insert("percent".into(), json!(self.percent));
        m.insert("status".into(), json!(self.status));
        m.insert("code".into(), json!(self.code));
        m.insert("watts".into(), json!(round_to(self.watts, 2)));
        m.insert("voltage".into(), json!(self.voltage));
        m.insert("energyNow".into(), json!(self.energy_now.map(|x| round_to(x, 2))));
        m.insert("energyFull".into(), json!(self.energy_full.map(|x| round_to(x, 2))));
        m.insert("energyDesign".into(), json!(self.energy_design.map(|x| round_to(x, 2))));
        m.insert("health".into(), json!(self.health));
        m.insert("cycles".into(), json!(self.cycles));
        m.insert("manufacturer".into(), json!(self.manufacturer));
        m.insert("model".into(), json!(self.model));
        m.insert("technology".into(), json!(self.technology));
        m.insert("minutesLeft".into(), json!(self.minutes_left));
        m
    }
}

fn limit_paths(bat: &Path) -> Vec<(&'static str, PathBuf)> {
    let mut out = Vec::new();
    for name in ["charge_control_end_threshold", "charge_stop_threshold"] {
        let p = bat.join(name);
        if p.exists() {
            out.push(("threshold", p));
        }
    }
    let mut cm: Vec<PathBuf> = fs::read_dir("/sys/bus/platform/drivers/ideapad_acpi")
    .into_iter()
    .flatten()
    .flatten()
    .filter(|e| !e.file_name().to_string_lossy().starts_with('.'))
    .map(|e| e.path().join("conservation_mode"))
    .filter(|p| p.exists())
    .collect();
    cm.sort();
    for p in cm {
        out.push(("conservation", p));
    }
    out
}

/// Write a sysfs file: directly if we may, otherwise through passwordless sudo.
fn write_sysfs(path: &Path, value: i64) -> String {
    if let Ok(mut f) = fs::File::create(path) {
        if f.write_all(value.to_string().as_bytes()).is_ok() {
            return String::new();
        }
    }
    let tee = which("tee").unwrap_or_else(|| "/usr/bin/tee".into());
    let ps = path.to_string_lossy().into_owned();
    let mut child = match Command::new("sudo")
    .args(["-n", &tee, &ps])
    .stdin(Stdio::piped())
    .stdout(Stdio::piped())
    .stderr(Stdio::piped())
    .spawn()
    {
        Ok(c) => c,
        Err(e) => return oserr(&e, "sudo"),
    };
    if let Some(mut si) = child.stdin.take() {
        let _ = si.write_all(format!("{}\n", value).as_bytes());
    }
    let mut so = child.stdout.take().unwrap();
    let mut se = child.stderr.take().unwrap();
    let _t1 = thread::spawn(move || {
        let mut b = Vec::new();
        let _ = so.read_to_end(&mut b);
    });
    let t2 = thread::spawn(move || {
        let mut b = Vec::new();
        let _ = se.read_to_end(&mut b);
        String::from_utf8_lossy(&b).into_owned()
    });
    let start = Instant::now();
    loop {
        match child.try_wait() {
            Ok(Some(st)) => {
                if st.success() {
                    return String::new();
                }
                let stderr = t2.join().unwrap_or_default();
                let s = stderr.trim();
                return match s.lines().last() {
                    Some(l) if !s.is_empty() => l.to_string(),
                    _ => "sudo failed".into(),
                };
            }
            Ok(None) => {
                if start.elapsed() >= Duration::from_secs(15) {
                    let _ = child.kill();
                    let _ = child.wait();
                    return format!("Command '['sudo', '-n', '{}', '{}']' timed out after 15 seconds", tee, ps);
                }
                thread::sleep(Duration::from_millis(10));
            }
            Err(e) => return e.to_string(),
        }
    }
}

// ───────────────────────────── the tool ──────────────────────────────

struct Bi {
    ps: String,
    state_dir: PathBuf,
    hist: PathBuf,
    daily: PathBuf,
    limit: PathBuf,
}

impl Bi {
    fn new() -> Self {
        let ps = env::var("QS_BATTERY_SYSFS").unwrap_or_else(|_| "/sys/class/power_supply".into());
        let state_dir = match env::var("QS_STATE_DIR") {
            Ok(d) => PathBuf::from(d),
            Err(_) => Path::new(&env::var("HOME").unwrap_or_else(|_| ".".into())).join(".config/quickshell/state"),
        };
        Bi {
            ps,
            hist: state_dir.join("battery-history.jsonl"),
            daily: state_dir.join("battery-daily.json"),
            limit: state_dir.join("battery-limit.json"),
            state_dir,
        }
    }

    /// The laptop's own battery. Mains adapters and batteries of wireless peripherals (scope Device)
    /// do not count; a desktop has none, so this returns None.
    fn battery_dir(&self) -> Option<PathBuf> {
        if let Ok(forced) = env::var("QS_BATTERY") {
            if !forced.is_empty() {
                return Some(Path::new(&self.ps).join(forced));
            }
        }
        let mut names: Vec<String> = fs::read_dir(&self.ps)
        .ok()?
        .filter_map(|e| e.ok())
        .map(|e| e.file_name().to_string_lossy().into_owned())
        .collect();
        names.sort();
        let mut cands: Vec<PathBuf> = Vec::new();
        for n in names {
            let d = Path::new(&self.ps).join(&n);
            let kind = rd(&d.join("type")).filter(|s| !s.is_empty()).unwrap_or_else(|| {
                if n.starts_with("BAT") { "Battery".into() } else { String::new() }
            });
            if kind != "Battery" {
                continue;
            }
            let scope = rd(&d.join("scope")).filter(|s| !s.is_empty()).unwrap_or_else(|| "System".into());
            if scope.to_lowercase() == "device" {
                continue;
            }
            cands.push(d);
        }
        let pref = cands
        .iter()
        .find(|d| d.file_name().map_or(false, |f| f.to_string_lossy().starts_with("BAT")));
        pref.or(cands.first()).cloned()
    }

    fn state_dir(&self) -> io::Result<()> {
        fs::create_dir_all(&self.state_dir)
    }

    fn write_json(&self, path: &Path, data: &Value) -> io::Result<()> {
        self.state_dir()?;
        let mut tmp = path.as_os_str().to_owned();
        tmp.push(".tmp");
        let tmp = PathBuf::from(tmp);
        fs::write(&tmp, dumps(data, false))?;
        fs::rename(&tmp, path)
    }

    /// Everything the page and the logger need, in Wh / W / V.
    fn read_battery(&self, bat: &Path) -> Battery {
        let g = |n: &str| bat.join(n);
        let vnow = num(&g("voltage_now"));
        let vmin = num(&g("voltage_min_design")).filter(|x| *x != 0.0).or(vnow);
        let v = vnow.unwrap_or(0.0) / 1e6;
        let vref = vmin.unwrap_or(0.0) / 1e6;

        let energy = |ne: &str, nc: &str| -> Option<f64> {
            if let Some(e) = num(&g(ne)) {
                return Some(e / 1e6);
            }
            if let Some(c) = num(&g(nc)) {
                if vref != 0.0 {
                    return Some(c / 1e6 * vref); // µAh -> Wh with the design voltage
                }
            }
            None
        };
        let now = energy("energy_now", "charge_now");
        let full = energy("energy_full", "charge_full");
        let design = energy("energy_full_design", "charge_full_design");

        let watts = match num(&g("power_now")) {
            Some(p) => p.abs() / 1e6,
            None => match num(&g("current_now")) {
                Some(i) if v != 0.0 => i.abs() / 1e6 * v,
                _ => 0.0,
            },
        };

        let status = rd(&g("status")).filter(|s| !s.is_empty()).unwrap_or_else(|| "Unknown".into());
        let nz = |x: Option<f64>| x.filter(|f| *f != 0.0);
        let mut pct = num(&g("capacity"));
        if pct.is_none() {
            if let (Some(n), Some(f)) = (now, nz(full)) {
                pct = Some(n / f * 100.0);
            }
        }
        let health = match (nz(full), nz(design)) {
            (Some(f), Some(d)) => Some(round_to(f / d * 100.0, 1)),
            _ => None,
        };
        let cycles = num(&g("cycle_count"));

        let lower = status.to_lowercase();
        let mut left = None; // minutes
        if watts > 0.5 {
            if let Some(n) = now {
                if lower == "discharging" {
                    left = Some((n / watts * 60.0) as i64);
                } else if lower == "charging" {
                    if let Some(f) = nz(full) {
                        left = Some(((f - n).max(0.0) / watts * 60.0) as i64);
                    }
                }
            }
        }

        let code = match lower.as_str() {
            "charging" => "c",
            "discharging" => "d",
            "full" => "f",
            "not charging" => "n",
            _ => "u",
        };

        Battery {
            path: bat.to_string_lossy().into_owned(),
            name: bat.file_name().map(|f| f.to_string_lossy().into_owned()).unwrap_or_default(),
            percent: pct.map(|p| round_half_even(p) as i64),
            status,
            code,
            watts,
            voltage: (v != 0.0).then(|| round_to(v, 2)),
            energy_now: now,
            energy_full: full,
            energy_design: design,
            health,
            cycles: cycles.map(|c| c as i64),
            manufacturer: rd(&g("manufacturer")),
            model: rd(&g("model_name")),
            technology: rd(&g("technology")),
            minutes_left: left,
        }
    }

    // ───────────────────────────── charge limit ──────────────────────────────

    fn limit_info(&self, bat: Option<&Path>) -> Map<String, Value> {
        let paths = bat.map(limit_paths).unwrap_or_default();
        let saved = read_json(&self.limit).unwrap_or_else(|| json!({}));
        let mut info = Map::new();
        info.insert("supported".into(), json!(false));
        info.insert("kind".into(), json!(""));
        info.insert("path".into(), json!(""));
        info.insert("value".into(), Value::Null);
        info.insert("on".into(), json!(false));
        info.insert("target".into(), json!(LIMIT_PCT));
        info.insert("saved".into(), saved.get("on").cloned().unwrap_or(Value::Null));
        info.insert("error".into(), saved.get("error").cloned().unwrap_or_else(|| json!("")));
        info.insert("sudoers".into(), json!(""));
        let Some((kind, path)) = paths.into_iter().next() else {
            return info;
        };
        let v = num(&path);
        info.insert("supported".into(), json!(true));
        info.insert("kind".into(), json!(kind));
        info.insert("path".into(), json!(path.to_string_lossy()));
        info.insert("value".into(), json!(v.map(|x| x as i64)));
        if let Some(v) = v {
            info.insert("on".into(), json!(if kind == "conservation" { v >= 1.0 } else { v < 100.0 }));
        }
        let tee = which("tee").unwrap_or_else(|| "/usr/bin/tee".into());
        info.insert(
            "sudoers".into(),
                    json!(format!("{} ALL=(root) NOPASSWD: {} {}", getuser(), tee, path.to_string_lossy())),
        );
        info
    }

    fn set_limit(&self, on: bool, remember: bool) -> io::Result<Value> {
        let bat = self.battery_dir();
        let info = self.limit_info(bat.as_deref());
        if info["supported"] != json!(true) {
            return Ok(json!({"ok": false, "error": "This laptop does not expose a charge limit to Linux."}));
        }
        let kind = info["kind"].as_str().unwrap_or("");
        let path = PathBuf::from(info["path"].as_str().unwrap_or(""));
        let value: i64 = if kind == "conservation" {
            on as i64
        } else if on {
            LIMIT_PCT
        } else {
            100
        };
        let mut err = write_sysfs(&path, value);
        let after = num(&path);
        let ok = err.is_empty() && after.map_or(false, |a| a as i64 == value);
        if err.is_empty() && !ok {
            err = format!(
                "The laptop did not accept the value (it reads {}).",
                          after.map_or("nothing".to_string(), |a| (a as i64).to_string())
            );
        }
        let low = err.to_lowercase();
        if low.contains("password") || low.contains("a terminal is required") {
            err = "Needs passwordless sudo for this one file.".into();
        }
        let err_out = if ok { String::new() } else { err };
        if remember {
            self.write_json(&self.limit, &json!({"on": on, "error": err_out}))?;
        }
        Ok(json!({"ok": ok, "error": err_out}))
    }

    /// Some laptops forget the threshold after suspend / a BIOS update: put it back (quietly).
    fn reapply_limit(&self) -> io::Result<()> {
        let Some(saved) = read_json(&self.limit) else { return Ok(()) };
        let Some(want) = saved.as_object().and_then(|o| o.get("on")) else { return Ok(()) };
        let want = truthy(want);
        let info = self.limit_info(self.battery_dir().as_deref());
        if info["supported"] == json!(true) && !info["value"].is_null() && info["on"].as_bool() != Some(want) {
            self.set_limit(want, true)?;
        }
        Ok(())
    }

    // ───────────────────────────── history ──────────────────────────────

    fn read_samples(&self) -> Vec<Value> {
        let mut out = Vec::new();
        if let Ok(txt) = fs::read_to_string(&self.hist) {
            for line in txt.lines() {
                if let Ok(s) = serde_json::from_str::<Value>(line) {
                    if s.as_object().map_or(false, |o| o.contains_key("t")) {
                        out.push(s);
                    }
                }
            }
        }
        out
    }

    fn read_days(&self) -> Map<String, Value> {
        read_json(&self.daily)
        .and_then(|d| d.get("days").and_then(Value::as_object).cloned())
        .unwrap_or_default()
    }

    fn sample(&self) -> io::Result<i32> {
        let Some(bat) = self.battery_dir() else { return Ok(0) };
        let b = self.read_battery(&bat);
        let Some(percent) = b.percent else { return Ok(0) };
        let now = unix_now();
        let mut samples = self.read_samples();
        let prev = samples.last().cloned();
        samples.push(json!({"t": now, "p": percent, "w": round_to(b.watts, 2), "s": b.code}));
        samples.retain(|s| fnum(s, "t") >= (now - KEEP_SAMPLES_S) as f64);
        self.state_dir()?;
        let mut tmp = self.hist.as_os_str().to_owned();
        tmp.push(".tmp");
        let tmp = PathBuf::from(tmp);
        let mut body = String::new();
        for s in &samples {
            body.push_str(&dumps(s, true));
            body.push('\n');
        }
        fs::write(&tmp, body)?;
        fs::rename(&tmp, &self.hist)?;

        // daily totals
        let mut days = self.read_days();
        let fresh = || json!({"used_wh": 0.0, "charged_wh": 0.0});
        let entry = days.entry(day_of(now)).or_insert_with(fresh);
        if !entry.is_object() {
            *entry = fresh();
        }
        let today = entry.as_object_mut().unwrap();
        if let Some(p) = &prev {
            let dt = now as f64 - fnum(p, "t");
            if dt > 0.0 && dt <= GAP_S {
                let wh = fnum(p, "w") * dt / 3600.0;
                match fstr(p, "s") {
                    "d" => {
                        let cur = today.get("used_wh").and_then(Value::as_f64).unwrap_or(0.0);
                        today.insert("used_wh".into(), json!(round_to(cur + wh, 3)));
                    }
                    "c" => {
                        let cur = today.get("charged_wh").and_then(Value::as_f64).unwrap_or(0.0);
                        today.insert("charged_wh".into(), json!(round_to(cur + wh, 3)));
                    }
                    _ => {}
                }
            }
        }
        if let Some(c) = b.cycles {
            today.insert("cycles".into(), json!(c));
        }
        if let Some(h) = b.health {
            today.insert("health".into(), json!(h));
        }
        if let Some(f) = b.energy_full {
            today.insert("full_wh".into(), json!(round_to(f, 2)));
        }
        let mut keys: Vec<String> = days.keys().cloned().collect();
        keys.sort();
        let start = keys.len().saturating_sub(KEEP_DAYS);
        let mut kept = Map::new();
        for k in &keys[start..] {
            kept.insert(k.clone(), days[k.as_str()].clone());
        }
        self.write_json(&self.daily, &json!({"days": kept}))?;

        self.reapply_limit()?;
        Ok(0)
    }

    fn history(&self) -> io::Result<i32> {
        let now = unix_now();
        let pts: Vec<Value> = self
        .read_samples()
        .into_iter()
        .filter(|s| fnum(s, "t") >= (now - 24 * 3600) as f64)
        .collect();
        let days = self.read_days();
        let mut keys: Vec<&String> = days.keys().collect();
        keys.sort();
        let start = keys.len().saturating_sub(30);
        let mut daily: Vec<Value> = keys[start..]
        .iter()
        .map(|k| {
            let mut m = Map::new();
            m.insert("date".into(), json!(k));
            if let Some(o) = days.get(k.as_str()).and_then(Value::as_object) {
                for (kk, vv) in o {
                    m.insert(kk.clone(), vv.clone());
                }
            }
            Value::Object(m)
        })
        .collect();
        daily.reverse(); // newest first
        let summary = summarize(&pts);
        emit(&dumps(&json!({"now": now, "points": pts, "summary": summary, "daily": daily}), true));
        Ok(0)
    }

    fn info(&self) -> io::Result<i32> {
        let Some(bat) = self.battery_dir() else {
            emit(&dumps(&json!({"present": false}), false));
            return Ok(0);
        };
        let mut b = self.read_battery(&bat).to_map();
        b.insert("present".into(), json!(true));
        b.insert("limit".into(), Value::Object(self.limit_info(Some(&bat))));
        emit(&dumps(&Value::Object(b), false));
        Ok(0)
    }
}

fn summarize(points: &[Value]) -> Value {
    let (mut used, mut charged, mut dis_s, mut peak) = (0.0f64, 0.0f64, 0.0f64, 0.0f64);
    for w in points.windows(2) {
        let (a, b) = (&w[0], &w[1]);
        let dt = fnum(b, "t") - fnum(a, "t");
        if dt <= 0.0 || dt > GAP_S {
            continue;
        }
        let wh = fnum(a, "w") * dt / 3600.0;
        match fstr(a, "s") {
            "d" => {
                used += wh;
                dis_s += dt;
                peak = peak.max(fnum(a, "w"));
            }
            "c" => charged += wh,
            _ => {}
        }
    }
    let avg = if dis_s > 0.0 { used / (dis_s / 3600.0) } else { 0.0 };
    json!({
        "usedWh": round_to(used, 2),
          "chargedWh": round_to(charged, 2),
          "avgW": round_to(avg, 1),
          "peakW": round_to(peak, 1),
          "samples": points.len(),
    })
}

fn emit(s: &str) {
    let mut o = io::stdout().lock();
    let _ = writeln!(o, "{s}");
}

pub fn main(a: &[String]) -> i32 {
    let bi = Bi::new();
    let r = match a.first().map(String::as_str) {
        Some("info") => bi.info(),
        Some("sample") => bi.sample(),
        Some("history") => bi.history(),
        Some("limit") if a.len() >= 2 && (a[1] == "on" || a[1] == "off") => {
            bi.set_limit(a[1] == "on", true).map(|v| {
                emit(&dumps(&v, false));
                0
            })
        }
        _ => return 2,
    };
    match r {
        Ok(c) => c,
        Err(e) => {
            eprintln!("battery-info: {e}");
            1
        }
    }
}
