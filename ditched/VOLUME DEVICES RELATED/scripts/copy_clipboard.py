#!/usr/bin/env python3
"""Copy a PNG screenshot to the Wayland clipboard.

Usage: copy_clipboard.py <source_image_path>
"""
import sys
import os
import subprocess


def notify(title, msg, urgency=None):
    cmd = ["notify-send"]
    if urgency:
        cmd += ["-u", urgency]
    cmd += [title, msg]
    subprocess.run(cmd)


def main():
    if len(sys.argv) < 2:
        print("usage: copy_clipboard.py <source_image>", file=sys.stderr)
        sys.exit(1)

    source = sys.argv[1]

    if not os.path.isfile(source):
        notify("Screenshot", f"Copy failed: source missing ({source})", urgency="critical")
        sys.exit(1)

    try:
        with open(source, 'rb') as f:
            data = f.read()
    except OSError as e:
        notify("Screenshot", f"Copy failed: {e}", urgency="critical")
        sys.exit(1)

    proc = subprocess.run(['wl-copy', '--type', 'image/png'], input=data)
    if proc.returncode == 0:
        notify("Screenshot", "Copied to clipboard")
    else:
        notify("Screenshot", "Copy failed", urgency="critical")
        sys.exit(1)


if __name__ == '__main__':
    main()
