import QtQuick.Layouts
import QtQuick
import "../Widgets"
import "../Services"
import "../Theme"

RowLayout {
    // Keep the container height strictly fixed so surrounding elements never shift
    Layout.preferredHeight: 34
    spacing: 16 // Give enough space between the icon and the slider
    clip: false // Prevents any accidental clipping during the height animation

    Text {
        text: Volume.muted ? "🔇" : "🔊"
        font.pixelSize: Theme.fs(13)
        color: Theme.foreground

        // Lock the text vertically so it doesn't move a single pixel when the slider expands
        Layout.alignment: Qt.AlignVCenter
    }

    GlassSlider {
        id: volumeSlider
        Layout.fillWidth: true
        Layout.rightMargin: 10
        // Reduce default height (20), expand to full height (34) only when pressed/dragged
        Layout.preferredHeight: pressed ? 34 : 30

        // Ensures the slider expands symmetrically from the center, never pushing the text
        Layout.alignment: Qt.AlignVCenter

        value: Volume.volume
        onValueCommitted: (v) => Volume.setVolume(v)

        // Smooth, snappy expansion animation
        Behavior on Layout.preferredHeight {
            NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
        }
    }
}
