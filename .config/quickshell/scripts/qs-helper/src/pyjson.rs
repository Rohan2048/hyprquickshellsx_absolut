//! Python-compatible `json.dumps` (ensure_ascii=True, float repr, default or compact separators),
//! so output stays byte-identical to what the Python scripts printed.

use serde_json::Value;

/// compact=false -> json.dumps(v)                      (", " and ": ")
/// compact=true  -> json.dumps(v, separators=(",", ":"))
pub fn dumps(v: &Value, compact: bool) -> String {
    let mut out = String::new();
    write(v, compact, &mut out);
    out
}

fn write(v: &Value, compact: bool, out: &mut String) {
    let (item_sep, key_sep) = if compact { (",", ":") } else { (", ", ": ") };
    match v {
        Value::Null => out.push_str("null"),
        Value::Bool(b) => out.push_str(if *b { "true" } else { "false" }),
        Value::Number(n) => match n.as_f64().filter(|_| n.is_f64()) {
            Some(f) => out.push_str(&float_repr(f)),
            None => out.push_str(&n.to_string()),
        },
        Value::String(s) => string(s, out),
        Value::Array(a) => {
            out.push('[');
            for (i, x) in a.iter().enumerate() {
                if i > 0 {
                    out.push_str(item_sep);
                }
                write(x, compact, out);
            }
            out.push(']');
        }
        Value::Object(m) => {
            out.push('{');
            for (i, (k, x)) in m.iter().enumerate() {
                if i > 0 {
                    out.push_str(item_sep);
                }
                string(k, out);
                out.push_str(key_sep);
                write(x, compact, out);
            }
            out.push('}');
        }
    }
}

fn string(s: &str, out: &mut String) {
    out.push('"');
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            '\u{8}' => out.push_str("\\b"),
            '\u{c}' => out.push_str("\\f"),
            c if (' '..='~').contains(&c) => out.push(c),
            c => {
                let mut buf = [0u16; 2];
                for u in c.encode_utf16(&mut buf) {
                    out.push_str(&format!("\\u{:04x}", u));
                }
            }
        }
    }
    out.push('"');
}

/// Python's repr(float).
pub fn float_repr(f: f64) -> String {
    if f.is_nan() {
        return "NaN".into();
    }
    if f.is_infinite() {
        return if f > 0.0 { "Infinity" } else { "-Infinity" }.into();
    }
    if f == 0.0 {
        return if f.is_sign_negative() { "-0.0" } else { "0.0" }.into();
    }
    let s = format!("{:e}", f.abs()); // shortest round-trip digits, e.g. "1.2345e2"
    let (mant, exp) = s.split_once('e').unwrap();
    let exp: i32 = exp.parse().unwrap();
    let digits: String = mant.chars().filter(|c| *c != '.').collect();
    let sign = if f < 0.0 { "-" } else { "" };
    let n = digits.len() as i32;
    if (-4..16).contains(&exp) {
        if exp >= 0 {
            if n <= exp + 1 {
                format!("{sign}{digits}{}.0", "0".repeat((exp + 1 - n) as usize))
            } else {
                let (a, b) = digits.split_at((exp + 1) as usize);
                format!("{sign}{a}.{b}")
            }
        } else {
            format!("{sign}0.{}{digits}", "0".repeat((-exp - 1) as usize))
        }
    } else {
        let (first, rest) = digits.split_at(1);
        let m = if rest.is_empty() { first.to_string() } else { format!("{first}.{rest}") };
        format!("{sign}{m}e{}{:02}", if exp < 0 { "-" } else { "+" }, exp.abs())
    }
}
