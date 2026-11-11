//! qs-helper — one binary replacing the Python/shell helpers in ~/.config/quickshell/scripts.
//!
//!   qs-helper battery-info info|sample|history|limit on|off     (was scripts/battery-info.py)
//!   qs-helper audio-ports  list|listen|set <card> <port>|debug  (was scripts/audio-ports.py)
//!   qs-helper sound-devices <command> ...                       (was scripts/sound-devices.py)

mod audio_ports;
mod battery_info;
mod pyjson;
mod sound_devices;
mod util;

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let code = match args.first().map(String::as_str) {
        Some("battery-info") => battery_info::main(&args[1..]),
        Some("audio-ports") => audio_ports::main(&args[1..]),
        Some("sound-devices") => sound_devices::main(&args[1..]),
        _ => {
            eprintln!("usage: qs-helper battery-info|audio-ports|sound-devices ...");
            2
        }
    };
    std::process::exit(code);
}
