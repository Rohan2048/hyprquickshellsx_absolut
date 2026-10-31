import QtQuick

// All the shapes of a lock screen layout, positioned by their fractions of this item.
// Delegates are keyed by index, so editing a shape (dragging it in the editor) updates it
// in place instead of rebuilding it.
Item {
    id: root

    property var shapes: []

    Repeater {
        model: root.shapes.length
        delegate: LockShape {
            required property int index
            spec: root.shapes[index] || ({})
            x: (spec.fx || 0) * root.width
            y: (spec.fy || 0) * root.height
            width: (spec.fw || 0.1) * root.width
            height: (spec.fh || 0.1) * root.height
        }
    }
}
