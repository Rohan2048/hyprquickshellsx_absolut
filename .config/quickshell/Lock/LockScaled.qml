import QtQuick

// Stretches / compresses ONE child (the lock screen's clock, a button row, ...) and takes the size of the result,
// so it can be placed with the usual LockPresets.place maths.
//
//   LockScaled { child: thing; sx: 1.4; sy: 1; Thing { id: thing } }
//
// `child` names the wrapped item (its own width / height are the unstretched size). The stretch is a plain
// transform: the child keeps working (clicks, hover, animations); only its picture is scaled.
Item {
    id: root

    property Item child: null
    property real sx: 1
    property real sy: 1
    default property alias content: holder.data

        readonly property real baseWidth: root.child ? root.child.width : 0
        readonly property real baseHeight: root.child ? root.child.height : 0

        width: root.baseWidth * root.sx
        height: root.baseHeight * root.sy

        Item {
            id: holder
            width: root.baseWidth
            height: root.baseHeight
            transform: Scale { xScale: root.sx; yScale: root.sy }
        }
}
