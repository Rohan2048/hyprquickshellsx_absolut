import QtQuick
import QtQuick.Layouts
import "../Services"
import "../Theme"
import "../Widgets"

// Settings > Theme > Border: the border of every panel (bar, popups, notifications ...). One setting for all
// themes, below the theme options. Live preview at the bottom; everything is stored by Services/BorderSettings.
ColumnLayout {
    id: sec

    spacing: 10
    property string openKey: ""                         // the colour picker that is open
    function toggleOpen(key) { sec.openKey = (sec.openKey === key) ? "" : key }

    component Hint: Text {
        color: Theme.foreground
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSm
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
    }
    component Lbl: Text {
        color: Theme.foreground
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        Layout.preferredWidth: 130
        elide: Text.ElideRight
    }
    // "label ---slider--- 3 unit"
    component SliderRow: RowLayout {
        id: sr
        property string label: ""
        property string key: ""
        property real from: 0
        property real to: 10
        property string unit: ""
        Layout.fillWidth: true
        spacing: 10
        Lbl { text: sr.label }
        GlassSlider {
            Layout.fillWidth: true
            Layout.preferredHeight: 26
            min: sr.from
            max: sr.to
            value: BorderSettings[sr.key]
            onValueCommitted: (v) => BorderSettings.set(sr.key, Math.round(v))
        }
        Text {
            text: BorderSettings[sr.key] + " " + sr.unit
            color: Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            Layout.preferredWidth: 56
            horizontalAlignment: Text.AlignRight
        }
    }

    // ---- on / off ----
    RowLayout {
        Layout.fillWidth: true
        spacing: 10
        Lbl { text: "Panel borders" }
        GlassButton { text: "On"; active: BorderSettings.enabled; onClicked: BorderSettings.set("enabled", true) }
        GlassButton { text: "Off"; active: !BorderSettings.enabled; onClicked: BorderSettings.set("enabled", false) }
    }
    Hint { text: "One setting for every theme (Transparent, Opaque and your own): it draws the border around the bar, popups and notifications. Off removes the borders everywhere." }

    ColumnLayout {
        visible: BorderSettings.enabled
        Layout.fillWidth: true
        spacing: 10

        // ---- preview ----
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 92
            Rectangle {
                id: pvPanel
                anchors.centerIn: parent
                width: Math.min(parent.width, 360)
                height: 64
                radius: BorderSettings.radiusFor(Theme.radiusMd)
                color: Qt.rgba(Theme.foreground.r, Theme.foreground.g, Theme.foreground.b, 0.06)
                PanelBorder {
                    tl: pvPanel.radius; tr: pvPanel.radius; bl: pvPanel.radius; br: pvPanel.radius
                }
                Text {
                    anchors.centerIn: parent
                    text: "Preview"
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                }
            }
        }

        // ---- shape ----
        SliderRow { label: "Thickness"; key: "thickness"; from: 1; to: 8; unit: "px" }
        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            Lbl { text: "Corner radius" }
            GlassButton { text: "Each panel's own"; active: BorderSettings.radiusMode === "panel"; onClicked: BorderSettings.set("radiusMode", "panel") }
            GlassButton { text: "Custom"; active: BorderSettings.radiusMode === "custom"; onClicked: BorderSettings.set("radiusMode", "custom") }
        }
        SliderRow {
            visible: BorderSettings.radiusMode === "custom"
            label: "Radius"; key: "customRadius"; from: 0; to: 40; unit: "px"
        }
        Hint {
            visible: BorderSettings.radiusMode === "custom"
            text: "Custom gives every panel (and its border) this corner radius, instead of the radius set for each popup in Settings > Popups."
        }

        // ---- colour ----
        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            Lbl { text: "Colour" }
            GlassButton { text: "Theme"; active: BorderSettings.colorType === "theme"; onClicked: BorderSettings.set("colorType", "theme") }
            GlassButton { text: "Solid"; active: BorderSettings.colorType === "solid"; onClicked: BorderSettings.set("colorType", "solid") }
            GlassButton { text: "Gradient"; active: BorderSettings.colorType === "gradient"; onClicked: BorderSettings.set("colorType", "gradient") }
        }
        ColorField {
            visible: BorderSettings.colorType === "solid"
            Layout.fillWidth: true
            label: "Border"
            col: BorderSettings.color
            open: sec.openKey === "solid"
            onToggled: sec.toggleOpen("solid")
            onEdited: (v) => BorderSettings.set("color", v)
        }
        ColumnLayout {
            visible: BorderSettings.colorType === "gradient"
            Layout.fillWidth: true
            spacing: 6
            Repeater {
                model: BorderSettings.stops
                delegate: ColorField {
                    id: stopField
                    required property int index
                    Layout.fillWidth: true
                    label: "Colour " + (stopField.index + 1)
                    col: BorderSettings.stops[stopField.index]
                    removable: BorderSettings.stops.length > 2
                    open: sec.openKey === "stop." + stopField.index
                    onToggled: sec.toggleOpen("stop." + stopField.index)
                    onEdited: (v) => {
                        const s = BorderSettings.stops.slice(); s[stopField.index] = v
                        BorderSettings.set("stops", s)
                    }
                    onRemoved: {
                        const s = BorderSettings.stops.slice(); s.splice(stopField.index, 1)
                        BorderSettings.set("stops", s)
                        sec.openKey = ""
                    }
                }
            }
            GlassButton {
                visible: BorderSettings.stops.length < 6
                text: "+ Add colour"
                onClicked: {
                    const s = BorderSettings.stops.slice()
                    s.push({ mode: "dyn", i: (s.length * 3 + 1) % 16 })
                    BorderSettings.set("stops", s)
                }
            }
        }
        Hint {
            visible: BorderSettings.colorType === "theme"
            text: "Theme: the theme's own muted border colour, as before."
        }

        // ---- effects ----
        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            Lbl { text: "Rotation" }
            GlassButton { text: "Off"; active: !BorderSettings.rotate; onClicked: BorderSettings.set("rotate", false) }
            GlassButton { text: "On"; active: BorderSettings.rotate; onClicked: BorderSettings.set("rotate", true) }
        }
        ColumnLayout {
            visible: BorderSettings.rotate
            Layout.fillWidth: true
            spacing: 10
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Lbl { text: "Direction" }
                GlassButton { text: "Clockwise \u21BB"; active: BorderSettings.rotateDir === "cw"; onClicked: BorderSettings.set("rotateDir", "cw") }
                GlassButton { text: "Anticlockwise \u21BA"; active: BorderSettings.rotateDir === "ccw"; onClicked: BorderSettings.set("rotateDir", "ccw") }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Lbl { text: "What turns" }
                GlassButton { text: "A streak"; active: BorderSettings.rotateMode === "streak"; onClicked: BorderSettings.set("rotateMode", "streak") }
                GlassButton { text: "The whole border"; active: BorderSettings.rotateMode === "whole"; onClicked: BorderSettings.set("rotateMode", "whole") }
            }
            SliderRow {
                visible: BorderSettings.rotateMode === "streak"
                label: "Streak size"; key: "streakPct"; from: 5; to: 60; unit: "%"
            }
            Hint {
                visible: BorderSettings.rotateMode === "whole" && BorderSettings.colorType !== "gradient"
                text: "The whole border only shows a turning effect with a Gradient colour; a single colour looks the same all the way round."
            }
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            Lbl { text: "Pulse" }
            GlassButton { text: "Off"; active: !BorderSettings.pulse; onClicked: BorderSettings.set("pulse", false) }
            GlassButton { text: "On"; active: BorderSettings.pulse; onClicked: BorderSettings.set("pulse", true) }
        }
        SliderRow {
            visible: BorderSettings.rotate || BorderSettings.pulse
            label: "Effect speed"; key: "speed"; from: 1; to: 10; unit: ""
        }

        // ---- anime streaks (NFS Unbound style) ----
        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            Lbl { text: "Anime streaks" }
            GlassButton { text: "Off"; active: !BorderSettings.anime; onClicked: BorderSettings.set("anime", false) }
            GlassButton { text: "On"; active: BorderSettings.anime; onClicked: BorderSettings.set("anime", true) }
        }
        ColumnLayout {
            visible: BorderSettings.anime
            Layout.fillWidth: true
            spacing: 10
            SliderRow { label: "Frame rate"; key: "animeFps"; from: 5; to: 15; unit: "fps" }
            SliderRow { label: "Streaks"; key: "animeStreaks"; from: 1; to: 8; unit: "" }
            SliderRow { label: "Glitch"; key: "animeGlitch"; from: 0; to: 10; unit: "" }
            Hint { text: "Hand-animated look inspired by NFS Unbound: the border is redrawn only 5 to 15 times a second, so speed streaks run round it in jumps (some turn wavy and ride just outside the border), the line jitters a little, and now and then specks, a small x or o, and a misprinted ghost of the outline flicker by. Where a panel has no room around it (the bar, or a popup near a screen edge) the wavy streaks, specks and x / o are drawn just inside the border instead. The Theme tiles never use the border effects. It uses the Colour above (a Gradient gives the streaks two colours) and can be combined with Rotation and Pulse. Lower frame rates look choppier and cost less." }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 2
            GlassButton { text: "Reset border"; onClicked: BorderSettings.reset() }
        }
    }
}
