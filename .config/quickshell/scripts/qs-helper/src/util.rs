//! Helpers shared by the audio ports (audio-ports, sound-devices).

use serde_json::Value;
use std::io::{self, Read, Write};
use std::os::unix::process::CommandExt;
use std::process::{Command, Stdio};
use std::thread;
use std::time::{Duration, Instant};

/// A command with the same environment the Python scripts used (LC_ALL=C, LANG=C).
pub fn cmd(prog: &str) -> Command {
    let mut c = Command::new(prog);
    c.env("LC_ALL", "C").env("LANG", "C");
    c
}

/// pactl <args>  -> stdout ("" when pactl is missing)
pub fn pactl(args: &[&str]) -> String {
    match cmd("pactl").args(args).output() {
        Ok(o) => String::from_utf8_lossy(&o.stdout).into_owned(),
        Err(_) => String::new(),
    }
}

/// pactl -f json <args>  -> None when pactl is missing, [] when the output is not JSON.
pub fn pactl_js(args: &[&str]) -> Option<Vec<Value>> {
    let o = cmd("pactl").arg("-f").arg("json").args(args).output().ok()?;
    let txt = String::from_utf8_lossy(&o.stdout).into_owned();
    let txt = if txt.is_empty() { "[]".to_string() } else { txt };
    match serde_json::from_str::<Value>(&txt) {
        Ok(Value::Array(a)) => Some(a),
        _ => Some(Vec::new()),
    }
}

/// Python round(x) (ties to even).
pub fn round_half_even(x: f64) -> f64 {
    if (x - x.trunc()).abs() == 0.5 {
        2.0 * (x / 2.0).round()
    } else {
        x.round()
    }
}

/// Python truthiness of a JSON value.
pub fn truthy(v: &Value) -> bool {
    match v {
        Value::Null => false,
        Value::Bool(b) => *b,
        Value::Number(n) => n.as_f64().map_or(true, |f| f != 0.0),
        Value::String(s) => !s.is_empty(),
        Value::Array(a) => !a.is_empty(),
        Value::Object(o) => !o.is_empty(),
    }
}

/// Python str(value) for the JSON types we meet.
pub fn py_str(v: &Value) -> String {
    match v {
        Value::Null => "None".into(),
        Value::Bool(b) => if *b { "True" } else { "False" }.into(),
        Value::String(s) => s.clone(),
        Value::Number(n) if n.is_f64() => crate::pyjson::float_repr(n.as_f64().unwrap()),
        Value::Number(n) => n.to_string(),
        other => other.to_string(),
    }
}

/// Python str.splitlines().
pub fn splitlines(s: &str) -> Vec<&str> {
    let mut out = Vec::new();
    let mut start = 0;
    let mut it = s.char_indices().peekable();
    while let Some((i, c)) = it.next() {
        if matches!(c, '\n' | '\r' | '\u{b}' | '\u{c}' | '\u{1c}' | '\u{1d}' | '\u{1e}' | '\u{85}' | '\u{2028}' | '\u{2029}') {
            out.push(&s[start..i]);
            let mut end = i + c.len_utf8();
            if c == '\r' {
                if let Some(&(j, '\n')) = it.peek() {
                    it.next();
                    end = j + 1;
                }
            }
            start = end;
        }
    }
    if start < s.len() {
        out.push(&s[start..]);
    }
    out
}

/// Python str.partition(sep) -> (before, after)
pub fn partition<'a>(s: &'a str, sep: char) -> (&'a str, &'a str) {
    match s.split_once(sep) {
        Some((a, b)) => (a, b),
        None => (s, ""),
    }
}

pub fn sleep_secs(s: f64) {
    thread::sleep(Duration::from_secs_f64(s));
}

/// Write a line to stdout and flush; false when stdout is gone (broken pipe).
pub fn out(s: &str) -> bool {
    let mut o = io::stdout().lock();
    writeln!(o, "{s}").and_then(|_| o.flush()).is_ok()
}

pub enum RunErr {
    Spawn,
    Timeout,
}

/// subprocess.run(capture_output=True, timeout=...) -> (exit code, stdout, stderr)
pub fn run_timeout(c: &mut Command, timeout: Duration) -> Result<(Option<i32>, String, String), RunErr> {
    c.stdin(Stdio::null()).stdout(Stdio::piped()).stderr(Stdio::piped());
    let mut child = c.spawn().map_err(|_| RunErr::Spawn)?;
    let mut so = child.stdout.take().unwrap();
    let mut se = child.stderr.take().unwrap();
    let t1 = thread::spawn(move || {
        let mut b = Vec::new();
        let _ = so.read_to_end(&mut b);
        b
    });
    let t2 = thread::spawn(move || {
        let mut b = Vec::new();
        let _ = se.read_to_end(&mut b);
        b
    });
    let start = Instant::now();
    loop {
        match child.try_wait() {
            Ok(Some(st)) => {
                let o = t1.join().unwrap_or_default();
                let e = t2.join().unwrap_or_default();
                return Ok((
                    st.code(),
                           String::from_utf8_lossy(&o).into_owned(),
                           String::from_utf8_lossy(&e).into_owned(),
                ));
            }
            Ok(None) => {
                if start.elapsed() >= timeout {
                    let _ = child.kill();
                    let _ = child.wait();
                    return Err(RunErr::Timeout);
                }
                thread::sleep(Duration::from_millis(10));
            }
            Err(_) => return Err(RunErr::Spawn),
        }
    }
}

/// Popen(..., stdin/stdout/stderr=DEVNULL, start_new_session=True) without waiting for it.
pub fn spawn_detached(c: &mut Command) -> io::Result<()> {
    c.stdin(Stdio::null()).stdout(Stdio::null()).stderr(Stdio::null());
    unsafe {
        c.pre_exec(|| {
            libc::setsid();
            Ok(())
        });
    }
    c.spawn().map(|_| ())
}
