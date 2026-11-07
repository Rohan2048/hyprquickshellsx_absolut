pragma Singleton
import QtQuick

/**
 * BorderClock.qml -- the one clock behind the border effects (pulse / rotate), Widgets/PanelBorder.qml.
 *
 * Before, every panel ran its own Qt animation at the monitor's full refresh rate, whether the panel was
 * on screen or not (the Music / Font / Settings windows stay mapped but transparent between uses, so their
 * borders kept redrawing, and the compositor kept re-blurring behind them). Now:
 *   - nothing ticks unless at least one border is really on screen (`users` > 0) and an effect is on
 *   - one timer drives all of them, at a capped rate: 30 fps for a rotating border (40 when it is fast),
 *     20 fps for a plain pulse, which is plenty for a slow fade; the stepped "anime" effect only ticks at
 *     about twice its own 5-15 fps
 *   - a border's phase comes from this clock, so every panel shows the same moment of the effect
 */
QtObject {
    id: root

    // borders that are on screen right now and need ticks (PanelBorder counts itself in and out)
    property int users: 0
    // milliseconds since the clock was created; moves only while it is running
    property real t: 0

    // the fastest effect that is on decides the tick; the "anime" effect only needs two ticks per frame of its
    // own (5-15 fps), it takes its frame number from `t` (PanelBorder.animeStep)
    readonly property int stepMs: {
        let ms = 1000
        if (BorderSettings.rotate) ms = Math.min(ms, BorderSettings.speed >= 8 ? 25 : 33)
            if (BorderSettings.pulse) ms = Math.min(ms, 50)
                if (BorderSettings.anime) ms = Math.min(ms, Math.max(25, Math.round(500 / BorderSettings.animeFps)))
                    return ms
    }

    property double _t0: Date.now()

    property Timer ticker: Timer {
        interval: root.stepMs
        repeat: true
        running: root.users > 0 && BorderSettings.animated
        onTriggered: root.t = Date.now() - root._t0
    }
}
