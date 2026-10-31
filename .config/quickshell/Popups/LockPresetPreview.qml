import QtQuick
import Quickshell
import "../Theme"
import "../Services"
import "../Widgets"
import "../Lock"

// Big live preview of a lock screen layout (Settings > Lock screen). It is the real lock screen's
// own pieces (clock, shapes, battery, icons) laid out with the same maths (LockPresets.place) in a
// world of your real screen size, scaled to fit, so what you see is where things land.
// Nothing real is created: the password, the power buttons and unlocking are never touched.
//
//   layout     a layout object (see Services/LockPresets.qml)
//   sel        highlighted element: "clock" "password" "power" "settings" "battery" "shape:<index>" "note:<index>" or ""
//   editable   drag elements, drag / resize shapes, stretch the clock, buttons and notes by their edge handles
//   showPush   show the clock where it sits while the settings panel is open
// Signals: picked(key); moved(key, fx, fy); scaled(key, sx, sy, fx, fy); shapeRect(index, fx, fy, fw, fh)
Item {
    id: pv

    property var layout: LockPresets.classic()
    property string sel: ""
    property bool editable: true
    property bool showPush: false
    signal picked(string key)
    signal moved(string key, real fx, real fy)
    signal scaled(string key, real sx, real sy, real fx, real fy)
    signal shapeRect(int index, real fx, real fy, real fw, real fh)

    readonly property real vw: Quickshell.screens.length > 0 ? Quickshell.screens[0].width : 1920
    readonly property real vh: Quickshell.screens.length > 0 ? Quickshell.screens[0].height : 1080
    readonly property real f: mock.width / pv.vw
    readonly property real m: LockPresets.margin
    readonly property int shapeIndex: pv.sel.indexOf("shape:") === 0 ? parseInt(pv.sel.slice(6)) : -1
    readonly property var pushVec: LockPresets.pushVector(pv.layout.settings.fx, pv.layout.settings.fy,
                                                          pv.layout.settings.push, 140)

    implicitHeight: mock.height + 6

    Rectangle {
        id: mock
        width: pv.width
        height: width * pv.vh / pv.vw
        radius: 8
        color: "black"
        border.width: 1
        border.color: Theme.borderMuted
        clip: true

        Item {
            id: world
            enabled: pv.editable
            width: pv.vw
            height: pv.vh
            scale: pv.f
            transformOrigin: Item.TopLeft

            // ---- background: your wallpaper, or a stand-in for the blurred screen ----
            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop { position: 0; color: Qt.rgba(Theme.color1.r, Theme.color1.g, Theme.color1.b, 0.55) }
                    GradientStop { position: 0.55; color: Qt.rgba(Theme.color3.r, Theme.color3.g, Theme.color3.b, 0.45) }
                    GradientStop { position: 1; color: Qt.rgba(Theme.color5.r, Theme.color5.g, Theme.color5.b, 0.5) }
                }
            }
            Image {
                anchors.fill: parent
                visible: pv.layout.bg.mode === "wallpaper" && pv.layout.bg.path !== "" && status === Image.Ready
                source: (pv.layout.bg.mode === "wallpaper" && pv.layout.bg.path !== "") ? "file://" + pv.layout.bg.path : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                sourceSize.width: 1280
            }
            Rectangle {
                anchors.fill: parent
                color: Theme.background.hslLightness < 0.5 ? "black" : "white"
                opacity: pv.layout.bg.dim / 100
            }

            LockShapes { anchors.fill: parent; shapes: pv.layout.shapes }

            // ---- notes: your text / signature; each has a frame with stretch handles ----
            // The model is the COUNT, not the array: every drag step edits the layout, which gives
            // pv.layout.notes a new array. An array model would rebuild every note (including the one
            // under the mouse) on each step and cut the drag off. With a count the items live on
            // and just re-read their note by index, like the shapes do.
            Repeater {
                model: pv.layout.notes.length
                delegate: Item {
                    id: nd
                    required property int index
                    readonly property var note: pv.layout.notes[nd.index] || ({})
                    z: 2
                    LockNote {
                        id: noteView
                        spec: nd.note
                        x: LockPresets.place(nd.note.fx, world.width, width, pv.m)
                        y: LockPresets.place(nd.note.fy, world.height, height, pv.m)
                    }
                    Frame {
                        host: pv; stage: world; key: "note:" + nd.index; target: noteView; margin: pv.m
                        scalable: true
                    }
                }
            }

            // ---- power buttons ----
            LockScaled {
                id: powerBox
                child: powerRow
                sx: pv.layout.power.sx
                sy: pv.layout.power.sy
                x: LockPresets.place(pv.layout.power.fx, world.width, width, pv.m)
                y: LockPresets.place(pv.layout.power.fy, world.height, height, pv.m)
                Row {
                    id: powerRow
                    spacing: 10
                    Repeater {
                        model: [{ id: "lock-suspend", f: "suspend.svg" }, { id: "lock-restart", f: "restart.svg" }, { id: "lock-poweroff", f: "power-off.svg" }]
                        delegate: GlassButton {
                            required property var modelData
                            icon: ""; elevated: true; implicitWidth: 48; implicitHeight: 48
                            radiusOverride: pv.layout.power.radius
                            hoverEnabled: false
                            ThemedIcon {
                                anchors.centerIn: parent
                                iconId: modelData.id
                                fallback: pv.dir + modelData.f
                                size: 20
                            }
                        }
                    }
                }
            }

            // ---- settings button ----
            LockScaled {
                id: settingsBox
                child: settingsBtn
                sx: pv.layout.settings.sx
                sy: pv.layout.settings.sy
                x: LockPresets.place(pv.layout.settings.fx, world.width, width, pv.m)
                y: LockPresets.place(pv.layout.settings.fy, world.height, height, pv.m)
                LockSettingsButton {
                    id: settingsBtn
                    cornerRadius: pv.layout.settings.radius
                }
            }

            // ---- battery ----
            LockScaled {
                id: battBox
                child: batt
                sx: pv.layout.battery.sx
                sy: pv.layout.battery.sy
                x: LockPresets.place(pv.layout.battery.fx, world.width, width, pv.m)
                y: LockPresets.place(pv.layout.battery.fy, world.height, height, pv.m)
                BatteryStatus { id: batt }
            }

            // ---- clock + password (pushed while the settings panel is open) ----
            Item {
                id: clockGroup
                anchors.fill: parent
                transform: Translate { x: pv.showPush ? pv.pushVec.dx : 0; y: pv.showPush ? pv.pushVec.dy : 0 }

                LockUser {
                    id: userBox
                    visible: pv.layout.user.show
                    showPfp: pv.layout.user.showPfp
                    showName: pv.layout.user.showName
                    pfp: pv.layout.user.pfp
                    size: pv.layout.user.size
                    textGrad: LockPresets.textGrad(pv.layout)
                    textColor: LockPresets.textColor(pv.layout)
                    x: LockPresets.place(pv.layout.user.fx, clockGroup.width, width, pv.m)
                    y: LockPresets.place(pv.layout.user.fy, clockGroup.height, height, pv.m)
                }

                LockScaled {
                    id: clockBox
                    child: clock
                    sx: pv.layout.clock.sx
                    sy: pv.layout.clock.sy
                    x: LockPresets.place(pv.layout.clock.fx, clockGroup.width, width, 0)
                    y: LockPresets.place(pv.layout.clock.fy, clockGroup.height, height, 0)
                    LockClock {
                        id: clock
                        textGrad: LockPresets.textGrad(pv.layout)
                        textColor: LockPresets.textColor(pv.layout)
                        showDate: pv.layout.clock.showDate
                    }
                }

                // the password field, drawn like the real one (dots, no box)
                Row {
                    id: pwRow
                    spacing: 6
                    readonly property bool follow: pv.layout.password.follow
                    x: follow ? clockBox.x + (clockBox.width - width) / 2
                    : LockPresets.place(pv.layout.password.fx, clockGroup.width, width, 0)
                    y: follow ? clockBox.y + clockBox.height + 24
                    : LockPresets.place(pv.layout.password.fy, clockGroup.height, height, 0)
                    Item {
                        width: 180; height: 28
                        Row {
                            anchors.centerIn: parent
                            spacing: 6
                            Repeater {
                                model: 6
                                delegate: Rectangle { width: 7; height: 7; radius: 3.5; color: Theme.foreground }
                            }
                        }
                    }
                    Rectangle {
                        width: 28; height: 28; radius: 14
                        color: "transparent"
                        border.width: 1
                        border.color: Theme.foreground
                        Text { anchors.centerIn: parent; text: "→"; color: Theme.foreground; font.pixelSize: 14 }
                    }
                }
            }

            // ---- selection frames + dragging (only when editable) ----
            component Frame: Item {
                id: fr
                property var host: null
                property Item stage: null
                property string key: ""
                property Item target: null
                property real offX: 0
                property real offY: 0
                property real margin: 0
                property real room: fr.stage.width
                property real roomH: fr.stage.height
                // clock, buttons, battery and notes can be stretched by their edge handles
                property bool scalable: false
                readonly property real baseW: fr.target && fr.target.baseWidth !== undefined ? fr.target.baseWidth : 0
                readonly property real baseH: fr.target && fr.target.baseHeight !== undefined ? fr.target.baseHeight : 0
                readonly property var spec: fr.key.indexOf("note:") === 0 ? fr.host.layout.notes[parseInt(fr.key.slice(5))]
                : fr.host.layout[fr.key]
                readonly property bool on: fr.host.sel === fr.key
                // drag a handle: the picture stretches, the top-left corner stays where it is
                function stretch(px, py, moveX, moveY) {
                    if (fr.baseW <= 0 || fr.baseH <= 0 || !fr.spec) return
                        const clampS = function (v) { return Math.max(0.3, Math.min(4, v)) }
                        const sx = moveX ? clampS((px - fr.x) / fr.baseW) : (fr.spec.sx || 1)
                        const sy = moveY ? clampS((py - fr.y) / fr.baseH) : (fr.spec.sy || 1)
                        fr.host.scaled(fr.key, sx, sy,
                                       LockPresets.fraction(fr.target.x, fr.room, fr.baseW * sx, fr.margin),
                                       LockPresets.fraction(fr.target.y, fr.roomH, fr.baseH * sy, fr.margin))
                }
                x: target ? target.x + offX : 0
                y: target ? target.y + offY : 0
                width: target ? target.width : 0
                height: target ? target.height : 0
                z: 5
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: -4 / fr.host.f
                    color: "transparent"
                    radius: 6 / fr.host.f
                    border.width: (fr.on ? 2 : 1) / fr.host.f
                    border.color: fr.on ? Theme.accentActive : Qt.rgba(1, 1, 1, 0.25)
                    visible: fr.host.editable
                }
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -4 / fr.host.f
                    enabled: fr.host.editable
                    cursorShape: Qt.SizeAllCursor
                    property real gx: 0
                    property real gy: 0
                    onPressed: (e) => {
                        fr.host.picked(fr.key)
                        const p = mapToItem(fr.stage, e.x, e.y)
                        gx = p.x - fr.x; gy = p.y - fr.y
                    }
                    onPositionChanged: (e) => {
                        if (!pressed) return
                            const p = mapToItem(fr.stage, e.x, e.y)
                            fr.host.moved(fr.key,
                                          LockPresets.fraction(p.x - gx - fr.offX, fr.room, fr.width, fr.margin),
                                          LockPresets.fraction(p.y - gy - fr.offY, fr.roomH, fr.height, fr.margin))
                    }
                }
                // stretch handles: right edge (width), bottom edge (height), corner (both)
                Repeater {
                    model: (fr.host.editable && fr.on && fr.scalable) ? [{ ax: 1, ay: 0.5, mx: true, my: false }, { ax: 0.5, ay: 1, mx: false, my: true }, { ax: 1, ay: 1, mx: true, my: true }] : []
                    delegate: Rectangle {
                        id: sh
                        required property var modelData
                        width: 12 / fr.host.f; height: width
                        radius: 2 / fr.host.f
                        color: Theme.accentActive
                        border.width: 1 / fr.host.f
                        border.color: "white"
                        x: fr.width * modelData.ax - width / 2 + (modelData.ax === 1 ? 4 / fr.host.f : 0)
                        y: fr.height * modelData.ay - height / 2 + (modelData.ay === 1 ? 4 / fr.host.f : 0)
                        z: 3
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -5 / fr.host.f
                            cursorShape: sh.modelData.mx && sh.modelData.my ? Qt.SizeFDiagCursor : (sh.modelData.mx ? Qt.SizeHorCursor : Qt.SizeVerCursor)
                            onPositionChanged: (e) => {
                                if (!pressed) return
                                    const p = mapToItem(fr.stage, e.x, e.y)
                                    fr.stretch(p.x, p.y, sh.modelData.mx, sh.modelData.my)
                            }
                        }
                    }
                }
            }
            Frame { host: pv; stage: world; key: "clock"; target: clockBox; scalable: true; offX: pv.showPush ? pv.pushVec.dx : 0; offY: pv.showPush ? pv.pushVec.dy : 0 }
            Frame { host: pv; stage: world; key: "password"; target: pwRow; offX: pv.showPush ? pv.pushVec.dx : 0; offY: pv.showPush ? pv.pushVec.dy : 0 }
            Frame {
                host: pv; stage: world; key: "user"; target: userBox; margin: pv.m
                visible: pv.layout.user.show
                offX: pv.showPush ? pv.pushVec.dx : 0; offY: pv.showPush ? pv.pushVec.dy : 0
            }
            Frame { host: pv; stage: world; key: "power"; target: powerBox; scalable: true; margin: pv.m }
            Frame { host: pv; stage: world; key: "settings"; target: settingsBox; scalable: true; margin: pv.m }
            Frame { host: pv; stage: world; key: "battery"; target: battBox; scalable: true; margin: pv.m }

            // shapes: click / drag the body to move; the selected one gets corner handles
            Repeater {
                model: pv.editable ? pv.layout.shapes.length : 0
                delegate: Item {
                    id: sh
                    required property int index
                    readonly property var s: pv.layout.shapes[sh.index] || ({})
                    x: (s.fx || 0) * world.width
                    y: (s.fy || 0) * world.height
                    width: (s.fw || 0.1) * world.width
                    height: (s.fh || 0.1) * world.height
                    z: 1
                    readonly property bool on: pv.sel === "shape:" + sh.index
                    Rectangle {
                        anchors.fill: parent
                        color: "transparent"
                        border.width: (sh.on ? 2 : 0) / pv.f
                        border.color: Theme.accentActive
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.SizeAllCursor
                        property real gx: 0
                        property real gy: 0
                        onPressed: (e) => {
                            pv.picked("shape:" + sh.index)
                            const p = mapToItem(world, e.x, e.y)
                            gx = p.x - sh.x; gy = p.y - sh.y
                        }
                        onPositionChanged: (e) => {
                            if (!pressed) return
                                const p = mapToItem(world, e.x, e.y)
                                pv.shapeRect(sh.index, (p.x - gx) / world.width, (p.y - gy) / world.height, sh.s.fw, sh.s.fh)
                        }
                    }
                }
            }

            // corner handles of the selected shape
            Item {
                id: handles
                visible: pv.editable && pv.shapeIndex >= 0 && pv.shapeIndex < pv.layout.shapes.length
                z: 8
                readonly property var s: visible ? pv.layout.shapes[pv.shapeIndex] : ({ fx: 0, fy: 0, fw: 0, fh: 0 })
                readonly property real hs: 14 / pv.f
                Repeater {
                    model: [{ cx: 0, cy: 0 }, { cx: 1, cy: 0 }, { cx: 0, cy: 1 }, { cx: 1, cy: 1 }]
                    delegate: Rectangle {
                        id: hd
                        required property var modelData
                        width: handles.hs; height: handles.hs
                        radius: width / 2
                        color: Theme.accentActive
                        border.width: 1 / pv.f
                        border.color: "white"
                        x: (handles.s.fx + hd.modelData.cx * handles.s.fw) * world.width - width / 2
                        y: (handles.s.fy + hd.modelData.cy * handles.s.fh) * world.height - height / 2
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -4 / pv.f
                            cursorShape: Qt.SizeFDiagCursor
                            onPositionChanged: (e) => {
                                if (!pressed) return
                                    const p = mapToItem(world, e.x, e.y)
                                    const px = Math.max(-0.5, Math.min(1.5, p.x / world.width))
                                    const py = Math.max(-0.5, Math.min(1.5, p.y / world.height))
                                    const s = handles.s
                                    const minS = 0.02
                                    let l = s.fx, t = s.fy, r = s.fx + s.fw, b = s.fy + s.fh
                                    if (hd.modelData.cx === 0) l = Math.min(px, r - minS); else r = Math.max(px, l + minS)
                                        if (hd.modelData.cy === 0) t = Math.min(py, b - minS); else b = Math.max(py, t + minS)
                                            pv.shapeRect(pv.shapeIndex, l, t, r - l, b - t)
                            }
                        }
                    }
                }
            }

            // where the settings panel opens from (shown with "Preview")
            Rectangle {
                id: ghost
                visible: pv.showPush
                z: 20
                readonly property var spot: LockPresets.panelRect(pv.layout.settings,
                                                                  settingsBox.x, settingsBox.y, settingsBox.width, settingsBox.height,
                                                                  width, height, world.width, world.height, pv.m)
                width: 350; height: 360
                x: spot.x; y: spot.y
                radius: Theme.radiusMd
                color: Qt.rgba(1, 1, 1, 0.12)
                border.width: 2 / pv.f
                border.color: Theme.accentActive
                Rectangle {
                    x: 14 + pv.layout.settings.contentX; y: 14 + pv.layout.settings.contentY
                    width: parent.width - 28; height: parent.height - 28
                    color: "transparent"
                    border.width: 1 / pv.f
                    border.color: Qt.rgba(1, 1, 1, 0.35)
                    radius: 8
                    Text { anchors.centerIn: parent; text: "settings panel"; color: Theme.foreground; font.pixelSize: 26 }
                }
            }

            // tap on empty space deselects
            MouseArea {
                anchors.fill: parent
                z: -1
                enabled: pv.editable
                onPressed: pv.picked("")
            }
        }
    }

    readonly property string dir: "file://" + Quickshell.env("HOME") + "/.config/icons/"
}
