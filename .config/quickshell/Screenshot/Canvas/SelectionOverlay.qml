pragma ComponentBehavior: Bound
import QtQuick
import "../../Services"
import "../../Theme"

Item {
    id: root
    anchors.fill: parent
    visible: ScreenshotSession.currentMode === "crop"
    enabled: visible && ScreenshotSession.currentTool === "none"
    z: 10
    property real selX: 0
    property real selY: 0
    property real selW: 0
    property real selH: 0
    property bool hasSelection: false

    property bool _dragging: false
    property real _dragStartX: 0
    property real _dragStartY: 0

    readonly property int handleSize: 12
    readonly property int minSize: 20

    function _clampAndCommit() {
        if (root.selX < 0) { root.selW += root.selX; root.selX = 0; }
        if (root.selY < 0) { root.selH += root.selY; root.selY = 0; }
        if (root.selX + root.selW > root.width) root.selW = root.width - root.selX;
        if (root.selY + root.selH > root.height) root.selH = root.height - root.selY;
        if (root.selW < 0) root.selW = 0;
        if (root.selH < 0) root.selH = 0;
        root.hasSelection = root.selW >= root.minSize && root.selH >= root.minSize;
        if (root.hasSelection)
            ScreenshotSession.setSelection(Qt.rect(root.selX, root.selY, root.selW, root.selH));
        else
            ScreenshotSession.clearSelection();
    }

    MouseArea {
        id: drawArea
        anchors.fill: parent
        onPressed: (mouse) => {
            root._dragging = true;
            root._dragStartX = mouse.x;
            root._dragStartY = mouse.y;
            root.selX = mouse.x;
            root.selY = mouse.y;
            root.selW = 0;
            root.selH = 0;
            root.hasSelection = false;
        }
        onPositionChanged: (mouse) => {
            if (!root._dragging) return;
            root.selX = Math.min(root._dragStartX, mouse.x);
            root.selY = Math.min(root._dragStartY, mouse.y);
            root.selW = Math.abs(mouse.x - root._dragStartX);
            root.selH = Math.abs(mouse.y - root._dragStartY);
        }
        onReleased: {
            root._dragging = false;
            root._clampAndCommit();
        }
    }

    Rectangle { // dim: top
        color: "#99000000"; visible: root.hasSelection
        x: 0; y: 0; width: root.width; height: root.selY
    }
    Rectangle { // dim: bottom
        color: "#99000000"; visible: root.hasSelection
        x: 0; y: root.selY + root.selH
        width: root.width; height: root.height - (root.selY + root.selH)
    }
    Rectangle { // dim: left
        color: "#99000000"; visible: root.hasSelection
        x: 0; y: root.selY; width: root.selX; height: root.selH
    }
    Rectangle { // dim: right
        color: "#99000000"; visible: root.hasSelection
        x: root.selX + root.selW; y: root.selY
        width: root.width - (root.selX + root.selW); height: root.selH
    }

    Rectangle {
        id: selectionBorder
        visible: root.hasSelection
        x: root.selX; y: root.selY
        width: root.selW; height: root.selH
        color: "transparent"
        border.color: Theme.color3
        border.width: 2

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.SizeAllCursor
            property real lastX: 0
            property real lastY: 0
            onPressed: (mouse) => {
                const p = mapToItem(root, mouse.x, mouse.y);
                lastX = p.x; lastY = p.y;
            }
            onPositionChanged: (mouse) => {
                if (!pressed) return;
                const p = mapToItem(root, mouse.x, mouse.y);
                root.selX += p.x - lastX;
                root.selY += p.y - lastY;
                lastX = p.x; lastY = p.y;
            }
            onReleased: root._clampAndCommit()
        }
    }

    Repeater {
        model: [
            { id: "tl", cursor: Qt.SizeFDiagCursor }, { id: "t",  cursor: Qt.SizeVerCursor },
            { id: "tr", cursor: Qt.SizeBDiagCursor }, { id: "l",  cursor: Qt.SizeHorCursor },
            { id: "r",  cursor: Qt.SizeHorCursor },  { id: "bl", cursor: Qt.SizeBDiagCursor },
            { id: "b",  cursor: Qt.SizeVerCursor },  { id: "br", cursor: Qt.SizeFDiagCursor }
        ]
        delegate: Rectangle {
            id: handle
            required property var modelData
            visible: root.hasSelection
            width: root.handleSize; height: root.handleSize
            radius: root.handleSize / 2
            color: Theme.color3
            border.color: "#ffffff"
            border.width: 1

            x: {
                switch (modelData.id) {
                    case "tl": case "l": case "bl": return root.selX - width / 2;
                    case "tr": case "r": case "br": return root.selX + root.selW - width / 2;
                    default: return root.selX + root.selW / 2 - width / 2;
                }
            }
            y: {
                switch (modelData.id) {
                    case "tl": case "t": case "tr": return root.selY - height / 2;
                    case "bl": case "b": case "br": return root.selY + root.selH - height / 2;
                    default: return root.selY + root.selH / 2 - height / 2;
                }
            }

            MouseArea {
                anchors.fill: parent
                anchors.margins: -6
                cursorShape: handle.modelData.cursor
                property real lastX: 0
                property real lastY: 0
                onPressed: (mouse) => {
                    const p = mapToItem(root, mouse.x, mouse.y);
                    lastX = p.x; lastY = p.y;
                }
                onPositionChanged: (mouse) => {
                    if (!pressed) return;
                    const p = mapToItem(root, mouse.x, mouse.y);
                    const dx = p.x - lastX;
                    const dy = p.y - lastY;
                    lastX = p.x; lastY = p.y;
                    const id = handle.modelData.id;
                    if (id.includes("l")) { root.selX += dx; root.selW -= dx; }
                    if (id.includes("r")) { root.selW += dx; }
                    if (id.includes("t")) { root.selY += dy; root.selH -= dy; }
                    if (id.includes("b")) { root.selH += dy; }
                }
                onReleased: root._clampAndCommit()
            }
        }
    }
}
