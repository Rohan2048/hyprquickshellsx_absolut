
pragma Singleton
import QtQuick
import Quickshell

// Thin compatibility forwarder. WallpaperState is now the single source
// of truth for wallpaper state AND owns the debounced file-watch that
// used to live here — this file just re-emits that same pulse under the
// old signal name so Bar.qml (and anything else still listening to
// TransitionSync.transition()) keeps working unmodified.
QtObject {
    id: sync

    signal transition()

    property Connections _forward: Connections {
        target: WallpaperState
        function onTransitionPulse() {
            sync.transition()
        }
    }
}
