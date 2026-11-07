import QtQuick
import Quickshell
import Quickshell.Wayland
import Qt5Compat.GraphicalEffects
import "../Theme"
import "../Services"
import "../Widgets"

PanelWindow {
    id: toastWindow
    visible: Notifications.activeToasts.count > 0
    implicitWidth: 260
    color: "transparent"
    exclusiveZone: 0

    property bool expanded: false

    // 🚀 FIX: Track when expand/collapse is actively happening so we can
    // re-enable smooth animations for all cards, preventing the "broken snap" transition.
    property bool isTransitioning: false
    Timer {
        id: transitionTimer
        interval: toastWindow.localStackDuration + 50 // Slightly longer than the animation
        repeat: false
        onTriggered: toastWindow.isTransitioning = false
    }
    Connections {
        target: toastWindow
        function onExpandedChanged() {
            toastWindow.isTransitioning = true
            transitionTimer.restart()
        }
    }

    readonly property int localStackDuration: Animations.scaleDuration(160)
    readonly property int localBlurPulseDuration: Animations.scaleDuration(260)
    readonly property int localBlurRetargetDuration: Animations.scaleDuration(90)
    readonly property int localMaxRenderedDepth: 2
    readonly property int localShadowMaxDepth: 1
    readonly property int localBodyMaxLines: 3

    function blurSamplesForCount(count) {
        if (count <= 1) return 8
            if (count === 2) return 6
                return 4
    }
    readonly property int currentBlurSamples: blurSamplesForCount(Notifications.activeToasts.count)

    function shadowSamplesForCount(count) {
        if (count <= 1) return 6
            if (count === 2) return 5
                return 4
    }
    readonly property int currentShadowSamples: shadowSamplesForCount(Notifications.activeToasts.count)

    readonly property real localScrimBase: 0.35
    readonly property real localScrimPerDepth: 0.16
    readonly property real localScrimMax: 0.88

    readonly property real localCardOpacity: 0.72
    readonly property int dragDirectionSign: 1

    readonly property real localDragBlurMaxLen: 24
    readonly property real localDragBlurVelocityFactor: 0.35
    readonly property real localDragBlurDeadzone: 1.5
    readonly property int localDragBlurSampleStride: 3
    readonly property real localDragStretchMax: 0.12
    readonly property real localDragStretchOpacityDip: 0.12

    property real nextEntranceSlot: 0
    readonly property int localEntranceStaggerMs: Animations.scaleDuration(40)

    property real nextExitSlot: 0
    readonly property int localExitStaggerMs: Animations.scaleDuration(40)

    implicitHeight: 900

    WlrLayershell.namespace: "quickshell:toast"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    anchors { top: true; left: true; right: true }
    margins { top: 5 }

    mask: Region {
        item: inputMaskArea
    }

    Item {
        id: blurWarmup
        width: 1; height: 1; opacity: 0.02; z: -1000
        // Was permanently "layer.enabled: true" — held an allocated FBO and
        // re-evaluated every frame for the shell's entire lifetime, for content
        // that never changes past the first frame. Only needs to run once to
        // force the DirectionalBlur shader to compile/warm up; after that the
        // layer is pure waste. Invisible either way (opacity 0.02, z -1000),
        // so this is zero visual change.
        property bool warmupActive: true
        layer.enabled: warmupActive
        layer.effect: DirectionalBlur { angle: 0; length: 0; samples: 4 }

        Timer {
            interval: 300
            running: true
            repeat: false
            onTriggered: blurWarmup.warmupActive = false
        }
    }

    Item {
        id: contentClip
        width: parent.width
        clip: true

        readonly property real targetHeight: toastWindow.expanded
        ? Math.min(stackRoot.totalExpandedHeight() + 20, 900)
        : stackRoot.frontHeight() + 60

        height: targetHeight

        Behavior on height {
            NumberAnimation {
                duration: toastWindow.localStackDuration
                easing.type: toastWindow.expanded ? Animations.pageSlideEasingOut : Animations.pageSlideEasingIn
            }
        }

        Item {
            id: inputMaskArea
            anchors.horizontalCenter: parent.horizontalCenter
            width: 220
            height: contentClip.targetHeight
        }

        Item {
            id: stackRoot
            width: parent.width
            height: parent.height

            readonly property real fallbackCardHeight: 70

            function frontHeight() {
                const item = toastRepeater.itemAt(Notifications.activeToasts.count - 1)
                return item ? item.height : fallbackCardHeight
            }

            function expandedY(depth) {
                let y = 0
                for (let d = 0; d < depth; d++) {
                    const idx = (Notifications.activeToasts.count - 1) - d
                    const item = toastRepeater.itemAt(idx)
                    y += (item ? item.height : fallbackCardHeight) + 10
                }
                return y
            }

            function totalExpandedHeight() {
                return stackRoot.expandedY(Notifications.activeToasts.count)
            }

            property var expandedYCache: []
            function rebuildExpandedYCache() {
                let arr = []
                let y = 0
                for (let d = 0; d < toastRepeater.count; d++) {
                    const idx = (Notifications.activeToasts.count - 1) - d
                    const item = toastRepeater.itemAt(idx)
                    arr.push(y)
                    y += (item ? item.height : fallbackCardHeight) + 10
                }
                expandedYCache = arr
            }
            function cachedExpandedY(depth) {
                return (depth >= 0 && depth < expandedYCache.length) ? expandedYCache[depth] : expandedY(depth)
            }

            property bool cacheDirty: false
            Timer {
                id: cacheRebuildTimer
                interval: 16
                repeat: false
                onTriggered: {
                    stackRoot.rebuildExpandedYCache()
                    stackRoot.cacheDirty = false
                }
            }

            Connections {
                target: Notifications.activeToasts

                function onCountChanged() {
                    if (!stackRoot.cacheDirty) {
                        stackRoot.cacheDirty = true
                        cacheRebuildTimer.restart()
                    }
                }
            }

            Connections {
                target: toastWindow

                function onExpandedChanged() {
                    if (!stackRoot.cacheDirty) {
                        stackRoot.cacheDirty = true
                        cacheRebuildTimer.restart()
                    }
                }
            }

            Repeater {
                id: toastRepeater
                model: Notifications.activeToasts

                delegate: Item {
                    id: toastCard
                    required property int index
                    required property string hash
                    required property string title
                    required property string body
                    required property int urgency
                    required property var actions
                    required property int timeout
                    required property int mergeCount
                    required property int restartToken

                    readonly property bool withinDrawDistance: rawDepth < toastWindow.localMaxRenderedDepth
                    readonly property int rawDepth: (Notifications.activeToasts.count - 1) - index
                    readonly property int depth: Math.min(rawDepth, 5)
                    readonly property bool isFrontCard: rawDepth === 0

                    readonly property real baseScale: toastWindow.expanded ? 1 : (1 - depth * 0.045)
                    readonly property real baseOpacity: toastWindow.expanded ? 1 : (depth === 0 ? 1 : Math.max(0.22, 1 - depth * 0.22))

                    readonly property real scrimOpacity: (rawDepth === 0 || toastWindow.expanded)
                    ? 0
                    : Math.min(toastWindow.localScrimBase + (rawDepth - 1) * toastWindow.localScrimPerDepth, toastWindow.localScrimMax)

                    property bool entering: true
                    readonly property bool cardIsMoving: isFrontCard && (cardMouse.drag.active || flingAnim.running || popSpring.running || toastCard.entering)

                    property real dragBlurLen: 0
                    property real dragLastX: 0

                    FrameAnimation {
                        id: dragVelocityTracker
                        running: toastCard.cardIsMoving
                        property real elapsedAccum: 0
                        property int frameCount: 0
                        onRunningChanged: {
                            if (running) {
                                dragLastX = dragTarget.x
                                elapsedAccum = 0; frameCount = 0
                            } else {
                                toastCard.dragBlurLen = 0
                            }
                        }
                        onTriggered: {
                            elapsedAccum += frameTime
                            if (++frameCount < toastWindow.localDragBlurSampleStride) return

                                const curX = dragTarget.x
                                if (elapsedAccum > 0.0005) {
                                    const velocity = Math.abs(curX - dragLastX) / elapsedAccum / 1000
                                    const newLen = Math.min(toastWindow.localDragBlurMaxLen, velocity * toastWindow.localDragBlurVelocityFactor * 40)
                                    if (Math.abs(newLen - toastCard.dragBlurLen) > toastWindow.localDragBlurDeadzone) {
                                        toastCard.dragBlurLen = newLen
                                    }
                                }
                                dragLastX = curX
                                elapsedAccum = 0; frameCount = 0
                        }
                    }

                    Behavior on dragBlurLen {
                        NumberAnimation { duration: Animations.scaleDuration(100); easing.type: Easing.OutQuad }
                    }

                    readonly property real dragBlurStrength: Math.min(dragBlurLen / toastWindow.localDragBlurMaxLen, 1)
                    readonly property real vertBlurStrength: Animations.blurEnvelope(transitionT)
                    readonly property bool blurIsVertical: vertBlurStrength >= dragBlurStrength
                    readonly property real blurStrength: Math.max(vertBlurStrength, dragBlurStrength)

                    readonly property real activeBlurLength: blurIsVertical
                    ? Animations.toastBlurToggleLength * vertBlurStrength
                    : 0

                    readonly property real currentBlurAngle: blurStrength > 0.02
                    ? (blurIsVertical ? Animations.slideBlurVerticalAngle : Animations.slideBlurHorizontalAngle)
                    : Animations.slideBlurVerticalAngle

                    readonly property real currentBlurLength: blurStrength > 0.02 ? activeBlurLength : 0
                    readonly property bool wantsBlurLayer: withinDrawDistance

                    width: 220
                    height: cardBg.implicitHeight
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: toastWindow.expanded ? stackRoot.cachedExpandedY(rawDepth) : depth * 8
                    z: 1000 - rawDepth

                    property real transitionT: 0
                    onYChanged: {
                        if (toastCard.isFrontCard || toastWindow.isTransitioning) transitionAnim.restart()
                    }
                    Connections {
                        target: toastWindow
                        function onExpandedChanged() {
                            if (toastCard.isFrontCard || toastWindow.isTransitioning) transitionAnim.restart()
                        }
                    }
                    NumberAnimation {
                        id: transitionAnim
                        target: toastCard; property: "transitionT"
                        from: 0; to: 1
                        duration: toastWindow.localBlurPulseDuration
                        easing.type: toastWindow.expanded ? Animations.pageSlideEasingOut : Animations.pageSlideEasingIn
                    }

                    // 🚀 FIX: Re-enable Y animation for ALL cards during expand/collapse transitions.
                    // During a burst (isTransitioning=false), only the front card animates, preventing GPU overload.
                    Behavior on y {
                        enabled: toastWindow.expanded || toastCard.isFrontCard || toastWindow.isTransitioning
                        NumberAnimation {
                            duration: toastWindow.localStackDuration
                            easing.type: toastWindow.expanded ? Animations.pageSlideEasingOut : Animations.pageSlideEasingIn
                        }
                    }

                    Timer {
                        id: expireTimer
                        interval: toastCard.timeout
                        running: true
                        repeat: false
                        onTriggered: dragTarget.flingOut(1)
                    }
                    onRestartTokenChanged: {
                        expireTimer.restart()
                        if (toastCard.isFrontCard || toastWindow.isTransitioning) transitionAnim.restart()
                    }

                    Item {
                        id: dragTarget
                        width: parent.width
                        height: parent.height
                        x: 0
                        y: entranceYOffset
                        property real entranceYOffset: -24
                        scale: toastCard.baseScale * popScale
                        property real popScale: 1.0

                        transform: Scale {
                            origin.x: dragTarget.width / 2
                            origin.y: dragTarget.height / 2
                            xScale: 1 + toastCard.dragBlurStrength * toastWindow.localDragStretchMax
                        }

                        Behavior on x {
                            enabled: !cardMouse.drag.active
                            NumberAnimation { duration: Animations.durationBase; easing.type: Animations.easingStandard }
                        }

                        // 🚀 FIX: Re-enable scale/opacity animations during expand/collapse.
                        Behavior on scale {
                            enabled: toastCard.isFrontCard || toastWindow.isTransitioning
                            NumberAnimation { duration: Animations.durationFast; easing.type: Animations.easingStandard }
                        }
                        Behavior on opacity {
                            enabled: toastCard.isFrontCard || toastWindow.isTransitioning
                            NumberAnimation { duration: Animations.durationBase; easing.type: Animations.easingStandard }
                        }

                        opacity: {
                            const dragFade = 1 - Math.min(Math.abs(dragTarget.x) / (toastCard.width * 0.6), 1)
                            const stretchDip = toastCard.dragBlurStrength * toastWindow.localDragStretchOpacityDip
                            return toastCard.baseOpacity * dragFade * (1 - stretchDip)
                        }

                        layer.enabled: toastCard.isFrontCard
                        layer.effect: DropShadow {
                            radius: 8
                            samples: toastWindow.currentShadowSamples
                            horizontalOffset: 0
                            verticalOffset: 3
                            color: Qt.rgba(0, 0, 0, toastCard.cardIsMoving ? 0.2 : 0.45 * toastCard.baseOpacity)
                        }

                        Component.onCompleted: {
                            if (!toastCard.isFrontCard) {
                                toastCard.entering = false
                                dragTarget.entranceYOffset = 0
                                dragTarget.opacity = toastCard.baseOpacity
                                dragTarget.scale = toastCard.baseScale
                                return
                            }
                            const now = Date.now()
                            const slot = Math.max(now, toastWindow.nextEntranceSlot)
                            entranceStartTimer.interval = slot - now
                            toastWindow.nextEntranceSlot = slot + toastWindow.localEntranceStaggerMs
                            entranceStartTimer.start()
                        }
                        Timer {
                            id: entranceStartTimer
                            interval: 0
                            repeat: false
                            onTriggered: {
                                entranceAnim.start()
                                entranceSlide.start()
                                transitionAnim.restart()
                            }
                        }
                        NumberAnimation {
                            id: entranceAnim
                            target: dragTarget; property: "opacity"
                            from: 0; to: toastCard.baseOpacity
                            duration: Animations.panelFadeDuration; easing.type: Easing.OutCubic
                        }
                        NumberAnimation {
                            id: entranceSlide
                            target: dragTarget; property: "entranceYOffset"
                            to: 0
                            duration: Animations.durationBase
                            easing.type: Easing.OutBack
                            onStopped: toastCard.entering = false
                        }

                        function flingOut(direction) {
                            const now = Date.now()
                            const slot = Math.max(now, toastWindow.nextExitSlot)
                            toastWindow.nextExitSlot = slot + toastWindow.localExitStaggerMs
                            exitStartTimer.direction = direction
                            exitStartTimer.interval = slot - now
                            exitStartTimer.start()
                        }
                        Timer {
                            id: exitStartTimer
                            property int direction: 1
                            interval: 0
                            repeat: false
                            onTriggered: {
                                flingAnim.toX = exitStartTimer.direction * toastCard.width * Animations.itemDismissDistanceFactor
                                flingAnim.start()
                                transitionAnim.restart()
                            }
                        }
                        NumberAnimation {
                            id: flingAnim
                            property real toX: 0
                            target: dragTarget; property: "x"; to: toX
                            duration: Animations.itemDismissDuration
                            easing.type: Animations.itemDismissEasing
                            onStopped: Notifications.dismissToast(toastCard.hash)
                        }

                        function popBack() {
                            popSpring.start()
                            popPulse.restart()
                        }
                        SpringAnimation {
                            id: popSpring
                            target: dragTarget; property: "x"
                            to: 0
                            spring: Animations.releasePopSpring
                            damping: Animations.releasePopDamping
                            mass: Animations.releasePopMass
                        }
                        SequentialAnimation {
                            id: popPulse
                            NumberAnimation {
                                target: dragTarget; property: "popScale"
                                to: Animations.releasePopScale
                                duration: Animations.releasePopDuration / 2
                                easing.type: Easing.OutCubic
                            }
                            NumberAnimation {
                                target: dragTarget; property: "popScale"
                                to: 1.0
                                duration: Animations.releasePopDuration / 2
                                easing.type: Easing.InCubic
                            }
                        }

                        GlassPanel {
                            id: cardBg
                            width: parent.width
                            implicitHeight: textBlurWrapper.implicitHeight
                            color: Qt.rgba(Theme.popupBg.r, Theme.popupBg.g, Theme.popupBg.b, toastWindow.localCardOpacity)

                            Item {
                                id: textBlurWrapper
                                width: parent.width
                                implicitHeight: cardCol.implicitHeight
                                height: implicitHeight

                                // 🚀 FIX: Allow blur layer during transitions for smoothness, but keep it zero-cost during bursts.
                                layer.enabled: (toastCard.isFrontCard || toastWindow.isTransitioning) && toastCard.wantsBlurLayer && toastCard.blurStrength > 0.02
                                layer.effect: DirectionalBlur {
                                    angle: toastCard.currentBlurAngle
                                    length: toastCard.currentBlurLength
                                    samples: Math.min(toastWindow.currentBlurSamples, 8)
                                }

                                Column {
                                    id: cardCol
                                    width: parent.width
                                    spacing: 6

                                    Item { width: 1; }

                                    Text {
                                        text: toastCard.mergeCount > 1
                                        ? (toastCard.title + " x" + toastCard.mergeCount)
                                        : toastCard.title
                                        color: Theme.foreground
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 13
                                        font.bold: true
                                        width: parent.width
                                        topPadding: 12
                                        leftPadding: 12
                                        rightPadding: 12
                                        horizontalAlignment: Text.AlignHCenter
                                        wrapMode: Text.Wrap
                                    }
                                    Text {
                                        visible: withinDrawDistance
                                        text: toastCard.body
                                        color: Theme.foreground
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 12
                                        width: parent.width
                                        leftPadding: 12
                                        rightPadding: 12
                                        horizontalAlignment: Text.AlignHCenter
                                        wrapMode: Text.Wrap
                                        maximumLineCount: toastWindow.localBodyMaxLines
                                        elide: Text.ElideRight
                                    }
                                    Item { width: 1; height: 10 }
                                }
                            }

                            Rectangle {
                                anchors.fill: parent
                                color: "black"
                                opacity: toastCard.scrimOpacity
                                radius: Theme.radiusMd
                            }
                        }

                        MouseArea {
                            id: cardMouse
                            anchors.fill: parent
                            acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                            drag.target: dragTarget
                            drag.axis: Drag.XAxis
                            drag.minimumY: 0
                            drag.maximumY: 0

                            onReleased: (mouse) => {
                                const dragged = dragTarget.x
                                if (Math.abs(dragged) > toastCard.width * 0.3) {
                                    dragTarget.flingOut(dragged > 0 ? 1 : -1)
                                } else {
                                    dragTarget.popBack()
                                }
                            }

                            onClicked: (mouse) => {
                                if (Math.abs(dragTarget.x) > 6) return

                                    if (mouse.button === Qt.RightButton) {
                                        if (toastWindow.expanded) {
                                            if (toastCard.rawDepth === 0) toastWindow.expanded = false
                                        } else {
                                            toastWindow.expanded = true
                                        }
                                        return
                                    }

                                    if (mouse.button === Qt.MiddleButton) {
                                        Notifications.dismissAllToasts()
                                    } else if (toastCard.actions && toastCard.actions.length > 0) {
                                        toastCard.actions[0].invoke()
                                        dragTarget.flingOut(1)
                                    } else {
                                        dragTarget.flingOut(1)
                                    }
                            }
                        }
                    }
                }
            }
        }
    }
}
