pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import "../Services"
import "../SBS"
import "Toolbar"
import "Canvas"
import "Tools"

PanelWindow {
    id: window

    readonly property int barClearance: 96 // reserved band top/bottom for toolbars

    property bool dialogOpen: false

    Process {
        id: hueRingGen
        command: ["bash", "-c",
        "test -f '" + Quickshell.env("HOME") + "/.config/quickshell/assets/hue_ring.png' || python3 '" +
        Quickshell.env("HOME") + "/.config/quickshell/scripts/gen_hue_ring.py'"
        ]
    }

    // This window is now created on demand (see shell.qml) and destroyed
    // again when the editor closes, so the "became visible" work has to run
    // from Component.onCompleted too: onVisibleChanged does not reliably
    // fire for a window that is already visible when it is created.
    property bool _shown: false
    function _onShown() {
        if (window._shown) return;
        window._shown = true;
        focusScope.forceActiveFocus();
        imageContainer.letterboxMargin = 0;
        letterboxTimer.restart();
        directScanoutOff.running = true;
        rofiKill.running = true;
    }

    Component.onCompleted: {
        hueRingGen.running = true;
        if (window.visible) window._onShown();
    }

    // ---- input-path fixes for fullscreen games / rofi ----
    Process {
        id: directScanoutOff
        command: ["hyprctl", "keyword", "render:direct_scanout", "0"]
    }
    Process {
        id: directScanoutOn
        command: ["hyprctl", "keyword", "render:direct_scanout", "1"]
    }
    Process {
        id: rofiKill
        command: ["pkill", "-x", "rofi"]
    }

    property var targetScreen: {
        const name = ScreenshotSession.screenName;
        for (const s of Quickshell.screens) {
            if (s.name === name) return s;
        }
        return null;
    }

    screen: targetScreen
    visible: ScreenshotSession.active && targetScreen !== null
    color: SBSState.active ? "black" : Qt.rgba(0,0,0,0.65)

    WlrLayershell.namespace: SBSState.active ? "quickshell:screenshot-noblur" : "quickshell:screenshot"
    WlrLayershell.layer: WlrLayer.Overlay
    // Exclusive, not OnDemand: OnDemand never proactively grabs focus, so a
    // fullscreen game's pointer-lock (which only releases when its surface
    // loses keyboard focus) never got released -- leaving clicks/Enter/the
    // cursor stuck on the game underneath until you alt-tabbed away.
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    WlrLayershell.exclusionMode: ExclusionMode.Ignore

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    Item {
        id: fullMaskArea
        anchors.fill: parent
    }

    Item {
        id: toastCutoutArea
        width: Notifications.activeToasts.count > 0 ? 280 : 0
        height: Notifications.activeToasts.count > 0 ? 320 : 0
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
    }

    mask: Region {
        item: fullMaskArea
        Region {
            item: toastCutoutArea
            intersection: Intersection.Subtract
        }
        Region {
            item: topToolbar
            intersection: Intersection.Add
        }
    }

    function requestClose() {
        if (!ScreenshotSession.active) return;
        ScreenshotSession.annotations.clear();
        ScreenshotSession.clearAnnotationSelection();
        imageContainer.letterboxMargin = 0;
        closeTimer.restart();
    }

    Timer {
        id: closeTimer
        interval: 320
        onTriggered: ScreenshotSession.cancel()
    }

    Item {
        id: focusScope
        anchors.fill: parent
        focus: true

        Keys.onPressed: (event) => {
            if (event.key === Qt.Key_Escape) {
                window.requestClose();
                event.accepted = true;
            } else if ((event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace)
                && ScreenshotSession.selectedAnnotationId !== -1) {
                ScreenshotSession.annotations.remove(ScreenshotSession.selectedAnnotationId);
            ScreenshotSession.clearAnnotationSelection();
            event.accepted = true;
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    const focusItem = window.activeFocusItem;
                    const isTextEditing = focusItem && (focusItem instanceof TextInput || focusItem instanceof TextEdit);
                    if (!isTextEditing) {
                        topToolbar.doSave();
                        event.accepted = true;
                    }
                }
        }

        Item {
            id: imageContainer
            property real letterboxMargin: 0

            anchors {
                top: parent.top
                bottom: parent.bottom
                left: parent.left
                right: parent.right
                topMargin: imageContainer.letterboxMargin
                bottomMargin: imageContainer.letterboxMargin
            }

            Behavior on letterboxMargin {
                NumberAnimation { duration: 320; easing.type: Easing.OutCubic }
            }

            Image {
                id: baseImage
                anchors.fill: parent
                source: ScreenshotSession.imagePath ? "file://" + ScreenshotSession.imagePath : ""
                fillMode: Image.PreserveAspectFit
                cache: false
                asynchronous: true
                onPaintedWidthChanged: window._updateScale()
                onStatusChanged: if (status === Image.Ready) {
                    window._updateScale();
                    ScreenshotSession.applyPendingRemap();
                }
            }

            Item {
                id: imageBounds
                x: (imageContainer.width - baseImage.paintedWidth) / 2
                y: (imageContainer.height - baseImage.paintedHeight) / 2
                width: baseImage.paintedWidth
                height: baseImage.paintedHeight

                Image {
                    id: compositeBackground
                    anchors.fill: parent
                    source: baseImage.source
                    fillMode: Image.Stretch
                    cache: false
                    smooth: true
                    visible: false
                }

                SelectionOverlay {}

                ShapeLayer { id: shapeLayer; annotationStack: annotationStack }
                TextLayer { id: textLayer; annotationStack: annotationStack }

                FreehandLayer {
                    id: freehandLayer
                    anchors.fill: parent
                    annotationStack: annotationStack
                }
                DoodleTool {
                    anchors.fill: parent
                    annotationModel: ScreenshotSession.annotations
                    strokeColor: ScreenshotSession.annotationColor
                    strokeWidth: ScreenshotSession.annotationStrokeWidth
                    highlighter: ScreenshotSession.annotationHighlighter
                    dotted: ScreenshotSession.annotationDotted
                    visible: ScreenshotSession.currentTool === "doodle"
                    enabled: visible
                }
                EraserTool {
                    anchors.fill: parent
                    visible: ScreenshotSession.currentTool === "eraser"
                    enabled: visible
                }
                BlurLayer {
                    id: blurLayer
                    anchors.fill: parent
                    annotationModel: ScreenshotSession.annotations
                    annotationStack: annotationStack
                }
                BlurTool {
                    anchors.fill: parent
                    annotationModel: ScreenshotSession.annotations
                    visible: ScreenshotSession.currentTool === "blur"
                    enabled: visible
                }

                AnnotationStack {
                    id: annotationStack
                    anchors.fill: parent
                    shapeLayer: shapeLayer
                    blurLayer: blurLayer
                    sourceItem: baseImage
                    sourceOffset: Qt.point(imageBounds.x, imageBounds.y)
                }
            }
        }

        TopToolbar { id: topToolbar; screenshotWindow: window }
        BottomToolbar { screenshotWindow: window }
    }

    function _updateScale() {
        if (baseImage.sourceSize.width > 0)
            ScreenshotSession.displayScale = baseImage.paintedWidth / baseImage.sourceSize.width;
    }

    function restoreFocus() {
        focusScope.forceActiveFocus();
    }

    function captureComposite(callback) {
        compositeBackground.visible = true;
        imageBounds.grabToImage(function(result) {
            compositeBackground.visible = false;
            const tmp = "/tmp/quickshot-composite-" + Date.now() + ".png";
            if (result.saveToFile(tmp))
                callback(tmp);
            else
                callback(null);
        });
    }

    onVisibleChanged: {
        if (visible) {
            window._onShown();
        } else {
            window._shown = false;
            directScanoutOn.running = true;
        }
    }

    Timer {
        id: letterboxTimer
        interval: 16
        onTriggered: imageContainer.letterboxMargin = window.barClearance
    }
}
