pragma ComponentBehavior: Bound
import QtQuick
import "../../Services"

Item {
    id: root
    anchors.fill: parent
    required property Item annotationStack
    readonly property bool placementActive: ScreenshotSession.currentTool === "text"
    readonly property bool selectionActive: ScreenshotSession.currentTool === "none"
    readonly property var _selItem: ScreenshotSession.annotations.itemsArray().find(a => a.id === ScreenshotSession.selectedAnnotationId)

    function hitTestText(mx, my) {
        return root.annotationStack.hitTestText(mx, my);
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.placementActive || root.selectionActive
        propagateComposedEvents: true
        onPressed: (mouse) => {
            const hitId = root.annotationStack.hitTestAll(mouse.x, mouse.y);
            const item = hitId !== -1 ? ScreenshotSession.annotations.itemsArray().find(a => a.id === hitId) : null;
            if (root.placementActive) {
                if (item && item.type === "text") {
                    ScreenshotSession.selectAnnotation(hitId);
                    mouse.accepted = true;
                    return;
                }
                ScreenshotSession.clearAnnotationSelection();
                const id = ScreenshotSession.annotations.add({
                    type: "text",
                    x: mouse.x,
                    y: mouse.y,
                    text: "",
                    fontSize: ScreenshotSession.annotationFontSize,
                    fontFamily: ScreenshotSession.annotationFontFamily,
                    color: ScreenshotSession.annotationColor
                });
                ScreenshotSession.selectAnnotation(id);
                mouse.accepted = true;
            } else {
                if (item && item.type === "text") {
                    mouse.accepted = false;
                    return;
                }
                const sel = root._selItem;
                if (!sel || sel.type === "text") {
                    ScreenshotSession.clearAnnotationSelection();
                }
                mouse.accepted = false;

            }
        }
    }
}
