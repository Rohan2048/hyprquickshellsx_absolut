import QtQuick

// A Flickable whose mouse wheel glides instead of jumping.
//  - wheel notch: one short eased animation to a target (rapid notches add up, the animation
//    just retargets); nothing runs between wheel events, so there is no timer or per-frame work
//  - touchpad: follows the fingers directly (pixel deltas), no extra animation
//  - drag / flick / scrollbar behave exactly as a normal Flickable
Flickable {
    id: f

    property real wheelStep: 90        // px per wheel notch
    property int smoothMs: 170

    clip: true
    boundsBehavior: Flickable.StopAtBounds
    pixelAligned: true                 // text and edges stay crisp while moving
    maximumFlickVelocity: 3200
    flickDeceleration: 2600

    function _clampY(y) { return Math.max(0, Math.min(y, Math.max(0, f.contentHeight - f.height))) }

    NumberAnimation {
        id: glide
        target: f
        property: "contentY"
        duration: f.smoothMs
        easing.type: Easing.OutCubic
    }

    // grabbing / flicking by hand cancels a running glide
    onMovementStarted: glide.stop()

    WheelHandler {
        target: null
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: (e) => {
            if (f.contentHeight <= f.height) return
                if (e.pixelDelta.y !== 0) {
                    glide.stop()
                    f.contentY = f._clampY(f.contentY - e.pixelDelta.y)
                    return
                }
                const base = glide.running ? glide.to : f.contentY
                const to = f._clampY(base - (e.angleDelta.y / 120) * f.wheelStep)
                glide.stop()
                glide.from = f.contentY
                glide.to = to
                glide.start()
        }
    }
}
