pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import "../../Services"
import "../../Theme"

Row {
    id: root
    spacing: 8

    required property var screenshotWindow

    readonly property var _namedCandidates: ["Noto Sans", "Ubuntu", "DejaVu Sans", "Liberation Sans"]
    readonly property var availableFonts: ["sans-serif", "serif", "monospace"]
    .concat(root._namedCandidates.filter(f => Qt.fontFamilies().includes(f)))
    .concat(ScreenshotSession.customFonts.map(f => f.family))

    // One-shot font registration. Deliberately NOT a single reused FontLoader
    // instance: QML skips a property assignment when the new value equals
    // the current one, so a shared loader's `source` would silently stay
    // put whenever the same file was picked twice in a row (including
    // delete -> re-add of the same font) — status never re-transitions to
    // Ready, so addCustomFont() never fires again. A fresh instance per
    // call always starts at Null and genuinely transitions, so it always
    // fires. Permanent registration lifetime is owned separately by
    // ScreenshotSession's _persistedFontLoaders Instantiator (keyed off
    // customFonts), so it's safe to destroy this one once we've read the
    // resolved family name from it.
    Component {
        id: fontLoaderComponent
        FontLoader {}
    }

    function loadFontFromPath(path) {
        const loader = fontLoaderComponent.createObject(root, { source: "file://" + path });
        if (!loader) {
            console.warn("TextOptionsBar: failed to create FontLoader for", path);
            return;
        }
        function handleStatus() {
            if (loader.status === FontLoader.Ready) {
                loader.statusChanged.disconnect(handleStatus);
                ScreenshotSession.addCustomFont(loader.name, path);
                ScreenshotSession.setAnnotationFontFamily(loader.name);
                loader.destroy();
            } else if (loader.status === FontLoader.Error) {
                loader.statusChanged.disconnect(handleStatus);
                console.warn("TextOptionsBar: failed to load font file", path);
                loader.destroy();
            }
        }
        loader.statusChanged.connect(handleStatus);
        handleStatus(); // covers the case where status is already Ready synchronously
    }

    ToolButton {
        label: "←"
        onClicked: ScreenshotSession.setTool("text")
    }

    Rectangle { width: 1; height: 28; color: Theme.borderMuted }

    Item {
        id: colorWheelRoot
        width: 28
        height: 28

        Image {
            anchors.fill: parent
            source: Qt.resolvedUrl("../../assets/hue_ring.png")
            smooth: true
            cache: true
        }

        Rectangle {
            anchors.centerIn: parent
            width: parent.width * 0.55
            height: width
            radius: width / 2
            color: ScreenshotSession.annotationColor

            Text {
                anchors.centerIn: parent
                text: "+"
                color: "white"
                font.pixelSize: Theme.fs(12)
                font.bold: true
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                colorPopup.visible = !colorPopup.visible;
                ScreenshotSession.colorPopupOpen = colorPopup.visible;
            }
        }
    }

    Item {
        id: colorPopupCloser
        parent: root.screenshotWindow ? root.screenshotWindow.contentItem : root
        anchors.fill: parent
        visible: colorPopup.visible
        z: 999

        MouseArea {
            anchors.fill: parent
            onClicked: {
                colorPopup.visible = false;
                ScreenshotSession.colorPopupOpen = false;
            }
        }
    }

    Rectangle {
        id: colorPopup
        parent: root.screenshotWindow ? root.screenshotWindow.contentItem : root
        visible: false
        z: 1000

        x: colorWheelRoot.mapToItem(parent, 0, 0).x - width / 2 + colorWheelRoot.width / 2
        y: colorWheelRoot.mapToItem(parent, 0, 0).y - height - 12

        width: 200
        height: 300
        radius: Theme.radiusMd
        color: Qt.rgba(Theme.popupBg.r, Theme.popupBg.g, Theme.popupBg.b, 0.75)
        border.width: 1
        border.color: Theme.borderMuted

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

        MouseArea {
            anchors.fill: parent
            onClicked: {}
        }

        Column {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            Item {
                id: hueRingArea
                width: 140
                height: 140
                anchors.horizontalCenter: parent.horizontalCenter

                Image {
                    anchors.fill: parent
                    source: Qt.resolvedUrl("../../assets/hue_ring.png")
                    smooth: true
                }

                Rectangle {
                    id: hueHandle
                    width: 12; height: 12
                    radius: 6
                    color: colorPopup.hueColor
                    border.width: 2
                    border.color: "white"
                    readonly property real ringRadius: hueRingArea.width / 2 - 8
                    x: hueRingArea.width / 2 + ringRadius * Math.cos(colorPopup.hue * Math.PI / 180) - width / 2
                    y: hueRingArea.height / 2 + ringRadius * Math.sin(colorPopup.hue * Math.PI / 180) - height / 2
                }

                MouseArea {
                    anchors.fill: parent
                    function updateHue(mx, my) {
                        const cx = hueRingArea.width / 2;
                        const cy = hueRingArea.height / 2;
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
                width: 140
                height: 100
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
                    id: svHandle
                    width: 12; height: 12
                    radius: 6
                    color: "transparent"
                    border.width: 2
                    border.color: "white"
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
                width: 140
                height: 20
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
                    id: alphaHandle
                    width: 6; height: alphaSlider.height + 4
                    radius: 3
                    color: "white"
                    border.width: 1
                    border.color: Theme.borderMuted
                    x: colorPopup.alpha * (alphaSlider.width - width)
                    y: -2
                }

                MouseArea {
                    anchors.fill: parent
                    function updateAlpha(mx) {
                        colorPopup.alpha = Math.max(0, Math.min(1, mx / alphaSlider.width));
                    }
                    onPressed: (mouse) => updateAlpha(mouse.x)
                    onPositionChanged: (mouse) => { if (pressed) updateAlpha(mouse.x); }
                    onReleased: colorPopup.commit()
                }
            }
        }
    }

    Rectangle { width: 1; height: 28; color: Theme.borderMuted }

    Flickable {
        id: fontScroll
        width: 260
        height: 36
        contentWidth: fontRow.width
        contentHeight: height
        clip: true
        interactive: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.HorizontalFlick

        Row {
            id: fontRow
            spacing: 8
            height: fontScroll.height

            Repeater {
                model: root.availableFonts
                delegate: ToolButton {
                    required property var modelData
                    label: modelData
                    checkable: true
                    checked: ScreenshotSession.annotationFontFamily === modelData
                    onClicked: ScreenshotSession.setAnnotationFontFamily(modelData)
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.NoButton
            onWheel: (wheel) => {
                const delta = wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : wheel.angleDelta.x;
                const maxX = Math.max(0, fontScroll.contentWidth - fontScroll.width);
                fontScroll.contentX = Math.max(0, Math.min(maxX, fontScroll.contentX - delta));
                wheel.accepted = true;
            }
        }
    }

    ToolButton {
        label: "+ Add Font"
        onClicked: fontBrowserWindow.open()
    }

    FontBrowserWindow {
        id: fontBrowserWindow
        screenshotWindow: root.screenshotWindow
        onFontChosen: (path) => root.loadFontFromPath(path)
    }
}
