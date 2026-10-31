import QtQuick
import QtQuick.Effects
import Qt5Compat.GraphicalEffects
import Quickshell.Wayland

Item {
    id: root
    property var screen
    // Settings > Lock screen > Background: an image used instead of the blurred screen ("" = blur)
    property string wallpaperPath: ""

    // True once the live compositor feed has actually delivered a frame
    readonly property bool liveReady: capture.hasContent

    // Scripted jitter offset -- driven by a fixed animation curve
    property real shakeX: 0

    // Always-present solid base. Nothing renders on top of this until
    // the async Image below has actually decoded, so there is never a
    // gap where the surface's own default background can show through.
    Rectangle {
        anchors.fill: parent
        color: "black"
    }

    // Static screenshot grabbed BEFORE the lock surface existed (see
    // LockScreen.qml's lockRequested()). This is on screen the instant
    // the surface appears, so there's no black flash while the live
    // Wayland capture spins up.
    Image {
        id: staticShot
        anchors.fill: parent
        source: root.screen ? "file:///tmp/quickshell-lockshot-" + root.screen.name + ".png" : ""
        cache: false
        // Synchronous: the lock surface must show the pre-lock screenshot on
        // its very first frame. Async decoding left only the black/white
        // base visible on the first lock of a session.
        asynchronous: false
        fillMode: Image.PreserveAspectCrop
    }

    MultiEffect {
        id: staticBlur
        anchors.fill: staticShot
        source: staticShot
        autoPaddingEnabled: false

        blurEnabled: true
        blur: 1.0
        blurMax: 96
        blurMultiplier: 1.6

        saturation: -0.08
        brightness: -0.06
        contrast: 0.05

        // Stays fully opaque underneath: the live capture fades in on top of
        // it. Fading both at once let the black base show through mid-crossfade
        // (a darker lock background on the first lock).
        opacity: 1
    }

    // Live capture, running from the moment the surface exists. Once it
    // has its first frame, it fades in over the static shot and freezes
    // (matches prior behavior of stopping after first frame).
    ScreencopyView {
        id: capture
        anchors.fill: parent
        captureSource: root.screen
        live: true
        onHasContentChanged: if (hasContent) live = false
    }

    MultiEffect {
        id: blurred
        anchors.fill: capture
        source: capture
        autoPaddingEnabled: false

        blurEnabled: true
        blur: 1.0
        blurMax: 96
        blurMultiplier: 1.6

        saturation: -0.08
        brightness: -0.06
        contrast: 0.05

        opacity: root.liveReady ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

        transform: Translate { x: root.shakeX }

        layer.enabled: root.shakeX !== 0
        layer.effect: DirectionalBlur {
            angle: 0
            length: Math.min(10, Math.abs(root.shakeX) * 3)
            samples: 16
        }
    }

    // Chosen wallpaper: covers the blurred screen once it has loaded. If the file is missing
    // or broken it never becomes Ready, so the normal blurred lock screen stays.
    Image {
        anchors.fill: parent
        visible: root.wallpaperPath !== "" && status === Image.Ready
        source: root.wallpaperPath !== "" ? "file://" + root.wallpaperPath : ""
        asynchronous: false
        cache: false
        fillMode: Image.PreserveAspectCrop
        sourceSize.width: root.width > 0 ? root.width : 1920
    }

    // Entrance jitter animation -- can start immediately now since the
    // static shot is already on screen (no more waiting on "ready").
    SequentialAnimation {
        running: true
        loops: 1

        PropertyAction { target: root; property: "shakeX"; value: 3 }
        PauseAnimation { duration: 35 }
        PropertyAction { target: root; property: "shakeX"; value: -3 }
        PauseAnimation { duration: 35 }
        PropertyAction { target: root; property: "shakeX"; value: 2 }
        PauseAnimation { duration: 30 }
        PropertyAction { target: root; property: "shakeX"; value: -2 }
        PauseAnimation { duration: 30 }
        PropertyAction { target: root; property: "shakeX"; value: 0 }
    }
}
