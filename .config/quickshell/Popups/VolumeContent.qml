import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Qt5Compat.GraphicalEffects
import Quickshell
import "../Theme"
import "../Widgets"
import "../Services"

// Everything inside the Volume popup's panel, for one page (0 = devices, 1 = output ports).
// Used by VolumePopup.qml, which slides between the pages, and by the live preview in
// Settings > Popups > Popup styles, which shows both pages side by side.
//
// Movable pieces (Widgets/PopupElement, ids): title, default, settings (header, both pages), mute, slider,
// devices, outputLabel (page 0), ports (page 1).
Item {
    id: root

    readonly property real baseWidth: 260
    // 0 = devices page, 1 = raw-ports page
    property int page: 0
    // false in the Settings preview: nothing there should switch devices or move the volume
    property bool interactive: true
    signal pageRequested(int page)

    // Guards the sink Repeater's model so it never populates on the same frame the popup (and, after an
    // SBS exit, the whole Bar tree) is freshly constructed -- VolBtn's layer/effect setup needs a real
    // attached window before it styles correctly.
    property bool listReady: false
    function rearm() {
        root.listReady = false
        Qt.callLater(() => root.listReady = true)
    }
    Component.onCompleted: root.rearm()

    implicitWidth: baseWidth
    implicitHeight: 220

    ColumnLayout {
        id: contentCol
        anchors.fill: parent
        anchors.margins: 14
        spacing: Theme.gapMd

        // ── Header: title + settings toggle ──────────────────────────
        Item {
            Layout.fillWidth: true
            implicitHeight: headerTitle.implicitHeight

            PopupElement { elementId: "title"; anchors.centerIn: parent
                Text {
                    id: headerTitle
                    text: root.page === 0 ? "Volume" : "Output Ports"
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize + 1
                    font.bold: true
                }
            }

            PopupElement { elementId: "default"; anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                Item {
                    id: defaultButton
                    implicitWidth: defaultLabel.implicitWidth + 12
                    implicitHeight: 24

                    Rectangle {
                        anchors.fill: parent
                        radius: height / 2
                        color: defaultArea.containsMouse ? Theme.hoverBg : "transparent"
                        Behavior on color { ColorAnimation { duration: Animations.durationBase } }
                    }

                    Text {
                        id: defaultLabel
                        anchors.centerIn: parent
                        text: "Default"
                        color: Theme.foreground
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSm
                        font.bold: true
                    }

                    MouseArea {
                        id: defaultArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        // Unconditional: always reverts to the built-in laptop
                        // speakers, regardless of what's currently active.
                        onClicked: Volume.resetToDefault()
                    }
                }
            }

            PopupElement { elementId: "settings"; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                Item {
                    id: settingsButton
                    implicitWidth: 24
                    implicitHeight: 24

                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: settingsArea.containsMouse || root.page === 1 ? Theme.hoverBg : "transparent"
                        Behavior on color { ColorAnimation { duration: Animations.durationBase } }
                    }

                    Image {
                        id: settingsIcon
                        anchors.centerIn: parent
                        width: 15
                        height: 15
                        sourceSize: Qt.size(15, 15)
                        smooth: true
                        source: "file://" + Quickshell.env("HOME") + "/.config/icons/settings.svg"
                        rotation: root.page === 1 ? 90 : 0
                        Behavior on rotation {
                            NumberAnimation { duration: Animations.durationBase; easing.type: Animations.easingStandard }
                        }
                        visible: false
                    }
                    ColorOverlay {
                        anchors.fill: settingsIcon
                        source: settingsIcon
                        color: Theme.foreground
                        rotation: settingsIcon.rotation
                    }

                    MouseArea {
                        id: settingsArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.pageRequested(root.page === 0 ? 1 : 0)
                    }
                }
            }

        }

        // ── Pager: slides between the devices page and the ports page ─
        Item {
            id: pager
            Layout.fillWidth: true
            clip: true
            implicitHeight: root.page === 0 ? page0Col.implicitHeight : page1Col.implicitHeight
            Behavior on implicitHeight {
                NumberAnimation { duration: Animations.durationBase; easing.type: Animations.easingStandard }
            }

            // ── Page 0: devices ────────────────────────────────────
            Item {
                id: page0Wrap
                width: pager.width
                height: page0Col.implicitHeight
                x: root.page === 0 ? 0 : -pager.width
                opacity: root.page === 0 ? 1 : 0
                Behavior on x { NumberAnimation { duration: Animations.durationBase; easing.type: Animations.easingStandard } }
                Behavior on opacity { NumberAnimation { duration: Animations.durationBase } }

                ColumnLayout {
                    id: page0Col
                    width: parent.width
                    spacing: Theme.gapMd

                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: Theme.gapSm

                        PopupElement {
                            elementId: "mute"
                            VolBtn {
                                text: Volume.muted ? "🔇" : "🔊"
                                onClicked: Volume.toggleMute()
                                implicitWidth: 34
                                implicitHeight: 34
                                borderWidth: 0
                            }
                        }

                        PopupElement {
                            elementId: "slider"; Layout.alignment: Qt.AlignVCenter
                            Item {
                                id: volTrack

                                implicitWidth: 150


                                implicitHeight: dragArea.pressed ? 34 : 22
                                Behavior on implicitHeight {
                                    SpringAnimation {
                                        spring: Animations.trackSpring
                                        damping: Animations.trackDamping
                                        mass: Animations.trackMass
                                    }
                                }

                                property real dragValue: Volume.volume
                                readonly property real ratio: Math.max(0, Math.min(1, dragValue / 100))
                                property bool settling: false

                                Binding {
                                    target: volTrack
                                    property: "dragValue"
                                    value: Volume.volume
                                    when: !dragArea.pressed && !volTrack.settling
                                }

                                Timer {
                                    id: settleTimer
                                    interval: 250
                                    onTriggered: volTrack.settling = false
                                }

                                readonly property real maxStretch: 10
                                readonly property real stretchConstant: 0.60
                                function rubberBand(distance) {
                                    return Animations.rubberBand(distance, maxStretch, stretchConstant)
                                }

                                property real overshoot: 0
                                Behavior on overshoot {
                                    SpringAnimation {
                                        spring: dragArea.pressed && dragArea.pinnedSide !== 0 ? Animations.pinnedStretchSpring : Animations.overshootSpring
                                        damping: dragArea.pressed && dragArea.pinnedSide !== 0 ? Animations.pinnedStretchDamping : Animations.overshootDamping
                                        mass: dragArea.pressed && dragArea.pinnedSide !== 0 ? Animations.pinnedStretchMass : Animations.overshootMass
                                    }
                                }

                                Rectangle {
                                    id: track
                                    anchors.fill: parent
                                    transform: Translate { x: volTrack.overshoot }
                                    radius: height / 2
                                    color: Theme.hoverBg
                                    clip: true

                                    Item {
                                        id: fill
                                        anchors.left: parent.left
                                        anchors.top: parent.top
                                        anchors.bottom: parent.bottom

                                        width: Math.round(volTrack.ratio * parent.width)
                                        clip: true

                                        Rectangle {
                                            anchors.left: parent.left
                                            anchors.top: parent.top
                                            width: track.width
                                            height: track.height
                                            radius: track.radius
                                            color: Theme.accentActive
                                        }

                                        Behavior on width {
                                            enabled: !dragArea.pressed && !volTrack.settling
                                            NumberAnimation {
                                                duration: Animations.durationBase
                                                easing.type: Animations.easingStandard
                                            }
                                        }
                                    }
                                }

                                MouseArea {
                                    id: dragArea
                                    anchors.fill: parent
                                    preventStealing: true
                                    cursorShape: Qt.PointingHandCursor

                                    property int pinnedSide: 0
                                    property int lastSentValue: -1

                                    function updateFromX(x) {
                                        const clampedX = Math.max(0, Math.min(width, x))
                                        const r = width > 0 ? clampedX / width : 0
                                        volTrack.dragValue = Math.round(r * 100)
                                        pinnedSide = x <= 0 ? -1 : (x >= width ? 1 : 0)
                                        volTrack.overshoot = pinnedSide * volTrack.maxStretch
                                    }

                                    onPressed: (mouse) => {
                                        updateFromX(mouse.x)
                                        Volume.setVolume(volTrack.dragValue)
                                        lastSentValue = volTrack.dragValue
                                        volumeThrottle.start()
                                    }
                                    onPositionChanged: (mouse) => { if (pressed) updateFromX(mouse.x) }
                                    onReleased: {
                                        volumeThrottle.stop()
                                        Volume.setVolume(volTrack.dragValue)
                                        lastSentValue = volTrack.dragValue
                                        pinnedSide = 0
                                        volTrack.overshoot = 0
                                        volTrack.settling = true
                                        settleTimer.restart()
                                    }
                                }

                                Timer {
                                    id: volumeThrottle
                                    interval: 40
                                    repeat: true
                                    onTriggered: {
                                        if (dragArea.lastSentValue !== volTrack.dragValue) {
                                            Volume.setVolume(volTrack.dragValue)
                                            dragArea.lastSentValue = volTrack.dragValue
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Scrollable device list: live sinks + pinned (always-on) ports
                    PopupElement {
                        elementId: "devices"; Layout.fillWidth: true; implicitWidth: 232
                        ScrollView {
                            id: devScroll
                            width: parent.width
                            height: 70
                            clip: false
                            // the list is exactly as wide as the view. Left to itself the ScrollView sizes its content from the
                            // content's own width, which itself follows the view: on a slow start that loop could settle on
                            // 0 and every row sat on the left.
                            contentWidth: devScroll.width

                            ColumnLayout {
                                width: devScroll.width
                                spacing: 2

                                Repeater {
                                    model: root.listReady ? Volume.sinks.filter((s) => s !== "Speakers") : []
                                    delegate: Item {
                                        required property string modelData

                                        Layout.fillWidth: true
                                        implicitHeight: 34

                                        VolBtn {
                                            anchors.horizontalCenter: parent.horizontalCenter

                                            implicitWidth: 180
                                            implicitHeight: 30

                                            text: modelData
                                            active: Volume.sink === modelData
                                            onClicked: Volume.setSink(modelData)
                                        }
                                    }
                                }

                                // Always-present entries (e.g. built-in speakers) that
                                // don't survive a profile switch away from analog-stereo,
                                // so they can't come from the sinks list above.
                                Repeater {
                                    model: root.listReady ? Volume.pinned.filter((p) => p.label !== "Speakers") : []
                                    delegate: Item {
                                        required property var modelData

                                        Layout.fillWidth: true
                                        implicitHeight: 34

                                        VolBtn {
                                            anchors.horizontalCenter: parent.horizontalCenter

                                            implicitWidth: 180
                                            implicitHeight: 30

                                            text: modelData.label
                                            active: modelData.active
                                            onClicked: Volume.setPort(modelData.card, modelData.port)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    PopupElement {
                        elementId: "outputLabel"; Layout.fillWidth: true; implicitWidth: 232
                        ColumnLayout {
                            width: parent.width
                            spacing: 2

                            Text {
                                text: "OUTPUT DEVICE"
                                color: Theme.textDim
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSm
                                font.bold: true
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                            }

                            Text {
                                text: Volume.sink
                                color: Theme.textMuted
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize - 1
                                font.bold: true
                                wrapMode: Text.Wrap
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                            }
                        }
                    }
                }
            }

            // ── Page 1: raw ports (HDMI / aux / etc) ───────────────
            Item {
                id: page1Wrap
                width: pager.width
                height: page1Col.implicitHeight
                x: root.page === 1 ? 0 : pager.width
                opacity: root.page === 1 ? 1 : 0
                Behavior on x { NumberAnimation { duration: Animations.durationBase; easing.type: Animations.easingStandard } }
                Behavior on opacity { NumberAnimation { duration: Animations.durationBase } }

                ColumnLayout {
                    id: page1Col
                    width: parent.width
                    spacing: Theme.gapSm

                    PopupElement {
                        elementId: "ports"; Layout.fillWidth: true; implicitWidth: 232
                        ScrollView {
                            id: portScroll
                            width: parent.width
                            height: 150
                            clip: false
                            contentWidth: portScroll.width

                            ColumnLayout {
                                width: portScroll.width
                                spacing: 4

                                Repeater {
                                    model: root.page === 1 ? Volume.ports : []
                                    delegate: Item {
                                        required property var modelData

                                        Layout.fillWidth: true
                                        implicitHeight: 34

                                        VolBtn {
                                            anchors.centerIn: parent

                                            implicitWidth: 220
                                            implicitHeight: 30

                                            text: modelData.cardLabel
                                            ? modelData.label + "  ·  " + modelData.cardLabel
                                            : modelData.label
                                            active: modelData.active
                                            onClicked: Volume.setPort(modelData.card, modelData.port)
                                        }
                                    }
                                }

                                Text {
                                    visible: root.page === 1 && Volume.ports.length === 0
                                    text: "No other output ports detected"
                                    color: Theme.textDim
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize - 1
                                    Layout.fillWidth: true
                                    horizontalAlignment: Text.AlignHCenter
                                }
                            }
                        }
                    }
                }
            }
        }
    }

}
