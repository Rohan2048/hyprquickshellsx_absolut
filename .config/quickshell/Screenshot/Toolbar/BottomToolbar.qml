pragma ComponentBehavior: Bound
import QtQuick
import "../../Services"
import "../../Theme"

Rectangle {
    id: root

    required property var screenshotWindow

    anchors {
        bottom: parent.bottom
        horizontalCenter: parent.horizontalCenter
        bottomMargin: 16
    }
    width: loader.item ? loader.item.implicitWidth + 24 : 0
    height: 48
    radius: Theme.radiusMd
    color: Theme.popupBg

    Loader {
        id: loader
        anchors.centerIn: parent
        sourceComponent: {
            if (ScreenshotSession.layersPanelOpen) return layersOptionsComponent;
            if (ScreenshotSession.currentTool === "text") return textOptionsComponent;
            if (["arrow", "line", "circle", "rectangle", "doodle", "eraser"].includes(ScreenshotSession.currentTool))
                return shapeOptionsComponent;
            return mainRowComponent;
        }
    }

    Component {
        id: mainRowComponent
        Row {
            spacing: 8

            ToolButton {
                label: "Fullscreen"
                onClicked: ScreenshotSession.setMode("fullscreen")
            }
            ToolButton {
                label: "Crop"
                checkable: true
                checked: ScreenshotSession.currentMode === "crop"
                onClicked: ScreenshotSession.toggleCropMode()
            }
            ToolButton {
                label: "Apply Crop"
                enabled: ScreenshotSession.currentMode === "crop" && ScreenshotSession.hasSelection
                onClicked: ScreenshotSession.commitCrop()
            }

            Rectangle { width: 1; height: 28; color: Theme.borderMuted }

            ToolButton { label: "Text"; checkable: true; checked: ScreenshotSession.currentTool === "text"; onClicked: ScreenshotSession.setTool("text") }
            ToolButton { label: "Arrow"; checkable: true; checked: ScreenshotSession.currentTool === "arrow"; onClicked: ScreenshotSession.setTool("arrow") }
            ToolButton { label: "Line"; checkable: true; checked: ScreenshotSession.currentTool === "line"; onClicked: ScreenshotSession.setTool("line") }
            ToolButton { label: "Rect"; checkable: true; checked: ScreenshotSession.currentTool === "rectangle"; onClicked: ScreenshotSession.setTool("rectangle") }
            ToolButton { label: "Circle"; checkable: true; checked: ScreenshotSession.currentTool === "circle"; onClicked: ScreenshotSession.setTool("circle") }
            ToolButton { label: "Doodle"; checkable: true; checked: ScreenshotSession.currentTool === "doodle"; onClicked: ScreenshotSession.setTool("doodle") }
            ToolButton { label: "Blur"; checkable: true; checked: ScreenshotSession.currentTool === "blur"; onClicked: ScreenshotSession.setTool("blur") }
            ToolButton { label: "Layers"; checkable: true; checked: ScreenshotSession.layersPanelOpen; onClicked: ScreenshotSession.toggleLayersPanel() }
            Rectangle { width: 1; height: 28; color: Theme.borderMuted }

            ToolButton { label: "Undo"; onClicked: ScreenshotSession.undo() }
            ToolButton { label: "Redo"; onClicked: ScreenshotSession.redo() }
        }
    }

    Component {
        id: textOptionsComponent
        TextOptionsBar { screenshotWindow: root.screenshotWindow }
    }
    Component {
        id: shapeOptionsComponent
        ShapeOptionsBar { screenshotWindow: root.screenshotWindow }

    }
    Component {
        id: layersOptionsComponent
        Row {
            spacing: 8
            readonly property bool hasSel: ScreenshotSession.selectedAnnotationId !== -1

            ToolButton {
                label: "Set Front"
                enabled: parent.hasSel
                onClicked: ScreenshotSession.annotations.bringForward(ScreenshotSession.selectedAnnotationId)
            }
            ToolButton {
                label: "Set Behind"
                enabled: parent.hasSel
                onClicked: ScreenshotSession.annotations.sendBackward(ScreenshotSession.selectedAnnotationId)
            }
            ToolButton {
                label: "Set Very Front"
                enabled: parent.hasSel
                onClicked: ScreenshotSession.annotations.bringToFront(ScreenshotSession.selectedAnnotationId)
            }
            ToolButton {
                label: "Set Bottom"
                enabled: parent.hasSel
                onClicked: ScreenshotSession.annotations.sendToBack(ScreenshotSession.selectedAnnotationId)
            }

            Rectangle { width: 1; height: 28; color: Theme.borderMuted }

            ToolButton { label: "Done"; onClicked: ScreenshotSession.toggleLayersPanel() }
        }
    }
}
