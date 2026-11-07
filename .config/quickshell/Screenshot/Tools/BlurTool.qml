pragma ComponentBehavior: Bound
import QtQuick

// Drag-rectangle capture for blur regions. Same interaction shape as a
// RegionTool would use, but commits a "blur" item instead of a selection.
Item {
    id: root
    required property var annotationModel
    property real blurRadius: 48

    property real startX: 0
    property real startY: 0
    property bool dragging: false

    Rectangle {
        id: preview
        visible: root.dragging
        color: "transparent"
        border.color: "#ffffff"
        border.width: 1
        radius: 2
    }

    MouseArea {
        anchors.fill: parent
        onPressed: (mouse) => {
            root.dragging = true
            root.startX = mouse.x
            root.startY = mouse.y
            preview.x = mouse.x
            preview.y = mouse.y
            preview.width = 0
            preview.height = 0
        }
        onPositionChanged: (mouse) => {
            if (!root.dragging) return
                preview.x = Math.min(mouse.x, root.startX)
                preview.y = Math.min(mouse.y, root.startY)
                preview.width = Math.abs(mouse.x - root.startX)
                preview.height = Math.abs(mouse.y - root.startY)
        }
        onReleased: (mouse) => {
            if (!root.dragging) return
                root.dragging = false
                if (preview.width < 4 || preview.height < 4) return

                    root.annotationModel.add({
                        type: "blur",
                        x: preview.x,
                        y: preview.y,
                        width: preview.width,
                        height: preview.height,
                        radius: root.blurRadius
                    })
        }
    }
}
