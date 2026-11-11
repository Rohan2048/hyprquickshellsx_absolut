pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Single source of truth for the current wallpaper image path.
QtObject {
    id: state

    property string statePath: Quickshell.env("HOME") + "/.cache/quickshell_wallpaper_state.json"

    property string imagePath: ""
    property bool initialized: false

    signal transitionPulse()

    // (imagePath, imageChanged)
    signal wallpaperUpdated(string imagePath, bool imageChanged)

    property FileView _file: FileView {
        path: state.statePath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: _debounce.restart()
    }

    property Timer _debounce: Timer {
        interval: 30
        repeat: false
        onTriggered: state._process()
    }

    function _process() {
        let data
        try {
            data = JSON.parse(state._file.text())
        } catch (e) {
            console.warn("WallpaperState: bad JSON", e)
            return
        }

        state.transitionPulse()

        const newImage = data.wallpaper || ""
        const imageChanged = newImage.length > 0 && newImage !== state.imagePath

        if (imageChanged) state.imagePath = newImage
            state.initialized = true

            state.wallpaperUpdated(state.imagePath, imageChanged)
    }

    Component.onCompleted: _file.reload()
}
