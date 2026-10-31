import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import "../Services"
import "../Theme"
import "../Widgets"

// Settings > Sounds: every output (speakers, headphones, HDMI, Bluetooth, aux ...) and every microphone
// as its own card. Each card has its profile, port, volume with separate Left / Right, mute and
// "Use this one" to make it the default. Values follow the system live.
// "Combine sound outputs" plays on several outputs at once: the wired ones share one delay slider, the
// Bluetooth ones are kept in step with the slowest Bluetooth output automatically.
Item {
    id: page

    property string tab: "out"      // "out" | "in"

    Component.onCompleted: SoundDevices.watching = true
    Component.onDestruction: SoundDevices.watching = false

    component Hint: Text {
        color: Theme.foreground
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSm
        opacity: 0.8
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
    }

    component Label2: Text {
        color: Theme.foreground
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
    }

    // label + slider + percent
    component VolRow: RowLayout {
        id: vr
        property string title: ""
        property real val: 0
        property bool dim: false
        signal moved(real v)
        spacing: 10
        Label2 { text: vr.title; Layout.preferredWidth: 56; opacity: vr.dim ? 0.6 : 1 }
        GlassSlider {
            Layout.fillWidth: true; Layout.preferredHeight: 26
            min: 0; max: 100
            value: Math.min(100, vr.val)
            onValueCommitted: (v) => vr.moved(v)
        }
        Label2 { text: Math.round(vr.val) + "%"; Layout.preferredWidth: 44; horizontalAlignment: Text.AlignRight }
    }

    // label + slider + milliseconds (-10 .. +500 ms)
    component DelayRow: RowLayout {
        id: dr
        property real val: 0
        signal moved(real v)
        spacing: 10
        Label2 { text: "Wired"; Layout.preferredWidth: 56 }
        GlassSlider {
            Layout.fillWidth: true; Layout.preferredHeight: 26
            min: -10; max: 500
            value: dr.val
            onValueCommitted: (v) => dr.moved(v)
        }
        Label2 {
            text: (Math.round(dr.val) > 0 ? "+" : "") + Math.round(dr.val) + " ms"
            Layout.preferredWidth: 64
            horizontalAlignment: Text.AlignRight
        }
    }

    component DeviceCard: Rectangle {
        id: card
        property string devName: ""
        property string kind: "sink"        // "sink" | "source"
        property bool open: false           // the three-dot menu: profile and port
        readonly property var dev: SoundDevices.byName(card.kind, card.devName)
        readonly property bool out: card.kind === "sink"
        readonly property int nch: card.dev.channels ? card.dev.channels.length : 0
        property real lvl: 0                // microphone loudness, 0-100
        property real peak: 0
        readonly property string glyph: ({ bluetooth: "\u2689", hdmi: "\u25AD", usb: "\u2B21", headphones: "\u266B",
            speaker: "\u25B6", line: "\u2501", mic: "\u25CF" })[card.dev.kind] || "\u266A"
            radius: Theme.radiusMd
            color: card.dev.isDefault ? Qt.rgba(Theme.accentActive.r, Theme.accentActive.g, Theme.accentActive.b, 0.12) : "transparent"
            border.width: 1
            border.color: card.dev.isDefault ? Theme.accentActive : Theme.borderMuted
            implicitHeight: inner.implicitHeight + 24

            // microphone level: only while this card is on screen
            Process {
                running: !card.out && card.card_visible
                command: ["python3", SoundDevices.micScript, card.devName]
                stdout: SplitParser {
                    splitMarker: "\n"
                    onRead: (line) => { const v = parseInt(line); if (!isNaN(v)) { card.lvl = v; if (v > card.peak) card.peak = v } }
                }
            }
            readonly property bool card_visible: card.visible
            Timer { running: !card.out; interval: 90; repeat: true; onTriggered: card.peak = Math.max(card.lvl, card.peak - 5) }

            ColumnLayout {
                id: inner
                x: 12; y: 12
                width: card.width - 24
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    Text {
                        text: card.glyph
                        color: card.dev.isDefault ? Theme.accentActive : Theme.foreground
                        font.pixelSize: 20
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        Label2 { text: card.dev.desc; font.bold: true; elide: Text.ElideRight; Layout.fillWidth: true }
                        Text {
                            text: SoundDevices.kindLabel(card.dev.kind) + (card.dev.cardDesc && card.dev.cardDesc !== card.dev.desc ? "  \u00B7  " + card.dev.cardDesc : "")
                            color: Theme.foreground
                            opacity: 0.65
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }
                    GlassButton {
                        text: card.dev.muted ? "Unmute" : "Mute"
                        active: card.dev.muted
                        onClicked: SoundDevices.toggleMute(card.kind, card.devName)
                    }
                    GlassButton {
                        text: card.dev.isDefault ? "In use" : (card.out ? "Use this output" : "Use this microphone")
                        active: card.dev.isDefault
                        disabled: card.dev.isDefault
                        onClicked: SoundDevices.setDefault(card.kind, card.devName)
                    }
                    GlassButton {
                        visible: (card.dev.profiles && card.dev.profiles.length > 1) || (card.dev.ports && card.dev.ports.length > 1)
                        text: "\u22EE"
                        active: card.open
                        onClicked: card.open = !card.open
                    }
                }

                VolRow {
                    Layout.fillWidth: true
                    title: card.out ? "Volume" : "Level"
                    val: SoundDevices.level(card.dev)
                    dim: card.dev.muted
                    onMoved: (v) => SoundDevices.setVolume(card.kind, card.devName, -1, v)
                }
                // left / right, only where the device has more than one channel
                Repeater {
                    model: card.nch > 1 ? card.nch : 0
                    delegate: VolRow {
                        required property int index
                        Layout.fillWidth: true
                        Layout.leftMargin: 14
                        title: SoundDevices.chLabel(card.dev.channels[index].ch)
                        val: card.dev.channels[index].pct
                        dim: card.dev.muted
                        onMoved: (v) => SoundDevices.setVolume(card.kind, card.devName, index, v)
                    }
                }

                // microphone test bar
                RowLayout {
                    visible: !card.out
                    Layout.fillWidth: true
                    spacing: 10
                    Label2 { text: "Hearing"; Layout.preferredWidth: 56 }
                    Rectangle {
                        Layout.fillWidth: true; Layout.preferredHeight: 12
                        radius: 6
                        color: Theme.pillOffBg
                        border.width: 1; border.color: Theme.borderMuted
                        Rectangle {
                            height: parent.height; radius: 6
                            width: parent.width * card.lvl / 100
                            color: card.lvl > 90 ? "#e5534b" : Theme.accentActive
                            Behavior on width { NumberAnimation { duration: 70 } }
                        }
                        Rectangle {      // peak mark
                            visible: card.peak > 2
                            x: Math.min(parent.width - width, parent.width * card.peak / 100)
                            width: 3; height: parent.height
                            color: Theme.foreground
                            opacity: 0.8
                        }
                    }
                    Label2 { text: card.dev.muted ? "muted" : (card.lvl > 3 ? "heard" : "quiet"); Layout.preferredWidth: 44; horizontalAlignment: Text.AlignRight; opacity: 0.7 }
                }

                // three-dot menu
                ColumnLayout {
                    visible: card.open
                    Layout.fillWidth: true
                    spacing: 8
                    RowLayout {
                        visible: card.dev.profiles && card.dev.profiles.length > 1
                        Layout.fillWidth: true
                        spacing: 8
                        Label2 { text: "Profile"; Layout.preferredWidth: 56; Layout.alignment: Qt.AlignTop }
                        Flow {
                            Layout.fillWidth: true
                            spacing: 6
                            Repeater {
                                model: card.dev.profiles ?? []
                                delegate: GlassButton {
                                    required property var modelData
                                    text: modelData.desc
                                    active: modelData.name === card.dev.activeProfile
                                    disabled: !modelData.avail
                                    onClicked: SoundDevices.setProfile(card.dev.card, modelData.name)
                                }
                            }
                        }
                    }
                    RowLayout {
                        visible: card.dev.ports && card.dev.ports.length > 1
                        Layout.fillWidth: true
                        spacing: 8
                        Label2 { text: "Port"; Layout.preferredWidth: 56; Layout.alignment: Qt.AlignTop }
                        Flow {
                            Layout.fillWidth: true
                            spacing: 6
                            Repeater {
                                model: card.dev.ports ?? []
                                delegate: GlassButton {
                                    required property var modelData
                                    text: modelData.desc
                                    active: modelData.name === card.dev.activePort
                                    disabled: modelData.avail === "no"
                                    onClicked: SoundDevices.setPort(card.kind, card.devName, modelData.name)
                                }
                            }
                        }
                    }
                }
            }
    }

    // pick two or more outputs and play on all of them at once
    property var picked: ({})
    function togglePick(n) {
        const p = Object.assign({}, page.picked)
        if (p[n]) delete p[n]; else p[n] = true
            page.picked = p
    }
    function pickedList() { return Object.keys(page.picked) }
    Connections {
        target: SoundDevices
        function onCombinedChanged() {
            if (SoundDevices.combined.active) {
                const p = {}
                for (let i = 0; i < SoundDevices.combined.members.length; i++) p[SoundDevices.combined.members[i]] = true
                    page.picked = p
            }
        }
    }

    // "Speaker A +0 ms  \u00B7  Earbuds +60 ms": how far each Bluetooth output is held back to match the slowest
    function btSyncText() {
        const l = SoundDevices.delay.bt ?? []
        const out = []
        for (let i = 0; i < l.length; i++) {
            const d = SoundDevices.byName("sink", l[i].name)
            out.push(d.desc + " +" + l[i].delayMs + " ms")
        }
        return out.join("  \u00B7  ")
    }

    component CombineCard: Rectangle {
        id: cc
        readonly property var comb: SoundDevices.combined
        radius: Theme.radiusMd
        color: cc.comb.active ? Qt.rgba(Theme.accentActive.r, Theme.accentActive.g, Theme.accentActive.b, 0.12) : "transparent"
        border.width: 1
        border.color: cc.comb.active ? Theme.accentActive : Theme.borderMuted
        implicitHeight: ci.implicitHeight + 24
        ColumnLayout {
            id: ci
            x: 12; y: 12
            width: cc.width - 24
            spacing: 8
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Text { text: "\u29C9"; color: cc.comb.active ? Theme.accentActive : Theme.foreground; font.pixelSize: 20 }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Label2 { text: "Combine sound outputs"; font.bold: true }
                    Text {
                        text: cc.comb.active ? "Playing on all of the chosen outputs at once" : "Choose two or more outputs to play on together"
                        color: Theme.foreground; opacity: 0.65
                        font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSm
                    }
                }
                GlassButton {
                    visible: cc.comb.active
                    text: "Stop combining"
                    onClicked: SoundDevices.uncombine()
                }
                GlassButton {
                    text: cc.comb.active ? "Apply selection" : "Combine"
                    active: cc.comb.active
                    disabled: page.pickedList().length < 2
                    onClicked: SoundDevices.combine(page.pickedList())
                }
            }
            Flow {
                Layout.fillWidth: true
                spacing: 6
                Repeater {
                    model: SoundDevices.outputs
                    delegate: GlassButton {
                        required property var modelData
                        text: modelData.desc
                        active: !!page.picked[modelData.name]
                        onClicked: page.togglePick(modelData.name)
                    }
                }
            }
            VolRow {
                visible: cc.comb.active && cc.comb.channels.length > 0
                Layout.fillWidth: true
                title: "Volume"
                val: cc.comb.channels.length > 0 ? cc.comb.channels[0].pct : 0
                onMoved: (v) => SoundDevices.setCombinedVolume(v)
            }
            // one delay for every wired output inside the combined output (speakers, headphone jack, HDMI, USB)
            DelayRow {
                visible: SoundDevices.delay.available
                Layout.fillWidth: true
                val: SoundDevices.delay.ms
                onMoved: (v) => SoundDevices.setSpeakerDelay(v)
            }
            GlassButton {
                visible: SoundDevices.delay.available
                Layout.alignment: Qt.AlignRight
                text: "Reset delay"
                disabled: Math.round(SoundDevices.delay.ms) === 0
                onClicked: SoundDevices.setSpeakerDelay(0)
            }
            Hint {
                visible: SoundDevices.delay.available
                text: "The slider delays all wired outputs together (speakers, headphone jack, HDMI, USB), only inside the combined output. It is applied when you let go of the slider. Bluetooth outputs ignore it."
            }
            Hint {
                visible: cc.comb.active && (SoundDevices.delay.bt ?? []).length > 0
                text: "Bluetooth outputs are kept in step with the slowest one, re-checked every 10 seconds: " + page.btSyncText()
            }
        }
    }

    Flickable {
        id: flick
        anchors.fill: parent
        anchors.leftMargin: -14; anchors.rightMargin: -14   // horizontal gutter only (hover-scaled buttons); top/bottom clip at the real edge
        clip: true
        contentWidth: width
        contentHeight: col.implicitHeight + 8
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: col
            x: 14; y: 4
            width: flick.width - 28
            spacing: 12

            Hint { text: "Every sound device is listed on its own. Set the volume (or Left and Right separately), open the \u22EE menu for the profile and port, and choose which output and microphone the system uses. Changes apply at once." }

            RowLayout {
                spacing: 8
                GlassButton { text: "Outputs (" + SoundDevices.outNames.length + ")"; active: page.tab === "out"; onClicked: page.tab = "out" }
                GlassButton { text: "Microphones (" + SoundDevices.inNames.length + ")"; active: page.tab === "in"; onClicked: page.tab = "in" }
            }

            Hint { visible: SoundDevices.error !== ""; text: SoundDevices.error }
            Hint {
                visible: SoundDevices.error === "" && (page.tab === "out" ? SoundDevices.outputs.length : SoundDevices.inputs.length) === 0
                text: page.tab === "out" ? "No output devices found." : "No microphone found. Plug one in (or connect a headset) and it appears here."
            }

            CombineCard { visible: page.tab === "out" && SoundDevices.outputs.length > 1; Layout.fillWidth: true }

            Repeater {
                model: page.tab === "out" ? SoundDevices.outNames : SoundDevices.inNames
                delegate: DeviceCard {
                    required property string modelData
                    Layout.fillWidth: true
                    devName: modelData
                    kind: page.tab === "out" ? "sink" : "source"
                }
            }

            Hint { visible: page.tab === "in"; text: "Speak normally: the Hearing bar should reach the middle or higher. If it barely moves, raise the Level; if it hits the red end, lower it." }
            Item { Layout.preferredHeight: 4 }
        }
    }
}
