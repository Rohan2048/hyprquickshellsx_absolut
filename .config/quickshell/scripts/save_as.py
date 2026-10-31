#!/usr/bin/env python3
"""Save-As via the XDG desktop portal file picker.

Usage: save_as.py <source_image_path> <default_filename>
"""
import sys
import os
import subprocess
from urllib.parse import unquote, urlparse

import dbus
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib


def notify(title, msg, urgency=None):
    cmd = ["notify-send"]
    if urgency:
        cmd += ["-u", urgency]
    cmd += [title, msg]
    subprocess.run(cmd)


def main():
    if len(sys.argv) < 3:
        print("usage: save_as.py <source_image> <default_filename>", file=sys.stderr)
        sys.exit(1)

    source = sys.argv[1]
    default_name = sys.argv[2]

    if not os.path.isfile(source):
        notify("Screenshot", f"Save As failed: source missing ({source})", urgency="critical")
        sys.exit(1)

    DBusGMainLoop(set_as_default=True)
    bus = dbus.SessionBus()
    portal = bus.get_object('org.freedesktop.portal.Desktop', '/org/freedesktop/portal/desktop')
    iface = dbus.Interface(portal, 'org.freedesktop.portal.FileChooser')

    loop = GLib.MainLoop()
    result = {}

    def on_response(response, results):
        if response == 0 and 'uris' in results and len(results['uris']) > 0:
            uri = str(results['uris'][0])
            if uri.startswith('file://'):
                result['path'] = unquote(urlparse(uri).path)
        loop.quit()

    default_dir = os.path.expanduser('~/Pictures/Screenshots')
    os.makedirs(default_dir, exist_ok=True)

    options = {
        'current_name': default_name,
        'current_folder': dbus.ByteArray((default_dir + '\0').encode()),
    }

    handle = iface.SaveFile('', 'Save Screenshot', options)
    bus.add_signal_receiver(
        on_response,
        signal_name='Response',
        dbus_interface='org.freedesktop.portal.Request',
        path=handle,
    )
    loop.run()

    if 'path' not in result:
        # User cancelled the dialog.
        sys.exit(0)

    dest = result['path']
    try:
        with open(source, 'rb') as f_in, open(dest, 'wb') as f_out:
            f_out.write(f_in.read())
    except OSError as e:
        notify("Screenshot", f"Save As failed: {e}", urgency="critical")
        sys.exit(1)

    notify("Screenshot", f"Saved as {os.path.basename(dest)}")
    print(dest)


if __name__ == '__main__':
    main()
