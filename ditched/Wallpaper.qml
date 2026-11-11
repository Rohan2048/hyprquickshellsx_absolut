import QtQuick
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
    exclusiveZone: 0
    color: "transparent"

    anchors { top: true; bottom: true; left: true; right: true }
    visible: true

    property string currentPath: ""
    property real transitionProgress: 1
    property bool transitioning: false

    Component {
        id: imageSlot
        Image {
            anchors.fill: parent
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: false
            property string imgPath: ""
            source: imgPath.length > 0 ? ("file://" + imgPath) : ""
            sourceSize.width: wallpaperWindow.width
            sourceSize.height: wallpaperWindow.height
        }
    }

    function reloadImageSlot(loader, path) {
        loader.active = false
        loader.imgPath = path
        loader.active = true
    }

    function unload() {
        loaderFront.active = false
        loaderBack.active = false
    }

    Timer {
        id: backWarmTimer
        interval: 800
        repeat: false
        property string pendingPath: ""
        onTriggered: {
            if (pendingPath.length > 0)
                wallpaperWindow.reloadImageSlot(loaderBack, pendingPath)
        }
    }

    Item {
        id: modeRoot
        anchors.fill: parent
        opacity: 1 - WallpaperState.progress
        // Lightweight lively feel: subtle scale as it becomes visible
        scale: 0.98 + (1.0 - WallpaperState.progress) * 0.02
        transformOrigin: Item.Center

        Loader {
            id: loaderBack
            anchors.fill: parent
            asynchronous: true
            sourceComponent: imageSlot
            property string imgPath: ""
            active: false
            opacity: 1 - wallpaperWindow.transitionProgress
            onItemChanged: if (item) item.imgPath = imgPath
        }

        Loader {
            id: loaderFront
            anchors.fill: parent
            asynchronous: true
            sourceComponent: imageSlot
            property string imgPath: ""
            active: false
            opacity: wallpaperWindow.transitionProgress

            property bool waitingForLoad: false

            onItemChanged: {
                if (item) {
                    item.imgPath = imgPath
                    if (item.status === Image.Ready)
                        WallpaperState.notifyContentReady(false, imgPath)
                }
            }

            Connections {
                target: loaderFront.item
                enabled: loaderFront.item !== null
                function onStatusChanged() {
                    if (loaderFront.item.status !== Image.Ready)
                        return

                        if (loaderFront.waitingForLoad && wallpaperWindow.transitionProgress === 0) {
                            loaderFront.waitingForLoad = false
                            crossfadeAnim.restart()
                        }

                        WallpaperState.notifyContentReady(false, loaderFront.item.imgPath)
                }
            }
        }
    }

    NumberAnimation {
        id: crossfadeAnim
        target: wallpaperWindow
        property: "transitionProgress"
        from: 0; to: 1
        duration: Animations.wallpaperCrossfadeDuration
        easing.type: Animations.wallpaperCrossfadeEasing
        running: false
        onStarted: wallpaperWindow.transitioning = true
        onStopped: {
            wallpaperWindow.transitioning = false
            wallpaperWindow.reloadImageSlot(loaderBack, wallpaperWindow.currentPath)
        }
    }

    function setWallpaper(path, instant) {
        currentPath = path
        if (instant) {
            reloadImageSlot(loaderFront, path)
            transitionProgress = 1
            backWarmTimer.pendingPath = path
            backWarmTimer.restart()
            return
        }
        transitionProgress = 0
        loaderFront.waitingForLoad = true
        reloadImageSlot(loaderFront, path)
    }

    function syncFromState(path, isVideo, modeChanged, forceInstant) {
        if (path.length === 0)
            return
            if (path === currentPath && !forceInstant && loaderFront.active)
                return
                const instant = forceInstant || isVideo || modeChanged
                setWallpaper(path, instant)
    }

    Connections {
        target: WallpaperState
        function onWallpaperUpdated(imagePath, videoPath, isVideo, imageChanged, videoChanged, modeChanged, instant) {
            if (imageChanged || instant) {
                wallpaperWindow.syncFromState(imagePath, isVideo, modeChanged, instant)
            } else if (modeChanged && !isVideo) {
                if (wallpaperWindow.currentPath === imagePath && imagePath.length > 0
                    && loaderFront.active && loaderFront.item) {
                    WallpaperState.notifyContentReady(false, imagePath)
                    } else {
                        wallpaperWindow.syncFromState(imagePath, isVideo, modeChanged, true)
                    }
            }
        }
    }

    Connections {
        target: WallpaperState
        function onTransitioningChanged() {
            if (!WallpaperState.transitioning && WallpaperState.isVideo)
                wallpaperWindow.unload()
        }
    }

    Component.onCompleted: {
        if (WallpaperState.initialized) {
            Qt.callLater(function() {
                if (!WallpaperState.isVideo)
                    wallpaperWindow.syncFromState(WallpaperState.imagePath, false, false, true)
            })
        }
    }
}
