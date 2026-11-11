pragma ComponentBehavior: Bound
import QtQuick
import "../../Services"
import "../../Theme"

Row {
    id: root
    spacing: 8

    required property var screenshotWindow
    readonly property string tool: ScreenshotSession.currentTool

    readonly property bool showFill: ["circle", "rectangle"].includes(root.tool)
    readonly property bool showCornerRadius: root.tool === "rectangle"
    readonly property bool showHighlighter: root.tool === "doodle"
    readonly property bool showDotted: ["arrow", "line", "circle", "rectangle", "doodle"].includes(root.tool)
    readonly property bool showEraser: ["arrow", "line", "circle", "rectangle", "doodle"].includes(root.tool)
    readonly property bool showColor: root.tool !== "eraser"

    property bool _colorPopupOpen: false
    onShowColorChanged: {
        if (!root.showColor) {
            root._colorPopupOpen = false;
            ScreenshotSession.colorPopupOpen = false;
        }
    }

    ToolButton {
        label: "←"
        onClicked: ScreenshotSession.setTool(root.tool)
    }

    Rectangle { width: 1; height: 28; color: Theme.borderMuted }

    Item {
        id: colorWheelRoot
        visible: root.showColor
        width: 28
        height: 28
        Image { anchors.fill: parent; source: Qt.resolvedUrl("../../assets/hue_ring.png"); smooth: true; cache: true }
        Rectangle {
            anchors.centerIn: parent
            width: parent.width * 0.55; height: width; radius: width / 2
            color: ScreenshotSession.annotationColor
            Text { anchors.centerIn: parent; text: "+"; color: "white"; font.pixelSize: Theme.fs(12); font.bold: true }
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                root._colorPopupOpen = !root._colorPopupOpen;
                ScreenshotSession.colorPopupOpen = root._colorPopupOpen;
            }
        }
    }

    Item {
        parent: root.screenshotWindow ? root.screenshotWindow.contentItem : root
        anchors.fill: parent
        visible: colorPopup.visible
        z: 999
        MouseArea {
            anchors.fill: parent
            onClicked: { root._colorPopupOpen = false; ScreenshotSession.colorPopupOpen = false; }
        }
    }

    Rectangle {
        id: colorPopup
        parent: root.screenshotWindow ? root.screenshotWindow.contentItem : root
        visible: root._colorPopupOpen && root.showColor
        z: 1000
        x: colorWheelRoot.mapToItem(parent, 0, 0).x - width / 2 + colorWheelRoot.width / 2
        y: colorWheelRoot.mapToItem(parent, 0, 0).y - height - 12
        width: 200; height: 300
        radius: Theme.radiusMd
        color: Qt.rgba(Theme.popupBg.r, Theme.popupBg.g, Theme.popupBg.b, 0.75)
        border.width: 1; border.color: Theme.borderMuted

        property real hue: 0
        property real sat: 1
        property real val: 1
        property real alpha: 1

        function hsvToRgb(h, s, v) {
            const c = v * s;
            const x = c * (1 - Math.abs((h / 60) % 2 - 1));
            const m = v - c;
            let r = 0, g = 0, b = 0;
            if (h < 60)       { r = c; g = x; b = 0; }
            else if (h < 120) { r = x; g = c; b = 0; }
            else if (h < 180) { r = 0; g = c; b = x; }
            else if (h < 240) { r = 0; g = x; b = c; }
            else if (h < 300) { r = x; g = 0; b = c; }
            else              { r = c; g = 0; b = x; }
            return Qt.rgba(r + m, g + m, b + m, 1.0);
        }
        function commit() {
            const rgb = hsvToRgb(colorPopup.hue, colorPopup.sat, colorPopup.val);
            ScreenshotSession.setAnnotationColor(Qt.rgba(rgb.r, rgb.g, rgb.b, colorPopup.alpha));
        }
        readonly property color hueColor: hsvToRgb(colorPopup.hue, 1.0, 1.0)

        MouseArea { anchors.fill: parent; onClicked: {} }

        Column {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            Item {
                id: hueRingArea
                width: 140; height: 140
                anchors.horizontalCenter: parent.horizontalCenter
                Image { anchors.fill: parent; source: Qt.resolvedUrl("../../assets/hue_ring.png"); smooth: true }
                Rectangle {
                    width: 12; height: 12; radius: 6
                    color: colorPopup.hueColor
                    border.width: 2; border.color: "white"
                    readonly property real ringRadius: hueRingArea.width / 2 - 8
                    x: hueRingArea.width / 2 + ringRadius * Math.cos(colorPopup.hue * Math.PI / 180) - width / 2
                    y: hueRingArea.height / 2 + ringRadius * Math.sin(colorPopup.hue * Math.PI / 180) - height / 2
                }
                MouseArea {
                    anchors.fill: parent
                    function updateHue(mx, my) {
                        const cx = hueRingArea.width / 2, cy = hueRingArea.height / 2;
                        let angle = Math.atan2(my - cy, mx - cx) * 180 / Math.PI;
                        if (angle < 0) angle += 360;
                        colorPopup.hue = angle;
                    }
                    onPressed: (mouse) => updateHue(mouse.x, mouse.y)
                    onPositionChanged: (mouse) => { if (pressed) updateHue(mouse.x, mouse.y); }
                    onReleased: colorPopup.commit()
                }
            }

            Item {
                id: svSquare
                width: 140; height: 100
                anchors.horizontalCenter: parent.horizontalCenter
                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: "white" }
                        GradientStop { position: 1.0; color: colorPopup.hueColor }
                    }
                }
                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: "transparent" }
                        GradientStop { position: 1.0; color: "black" }
                    }
                }
                Rectangle {
                    width: 12; height: 12; radius: 6
                    color: "transparent"; border.width: 2; border.color: "white"
                    x: colorPopup.sat * svSquare.width - width / 2
                    y: (1 - colorPopup.val) * svSquare.height - height / 2
                }
                MouseArea {
                    anchors.fill: parent
                    function updateSV(mx, my) {
                        colorPopup.sat = Math.max(0, Math.min(1, mx / svSquare.width));
                        colorPopup.val = 1 - Math.max(0, Math.min(1, my / svSquare.height));
                    }
                    onPressed: (mouse) => updateSV(mouse.x, mouse.y)
                    onPositionChanged: (mouse) => { if (pressed) updateSV(mouse.x, mouse.y); }
                    onReleased: colorPopup.commit()
                }
            }

            Item {
                id: alphaSlider
                width: 140; height: 20
                anchors.horizontalCenter: parent.horizontalCenter
                Rectangle {
                    anchors.fill: parent
                    radius: 4
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: Qt.rgba(colorPopup.hueColor.r, colorPopup.hueColor.g, colorPopup.hueColor.b, 0.0) }
                        GradientStop { position: 1.0; color: Qt.rgba(colorPopup.hueColor.r, colorPopup.hueColor.g, colorPopup.hueColor.b, 1.0) }
                    }
                }
                Rectangle {
                    width: 6; height: alphaSlider.height + 4; radius: 3
                    color: "white"; border.width: 1; border.color: Theme.borderMuted
                    x: colorPopup.alpha * (alphaSlider.width - width)
                    y: -2
                }
                MouseArea {
                    anchors.fill: parent
                    function updateAlpha(mx) { colorPopup.alpha = Math.max(0, Math.min(1, mx / alphaSlider.width)); }
                    onPressed: (mouse) => updateAlpha(mouse.x)
                    onPositionChanged: (mouse) => { if (pressed) updateAlpha(mouse.x); }
                    onReleased: colorPopup.commit()
                }
            }
        }
    }

    Rectangle { width: 1; height: 28; color: Theme.borderMuted; visible: root.showColor }

    // Thickness slider — used by every tool that reaches this bar
    Row {
        spacing: 6
        Text { text: "Width"; color: Theme.foreground; font.pixelSize: Theme.fs(12); anchors.verticalCenter: parent.verticalCenter }
        Rectangle {
            id: widthTrack
            width: 90; height: 6; radius: 3
            color: Theme.hoverBgStrong
            anchors.verticalCenter: parent.verticalCenter
            Rectangle {
                width: widthHandle.x + widthHandle.width / 2
                height: parent.height; radius: 3
                color: Theme.color3
            }
            Rectangle {
                id: widthHandle
                width: 14; height: 14; radius: 7
                color: "white"; border.width: 1; border.color: Theme.borderMuted
                y: -4
                x: Math.max(0, Math.min(widthTrack.width - width, (ScreenshotSession.annotationStrokeWidth / 40) * widthTrack.width - width / 2))
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -6
                    drag.target: parent
                    drag.axis: Drag.XAxis
                    drag.minimumX: -width / 2
                    drag.maximumX: widthTrack.width - widthHandle.width / 2
                    onPositionChanged: {
                        const ratio = Math.max(0, Math.min(1, (widthHandle.x + widthHandle.width / 2) / widthTrack.width));
                        const newWidth = Math.max(1, ratio * 40);
                        ScreenshotSession.annotationStrokeWidth = newWidth;
                        if (ScreenshotSession.selectedAnnotationId !== -1)
                            ScreenshotSession.annotations.update(ScreenshotSession.selectedAnnotationId, { strokeWidth: newWidth });
                    }
                }
            }
        }
    }

    ToolButton {
        visible: root.showDotted
        label: "Dotted"
        checkable: true
        checked: ScreenshotSession.annotationDotted
        onClicked: {
            ScreenshotSession.annotationDotted = !ScreenshotSession.annotationDotted;
            if (ScreenshotSession.selectedAnnotationId !== -1)
                ScreenshotSession.annotations.update(ScreenshotSession.selectedAnnotationId, { dotted: ScreenshotSession.annotationDotted });
        }
    }

    ToolButton {
        visible: root.showFill
        label: ScreenshotSession.annotationFilled ? "Fill" : "Hollow"
        checkable: true
        checked: ScreenshotSession.annotationFilled
        onClicked: {
            ScreenshotSession.annotationFilled = !ScreenshotSession.annotationFilled;
            if (ScreenshotSession.selectedAnnotationId !== -1)
                ScreenshotSession.annotations.update(ScreenshotSession.selectedAnnotationId, { filled: ScreenshotSession.annotationFilled });
        }
    }

    Row {
        visible: root.showCornerRadius
        spacing: 6
        Text { text: "Radius"; color: Theme.foreground; font.pixelSize: Theme.fs(12); anchors.verticalCenter: parent.verticalCenter }
        Rectangle {
            id: radiusTrack
            width: 70; height: 6; radius: 3
            color: Theme.hoverBgStrong
            anchors.verticalCenter: parent.verticalCenter
            Rectangle {
                id: radiusHandle
                width: 14; height: 14; radius: 7
                color: "white"; border.width: 1; border.color: Theme.borderMuted
                y: -4
                x: Math.max(0, Math.min(radiusTrack.width - width, (ScreenshotSession.annotationCornerRadius / 40) * radiusTrack.width - width / 2))
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -6
                    drag.target: parent
                    drag.axis: Drag.XAxis
                    drag.minimumX: -width / 2
                    drag.maximumX: radiusTrack.width - radiusHandle.width / 2
                    onPositionChanged: {
                        const ratio = Math.max(0, Math.min(1, (radiusHandle.x + radiusHandle.width / 2) / radiusTrack.width));
                        const newRadius = ratio * 40;
                        ScreenshotSession.annotationCornerRadius = newRadius;
                        if (ScreenshotSession.selectedAnnotationId !== -1)
                            ScreenshotSession.annotations.update(ScreenshotSession.selectedAnnotationId, { cornerRadius: newRadius });
                    }
                }
            }
        }
    }

    ToolButton {
        visible: root.showHighlighter
        label: "Highlighter"
        checkable: true
        checked: ScreenshotSession.annotationHighlighter
        onClicked: ScreenshotSession.annotationHighlighter = !ScreenshotSession.annotationHighlighter
    }

    ToolButton {
        visible: root.showEraser
        label: "Eraser"
        checkable: true
        checked: ScreenshotSession.currentTool === "eraser"
        onClicked: ScreenshotSession.setTool("eraser")
    }
}
