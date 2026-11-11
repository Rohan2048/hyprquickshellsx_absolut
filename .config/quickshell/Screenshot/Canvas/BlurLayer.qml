pragma ComponentBehavior: Bound
import QtQuick
import "../../Services"

Item {
    id: root
    required property var annotationModel
    required property Item annotationStack
    z: 10

    readonly property bool selectionActive: ScreenshotSession.currentTool === "none"

    property int _selDragId: -1
    property real _selDragOffsetX: 0
    property real _selDragOffsetY: 0
    property real _selStartMouseX: 0
    property real _selStartMouseY: 0

    readonly property var _selItem: root.annotationModel.itemsArray()
    .find(a => a.type === "blur" && a.id === ScreenshotSession.selectedAnnotationId)

    function hitTestAt(mx, my) {
        const items = root.annotationModel.itemsArray().filter(i => i.type === "blur");
        const pad = 4;
        for (let i = items.length - 1; i >= 0; i--) {
            const a = items[i];
            if (mx >= a.x - pad && mx <= a.x + a.width + pad &&
                my >= a.y - pad && my <= a.y + a.height + pad) return a.id;
        }
        return -1;
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.selectionActive
        propagateComposedEvents: true
        onPressed: (mouse) => {
            const hitId = root.annotationStack.hitTestAll(mouse.x, mouse.y);
            const item = hitId !== -1 ? root.annotationModel.itemsArray().find(a => a.id === hitId) : null;
            if (item && item.type === "blur") {
                ScreenshotSession.selectAnnotation(hitId);
                root._selDragId = hitId;
                root._selStartMouseX = mouse.x;
                root._selStartMouseY = mouse.y;
                root._selDragOffsetX = 0;
                root._selDragOffsetY = 0;
                mouse.accepted = true;
            } else {
                if (root._selItem) ScreenshotSession.clearAnnotationSelection();
                mouse.accepted = false;
            }
        }
        onPositionChanged: (mouse) => {
            if (root._selDragId === -1) return;
            root._selDragOffsetX = mouse.x - root._selStartMouseX;
            root._selDragOffsetY = mouse.y - root._selStartMouseY;
        }
        onReleased: {
            if (root._selDragId === -1) return;
            if (root._selDragOffsetX !== 0 || root._selDragOffsetY !== 0) {
                const item = root.annotationModel.itemsArray().find(a => a.id === root._selDragId);
                if (item) {
                    ScreenshotSession.annotations.update(item.id, {
                        x: item.x + root._selDragOffsetX,
                        y: item.y + root._selDragOffsetY
                    });
                }
            }
            root._selDragId = -1;
            root._selDragOffsetX = 0;
            root._selDragOffsetY = 0;
        }
    }
}
