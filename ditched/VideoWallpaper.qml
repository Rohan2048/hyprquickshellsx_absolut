import QtQuick
import QtMultimedia
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../Theme"
import "../Services"

PanelWindow {
    id: videoWallpaperWindow

    required property var modelData
    screen: modelData

    WlrLayershell.namespace: "quickshell:videowallpaper"
    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusiveZone: 0
    color: "transparent"

    anchors { top: true; bottom: true; left: true; right: true }
    visible: true

    property string currentPath: ""
    property real transitionProgress: 1
    property bool transitioning: false
    property bool shouldPlay: false

    Component {
        id: playerSlot
        Item {
            anchors.fill: parent
            property string videoPath: ""
            property alias player: mp
            VideoOutput {
                id: vo
                anchors.fill: parent
                fillMode: VideoOutput.PreserveAspectCrop
            }
            MediaPlayer {
                id: mp
                source: parent.videoPath.length > 0 ? ("file://" + parent.videoPath) : ""
                videoOutput: vo
                loops: MediaPlayer.Infinite
                audioOutput: AudioOutput { muted: true }
                autoPlay: false
            }
        }
    }

    function reloadSlot(loader, path) {
        loader.active = false
        loader.videoPath = path
        loader.active = true
    }

    function ensurePlaying(loader) {
        if (loader.item && videoWallpaperWindow.shouldPlay)
            loader.item.player.play()
    }

    function pausePlayback() {
        shouldPlay = false
        playRetryTimer.stop()
        backWarmTimer.stop()
        if (loaderBack.item) {
            loaderBack.item.player.stop()
            loaderBack.item.videoPath = ""
        }
        if (loaderFront.item) {
            loaderFront.item.player.stop()
            loaderFront.item.videoPath = ""
        }
    }

    function unload() {
        pausePlayback()
        loaderFront.active = false
        loaderBack.active = false
    }

    function resumePlayback() {
        shouldPlay = true
        ensurePlaying(loaderFront)
        if (!loaderFront.item || loaderFront.item.player.playbackState !== MediaPlayer.PlayingState)
            playRetryTimer.restart()
    }

    Timer {
        id: playRetryTimer
        interval: 200
        repeat: false
        onTriggered: videoWallpaperWindow.ensurePlaying(loaderFront)
    }

    Timer {
        id: backWarmTimer
        interval: 800
        repeat: false
        property string pendingPath: ""
        onTriggered: {
            if (pendingPath.length > 0 && videoWallpaperWindow.shouldPlay)
                videoWallpaperWindow.reloadSlot(loaderBack, pendingPath)
        }
    }

    Item {
        id: modeRoot
        anchors.fill: parent
        opacity: WallpaperState.progress
        // Lightweight lively feel: subtle scale as it becomes visible
        scale: 0.98 + WallpaperState.progress * 0.02
        transformOrigin: Item.Center

        Loader {
            id: loaderBack
            anchors.fill: parent
            asynchronous: true
            sourceComponent: playerSlot
            property string videoPath: ""
            active: false
            opacity: 1 - videoWallpaperWindow.transitionProgress
            onItemChanged: if (item) item.videoPath = videoPath
        }

        Loader {
            id: loaderFront
            anchors.fill: parent
            asynchronous: true
            sourceComponent: playerSlot
            property string videoPath: ""
            active: false
            opacity: videoWallpaperWindow.transitionProgress

            property bool waitingForLoad: false

            onItemChanged: {
                if (item) {
                    item.videoPath = videoPath
                    videoWallpaperWindow.ensurePlaying(loaderFront)
                    const st = item.player.mediaStatus
                    if (st === MediaPlayer.LoadedMedia || st === MediaPlayer.BufferedMedia)
                        WallpaperState.notifyContentReady(true, videoPath)
                }
            }

            onLoaded: {
                if (waitingForLoad && videoWallpaperWindow.transitionProgress === 0) {
                    waitingForLoad = false
                    crossfadeAnim.restart()
                }
            }

            Connections {
                target: loaderFront.item ? loaderFront.item.player : null
                enabled: loaderFront.item !== null
                function onMediaStatusChanged() {
                    const st = loaderFront.item.player.mediaStatus
                    if (st === MediaPlayer.LoadedMedia || st === MediaPlayer.BufferedMedia)
                        WallpaperState.notifyContentReady(true, loaderFront.videoPath)
                }
            }
        }
    }

    NumberAnimation {
        id: crossfadeAnim
        target: videoWallpaperWindow
        property: "transitionProgress"
        from: 0; to: 1
        duration: Animations.wallpaperCrossfadeDuration
        easing.type: Animations.wallpaperCrossfadeEasing
        running: false
        onStarted: {
            videoWallpaperWindow.transitioning = true
            videoWallpaperWindow.ensurePlaying(loaderBack)
        }
        onStopped: {
            videoWallpaperWindow.transitioning = false
            videoWallpaperWindow.reloadSlot(loaderBack, videoWallpaperWindow.currentPath)
        }
    }

    function setWallpaper(path, instant) {
        currentPath = path
        if (instant) {
            reloadSlot(loaderFront, path)
            transitionProgress = 1
            backWarmTimer.pendingPath = path
            backWarmTimer.restart()
            return
        }
        transitionProgress = 0
        loaderFront.waitingForLoad = true
        reloadSlot(loaderFront, path)
    }

    function syncFromState(path, isVideo, modeChanged, forceInstant) {
        if (path.length === 0)
            return
            if (path === currentPath && !forceInstant && loaderFront.active)
                return
                const instant = forceInstant || !isVideo || modeChanged
                setWallpaper(path, instant)
    }

    Connections {
        target: WallpaperState
        function onWallpaperUpdated(imagePath, videoPath, isVideo, imageChanged, videoChanged, modeChanged, instant) {
            if (videoChanged || instant) {
                videoWallpaperWindow.syncFromState(videoPath, isVideo, modeChanged, instant)
            } else if (modeChanged && isVideo) {
                if (videoWallpaperWindow.currentPath === videoPath && videoPath.length > 0
                    && loaderFront.active && loaderFront.item) {
                    WallpaperState.notifyContentReady(true, videoPath)
                    } else {
                        videoWallpaperWindow.syncFromState(videoPath, isVideo, modeChanged, true)
                    }
            }

            if (instant) {
                if (isVideo)
                    videoWallpaperWindow.resumePlayback()
                    else
                        videoWallpaperWindow.pausePlayback()
            } else if (modeChanged && isVideo) {
                videoWallpaperWindow.resumePlayback()
            }
        }
    }

    Connections {
        target: WallpaperState
        function onTransitioningChanged() {
            if (!WallpaperState.transitioning && !WallpaperState.isVideo)
                videoWallpaperWindow.unload()
        }
    }

    Component.onCompleted: {
        if (WallpaperState.initialized) {
            Qt.callLater(function() {
                if (WallpaperState.isVideo) {
                    videoWallpaperWindow.syncFromState(WallpaperState.videoPath, true, false, true)
                    videoWallpaperWindow.resumePlayback()
                }
            })
        }
    }
}
