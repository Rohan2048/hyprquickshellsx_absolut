import QtQuick

// SBSLockBackground.qml — flat black backdrop for the SBS lock screen.
//
// No pre-lock screenshot capture, no live ScreencopyView, no blur: SBS
// runs with no wallpaper underneath in the first place (see the
// Variants gating in the shell root), so there is nothing to preserve
// or composite against here, and no black-flash risk to guard against
// either. This is the entire background.
Rectangle {
    anchors.fill: parent
    color: "black"
}
