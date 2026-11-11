import QtQuick
import "../Theme"
import "../Services"

// The border of an input field or inner box, driven by Settings > Theme > Border exactly like the panels:
// on / off, thickness, colour (theme / solid / gradient), rotation and pulse effects and the corner radius
// mode all come from BorderSettings (it is the same painter, Widgets/PanelBorder.qml).
// Use it as `background: FieldBorder { focused: field.activeFocus }`. When focused, an accent outline of
// the same thickness is drawn over it, so you can still see where the cursor is (also when borders are off).
Item {
    id: fb

    property real radius: Theme.radiusSm      // the field's own radius (a "custom" radius in Border settings replaces it)
    property bool focused: false

    readonly property real r: BorderSettings.radiusFor(fb.radius)

    PanelBorder { tl: fb.r; tr: fb.r; bl: fb.r; br: fb.r }

    Rectangle {
        anchors.fill: parent
        visible: fb.focused
        color: "transparent"
        radius: fb.r
        border.width: BorderSettings.enabled ? BorderSettings.thickness : 1
        border.color: Theme.accentActive
    }
}
