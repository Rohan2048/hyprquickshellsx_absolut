import QtQuick
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../Theme"
import "../Services"

PanelWindow {
    id: wallpaperWindow

    required property var modelData
    screen: modelData

    WlrLayershell.namespace: "quickshell:wallpaper"
    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    // -1: cover the whole output even when bars reserve space (the wallpaper must not shrink / stretch)
    exclusiveZone: -1
    color: "black"

    anchors { top: true; bottom: true; left: true; right: true }
    visible: true

    property string currentPath: ""
    property real transitionProgress: 1
    property bool transitioning: false

    // --- Minimal & Optimized Parallax ---
    // Reduced to 4 for a very tight, subtle movement
    readonly property int parallaxStrength: 4
    readonly property int parallaxOverscan: 5

    property int targetX: 0
    property int targetY: 0

    Component {
        id: blurComponent
        DirectionalBlur {
            angle: Animations.wallpaperBlurAngle
            length: Animations.blurEnvelope(wallpaperWindow.transitionProgress) * Animations.wallpaperBlurLength
            samples: Math.min(Animations.wallpaperBlurSamples, 16)
            transparentBorder: false
        }
    }

    component CrossfadeLayer: Loader {
        anchors.fill: parent
        asynchronous: true
        sourceComponent: imageSlot
        property string imgPath: ""
        active: false
        visible: opacity > 0.01

        layer.enabled: wallpaperWindow.transitioning
        layer.effect: wallpaperWindow.transitioning ? blurComponent : null

        onItemChanged: if (item) item.imgPath = imgPath
    }

    Component {
        id: imageSlot
        Image {
            anchors.fill: parent
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true
            property string imgPath: ""
            source: imgPath.length > 0 ? ("file://" + imgPath) : ""

            sourceSize.width: (wallpaperWindow.width + wallpaperWindow.parallaxOverscan * 2) * wallpaperWindow.screen.devicePixelRatio
            sourceSize.height: (wallpaperWindow.height + wallpaperWindow.parallaxOverscan * 2) * wallpaperWindow.screen.devicePixelRatio
        }
    }

    Item {
        id: parallaxContainer
        width: wallpaperWindow.width + (wallpaperWindow.parallaxOverscan * 2)
        height: wallpaperWindow.height + (wallpaperWindow.parallaxOverscan * 2)

        x: -wallpaperWindow.parallaxOverscan + targetX
        y: -wallpaperWindow.parallaxOverscan + targetY

        Behavior on x {
            NumberAnimation { duration: 250; easing.type: Easing.OutQuad }
        }
        Behavior on y {
            NumberAnimation { duration: 250; easing.type: Easing.OutQuad }
        }

        CrossfadeLayer {
            id: loaderBack
            opacity: 1 - wallpaperWindow.transitionProgress
        }

        CrossfadeLayer {
            id: loaderFront
            opacity: wallpaperWindow.transitionProgress
            property bool waitingForLoad: false

            Connections {
                target: loaderFront.item
                enabled: loaderFront.item !== null
                function onStatusChanged() {
                    if (loaderFront.item.status !== Image.Ready) return
                        if (loaderFront.waitingForLoad && wallpaperWindow.transitionProgress === 0) {
                            loaderFront.waitingForLoad = false
                            crossfadeAnim.restart()
                        }
                }
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton

        onPositionChanged: {
            var nx = (mouseX / width - 0.5) * 2
            var ny = (mouseY / height - 0.5) * 2

            // Pixel snapping keeps the GPU from re-filtering the texture
            var tx = -Math.round(nx * wallpaperWindow.parallaxStrength)
            var ty = -Math.round(ny * wallpaperWindow.parallaxStrength)

            if (tx !== wallpaperWindow.targetX) wallpaperWindow.targetX = tx
                if (ty !== wallpaperWindow.targetY) wallpaperWindow.targetY = ty
        }
    }

    NumberAnimation {
        id: crossfadeAnim
        target: wallpaperWindow
        property: "transitionProgress"
        from: 0; to: 1
        duration: Animations.wallpaperCrossfadeDuration
        easing.type: Animations.wallpaperCrossfadeEasing
        onStarted: wallpaperWindow.transitioning = true
        onStopped: {
            wallpaperWindow.transitioning = false
            loaderBack.active = false
            wallpaperWindow.reloadImageSlot(loaderBack, wallpaperWindow.currentPath)
        }
    }

    function reloadImageSlot(loader, path) {
        loader.active = false
        loader.imgPath = path
        loader.active = true
    }

    function setWallpaper(path) {
        if (!path) return
            currentPath = path
            transitionProgress = 0
            loaderFront.waitingForLoad = true
            reloadImageSlot(loaderFront, path)
    }

    Connections {
        target: WallpaperState
        function onWallpaperUpdated(imagePath, imageChanged) {
            if (imagePath.length === 0 || imagePath === currentPath) return
                setWallpaper(imagePath)
        }
    }

    Component.onCompleted: {
        if (WallpaperState.initialized) {
            Qt.callLater(() => setWallpaper(WallpaperState.imagePath))
        }
    }
}
