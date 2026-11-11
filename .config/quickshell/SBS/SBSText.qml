import QtQuick

// SBSText.qml — shared white/monospace label, factored out of the
// dozens of near-identical `color: "white"; font.family: "monospace";
// font.pixelSize: N` Text blocks across SBSShell/SBSWifi/SBSBluetooth/
// SBSLockScreen. `size` aliases font.pixelSize; any other Text
// property (font.bold, wrapMode, color override, etc.) can still be
// set per-instance exactly as on a plain Text.
Text {
    property int size: 11
    color: "white"
    font.family: "SFPro Display"
    font.pixelSize: size
}
