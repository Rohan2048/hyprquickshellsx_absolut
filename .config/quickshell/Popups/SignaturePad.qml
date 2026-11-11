import QtQuick
import "../Services"
import "../Theme"
import "../Lock"

// A pad to write on with the mouse, a touchpad, a touch screen or a digital pen (anything that moves a pointer
// while a button / the tip is down). The strokes are kept as lists of x, y pairs, 0..1 of the pad (the same
// 300 x 120 shape as the lock screen's signature), so they scale cleanly.
//   strokes    the finished strokes
//   spec       the note being edited (its colour and pen are used for the preview)
// Signal: committed(strokes) when a stroke is finished.
Rectangle {
    id: pad

    property var strokes: []
    property var spec: ({})
    signal committed(var strokes)

    implicitHeight: width * 0.4
    radius: Theme.radiusSm
    color: Qt.rgba(0, 0, 0, 0.35)
    border.width: 1
    border.color: Theme.borderMuted
    clip: true

    property var current: []

    // the finished strokes + the one being drawn, drawn by the lock screen's own note painter
    LockNote {
        spec: ({
            kind: "signature",
            sx: pad.width / 300, sy: pad.height / 120,
            pen: pad.spec.pen || 3,
            color: pad.spec.color,
            strokes: pad.strokes.concat(pad.current.length > 0 ? [pad.current] : [])
        })
    }

    Text {
        anchors.centerIn: parent
        visible: pad.strokes.length === 0 && pad.current.length === 0
        text: "Sign here"
        color: Theme.foreground
        opacity: 0.45
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.CrossCursor
        preventStealing: true
        function norm(e) { return [Math.max(0, Math.min(1, e.x / width)), Math.max(0, Math.min(1, e.y / height))] }
        onPressed: (e) => { const p = norm(e); pad.current = [p[0], p[1]] }
        onPositionChanged: (e) => {
            if (!pressed) return
                const p = norm(e)
                const c = pad.current
                const lx = c[c.length - 2], ly = c[c.length - 1]
                if (Math.abs(p[0] - lx) * width < 1.5 && Math.abs(p[1] - ly) * height < 1.5) return
                    pad.current = c.concat([p[0], p[1]])
        }
        onReleased: {
            if (pad.current.length >= 2) pad.committed(pad.strokes.concat([pad.current]))
                pad.current = []
        }
    }
}
