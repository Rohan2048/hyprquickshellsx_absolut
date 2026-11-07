pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../SBS"

QtObject {
    id: root

    // ---- Super Battery Saver: hard animation kill-switch ----
    // When SBS mode is active, every duration below collapses to 0 and
    // every spring collapses to a snap (no oscillation/overshoot — that's
    // why this is a separate branch per function rather than folding into
    // `scale`, which multiplies and would make springs ring harder, not
    // disappear). Components using these functions/properties go instant
    // automatically; nothing else needs to change in them.
    readonly property bool sbsActive: SBSState.active

    // ---- Refresh-rate animation scaling ----
    // 1.0 = tuned for 60Hz. Higher scale = faster (shorter) durations.
    // Set by ~/.config/quickshell/.animation-scale, written by the rofi picker.
    property real scale: 1.0

    property FileView scaleFile: FileView {
        id: scaleFile
        path: Quickshell.env("HOME") + "/.config/quickshell/.animation-scale"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            const parsed = parseFloat(text().trim())
            if (!isNaN(parsed) && parsed > 0)
                root.scale = parsed
        }
    }

    function scaleDuration(baseMs) {
        if (root.sbsActive) return 0
        return Math.max(1, Math.round(baseMs / scale))
    }
    function scaleSpring(baseSpring) {
        // NOT gated on sbsActive: a spring constant of 0 means zero
        // restoring force in SpringAnimation, i.e. the item stops moving
        // entirely rather than snapping instantly — that would freeze
        // whichever widget uses it, not remove its animation. Consumers
        // of this function need per-widget review to decide what
        // "instant" means for their specific spring/damping combo.
        return baseSpring * scale
    }
    function scaleSpeed(basePxPerSecond) {
        if (root.sbsActive) return 0
        return basePxPerSecond * scale
    }

    readonly property int durationFast: scaleDuration(130)
    readonly property int durationBase: scaleDuration(170)
    readonly property int easingStandard: Easing.OutCubic

    readonly property real hoverScale: 1.06
    readonly property int hoverScaleDuration: scaleDuration(140)
    readonly property int hoverScaleEasing: Easing.OutBack
    readonly property real hoverScaleOvershoot: 6

    readonly property real trackSpring: scaleSpring(6.5)
    readonly property real trackDamping: 0.4
    readonly property real trackMass: 0.35

    readonly property real overshootSpring: scaleSpring(5.5)
    readonly property real overshootDamping: 0.38
    readonly property real overshootMass: 0.3

    readonly property real releasePopSpring: scaleSpring(6.5)
    readonly property real releasePopDamping: 0.26
    readonly property real releasePopMass: 0.28
    readonly property real releasePopScale: 1.12
    readonly property int releasePopDuration: scaleDuration(260)
    readonly property real pinnedStretchSpring: scaleSpring(3.5)
    readonly property real pinnedStretchDamping: 0.35
    readonly property real pinnedStretchMass: 0.28

    readonly property int accordionDuration: scaleDuration(220)
    readonly property int accordionEasing: Easing.OutBack

    readonly property int barResizeDuration: scaleDuration(260)
    readonly property int barResizeEasing: Easing.OutQuint

    readonly property real panelSlideSpring: scaleSpring(5.5)
    readonly property real panelSlideDamping: 0.32
    readonly property real panelSlideMass: 0.32
    readonly property real panelBlurRadius: 24
    readonly property int panelFadeDuration: scaleDuration(90)
    readonly property int pageSlideDuration: scaleDuration(220)
    readonly property int pageSlideEasingOut: Easing.OutCubic
    readonly property int pageSlideEasingIn: Easing.InCubic

    readonly property int motionBlurSamples: 32
    readonly property real motionBlurLength: 20
    readonly property int motionBlurFadeDuration: scaleDuration(90)

    readonly property int slideBlurDuration: scaleDuration(260)
    readonly property int slideBlurEasingOut: Easing.OutCubic
    readonly property int slideBlurEasingIn: Easing.InCubic
    readonly property int slideBlurSamples: 24

    readonly property real slideBlurHorizontalAngle: 0
    readonly property real slideBlurVerticalAngle: 90

    readonly property real slideBlurHorizontalLength: 28
    readonly property real slideBlurVerticalLength: 28

    readonly property int itemDismissDuration: scaleDuration(140)
    readonly property int itemDismissEasing: Easing.InCubic
    readonly property real itemDismissDistanceFactor: 1.6
    readonly property int itemDismissCollapseDuration: scaleDuration(140)

    readonly property int toastBlurSamples: 28
    readonly property real toastBlurSwipeLength: 20
    readonly property real toastBlurToggleLength: 26
    readonly property real toastBlurRestPerDepth: 5
    readonly property real toastBlurRestMax: 20
    readonly property int toastBlurRetargetDuration: scaleDuration(110)
    readonly property int toastBlurRetargetEasing: Easing.OutCubic
    readonly property int toastMaxRenderedDepth: 6

    readonly property int toastCardStackDuration: scaleDuration(150)
    readonly property int toastCardBlurPulseDuration: scaleDuration(200)
    readonly property int toastCardBlurRetargetDuration: scaleDuration(85)
    readonly property int toastCardBlurSamples: 16
    readonly property int toastCardShadowSamples: 5
    readonly property int toastCardMaxRenderedDepth: 3
    readonly property real toastCardBlurRestBase: 30
    readonly property real toastCardBlurRestPerDepth: 6
    readonly property real toastCardBlurRestMax: 40
    readonly property int toastCardShadowMaxDepth: 2

    readonly property real toastCardDragBlurMaxLen: 20
    readonly property real toastCardDragBlurVelocityFactor: 0.5
    readonly property real toastCardVelocitySmoothing: 0.4
    readonly property real toastCardVelocityBlurMax: 2200

    readonly property real marqueePxPerSecond: scaleSpeed(10)
    readonly property int marqueePauseMs: scaleDuration(500)
    readonly property int marqueeEasing: Easing.InOutSine
    readonly property int marqueeMinDuration: scaleDuration(700)

    readonly property int trackSwapOutDuration: scaleDuration(110)
    readonly property int trackSwapInDuration: scaleDuration(150)
    readonly property int trackSwapOutEasing: Easing.InCubic
    readonly property int trackSwapInEasing: Easing.OutBack
    readonly property real trackSwapSlideDistance: 24
    readonly property real trackSwapBlurLength: 24

    readonly property int wallpaperCrossfadeDuration: scaleDuration(500)
    readonly property int wallpaperCrossfadeEasing: Easing.OutCubic
    readonly property real wallpaperBlurAngle: 0
    readonly property real wallpaperBlurLength: 32
    readonly property int wallpaperBlurSamples: 14


    readonly property int shakyStepCount: 6
    readonly property int shakyStepDuration: scaleDuration(50)
    readonly property real shakyJitterMax: 10
    readonly property real shakyBlurMaxLength: 16
    readonly property int shakyBlurSamples: 10
    readonly property int shakyEntranceDuration: scaleDuration(300)
    readonly property int shakyEntranceEasing: Easing.OutBack
    readonly property int shakyStagger: scaleDuration(55)

    function rubberBand(distance, maxStretch, stretchConstant) {
        return (distance * maxStretch * stretchConstant) / (maxStretch + stretchConstant * distance)
    }

    function blurEnvelope(progress) {
        return Math.sin(Math.max(0, Math.min(1, progress)) * Math.PI)
    }
}
