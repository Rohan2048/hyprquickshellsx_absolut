pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Io
import Quickshell.Wayland
import "../../Services"
import "../../Theme"

Rectangle {
    id: root

    required property var screenshotWindow

    anchors {
        top: parent.top
        horizontalCenter: parent.horizontalCenter
        topMargin: 16
    }
    width: row.implicitWidth + 24
    height: 48
    radius: Theme.radiusMd
    color: Theme.popupBg

    // ---- config ----

    // Fill in your phone's device ID from `kdeconnect-cli -l`
    readonly property string kdeDeviceId: "59ef5ae2cbbc47739c19784bc975eec7" //unique to your device

    // ---- helpers ----

    function shellQuote(str) {
        return "'" + String(str).replace(/'/g, "'\\''") + "'";
    }

    function timestampName() {
        const d = new Date();
        const pad = n => String(n).padStart(2, "0");
        return "Screenshot_" + d.getFullYear() + pad(d.getMonth() + 1) + pad(d.getDate())
        + "_" + pad(d.getHours()) + pad(d.getMinutes()) + pad(d.getSeconds()) + ".png";
    }

    // ---- processes ----

    Process {
        id: saveProc
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim().length > 0)
                    console.warn("save() stderr:", text);
            }
        }
        onExited: (exitCode) => {
            if (exitCode !== 0)
                console.warn("Save failed, exit code", exitCode);
        }
    }

    Process {
        id: saveAsCopyProc
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim().length > 0)
                    console.warn("Save As stderr:", text);
            }
        }
        onExited: (exitCode) => {
            if (exitCode === 0)
                root.screenshotWindow.requestClose();
            else
                console.warn("Save As failed, exit code", exitCode);
        }
    }

    // Always saves to ~/Pictures/Screenshots first, then attempts to share
    // over KDE Connect. Never touches wl-copy / the system clipboard.
    Process {
        id: shareToPhoneProc
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim().length > 0)
                    console.warn("share() stderr:", text);
            }
        }
        onExited: (exitCode) => {
            if (exitCode !== 0)
                console.warn("Share to phone script failed, exit code", exitCode);
        }
    }

    // ---- actions ----

    function doSave() {
        root.screenshotWindow.captureComposite(function(path) {
            if (!path) { console.warn("Save failed: composite grab failed"); return; }
            const filename = timestampName();
            const script = "mkdir -p \"$HOME/Pictures/Screenshots\" && cp "
            + shellQuote(path)
            + " \"$HOME/Pictures/Screenshots/" + filename + "\""
            + " && rm -f " + shellQuote(path)
            + " && notify-send -t 3000 'Screenshot' 'Saved as " + filename + "'"
            + " || notify-send -u critical -t 3000 'Screenshot' 'Save failed'";
            saveProc.exec(["bash", "-c", script]);
            // Don't wait for the save subprocess to exit -- the script
            // reports its own success/failure via notify-send, so the
            // window can close the instant the capture+copy is kicked off
            // instead of blocking on process spawn + disk I/O + notify-send's
            // DBus round-trip.
            root.screenshotWindow.requestClose();
        });
    }

    function doSaveAs() {
        root.screenshotWindow.captureComposite(function(path) {
            if (!path) { console.warn("Save As failed: composite grab failed"); return; }
            saveAsWindow.open(path, root.timestampName());
        });
    }

    function doShareToPhone() {
        root.screenshotWindow.captureComposite(function(path) {
            if (!path) { console.warn("Share failed: composite grab failed"); return; }
            const filename = root.timestampName();
            const destPath = "\"$HOME/Pictures/Screenshots/" + filename + "\"";
            const script = "mkdir -p \"$HOME/Pictures/Screenshots\" && cp "
            + root.shellQuote(path) + " " + destPath
            + " && rm -f " + root.shellQuote(path)
            + " && { "
            + "if ! command -v kdeconnect-cli >/dev/null 2>&1; then "
            + "notify-send -u critical -t 3000 'Screenshot' 'You need KDE Connect to share image files'; "
            + "elif ! (ping -c1 -W2 8.8.8.8 >/dev/null 2>&1 || ping -c1 -W2 1.1.1.1 >/dev/null 2>&1); then "
            + "notify-send -u critical -t 3000 'Screenshot' 'Failed to share. Try later. Picture saved in ~/Pictures/Screenshots'; "
            + "else "
            + "kdeconnect-cli --share " + destPath + " -d " + root.kdeDeviceId + " "
            + "&& notify-send -t 3000 'Screenshot' 'Sent to phone' "
            + "|| notify-send -u critical -t 3000 'Screenshot' 'Share failed'; "
            + "fi; }"
            + " || notify-send -u critical -t 3000 'Screenshot' 'Save failed'";
            shareToPhoneProc.exec(["bash", "-c", script]);
        });
    }

    SaveAsWindow {
        id: saveAsWindow
        screenshotWindow: root.screenshotWindow
        onSaveRequested: (destDir, filename) => {
            const script = "cp " + root.shellQuote(saveAsWindow.sourcePath) + " " + root.shellQuote(destDir + "/" + filename)
            + " && rm -f " + root.shellQuote(saveAsWindow.sourcePath)
            + " && notify-send -t 3000 'Screenshot' 'Saved as " + filename + "'"
            + " || notify-send -u critical -t 3000 'Screenshot' 'Save failed'";
            saveAsCopyProc.exec(["bash", "-c", script]);
        }
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 8

        ToolButton { label: "Save"; onClicked: root.doSave() }
        ToolButton { label: "Save As"; onClicked: root.doSaveAs() }
        ToolButton { label: "Send to Phone"; onClicked: root.doShareToPhone() }
        ToolButton { label: "Cancel"; onClicked: root.screenshotWindow.requestClose() }
    }
}
