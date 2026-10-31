import QtQuick
import "../Theme"
import "../Services"
// Horizontally auto-scrolls its text when it's too wide for the box instead
// of eliding it. Scrolls only while `active` is true (drive that from your
// own hover MouseArea) so a whole list of these isn't all animating on
// screen at once — parks back at the start when not active.
//
// Drop into a fixed-width/height Item; this clips to whatever size it's
// given, so size it explicitly (Layout.preferredWidth, or width:/height:).
Item {
    id: root
    property string text: ""
    property color textColor: Theme.foreground
    property alias font: label.font
    property bool active: false
    property int horizontalAlignment: Text.AlignLeft
    clip: true
    implicitHeight: label.implicitHeight
    readonly property real overflow: Math.max(0, label.implicitWidth - width)
    readonly property bool overflowing: overflow > 0.5
    readonly property int scrollDuration: Math.max(
        Animations.marqueeMinDuration,
        (overflow / Animations.marqueePxPerSecond) * 400
    )
    // Single source of truth for where the text is parked. The actual
    // sliding motion is entirely handled by the Behavior on label.x below —
    // there is exactly one thing ever writing to that property, so there's
    // no way for a duration/target to go stale mid-flight and make it look
    // like it's teleporting instead of sliding (which is what the old
    // SequentialAnimation + reactive-duration setup could do if the
    // button's width so much as twitched during layout).
    property bool atEnd: false
    // True for the "snap back to start because hover ended" case, so that
    // reset is quick (Animations.durationFast) instead of crawling back at
    // the same slow pace it scrolled out at.
    readonly property bool resetting: !active
    Timer {
        id: flipTimer
        repeat: true
        onTriggered: {
            root.atEnd = !root.atEnd
            // From here on, every flip must wait for the scroll that this
            // trigger just kicked off to finish, then pause — but the very
            // first trigger has no prior animation to wait on, so it alone
            // uses a short pauseMs-only interval (set in onActiveChanged).
            interval = Animations.marqueePauseMs + root.scrollDuration
        }
        // no `running:` binding — fully imperative control from onActiveChanged
    }
    onActiveChanged: {
        flipTimer.stop()
        atEnd = false
        if (active) {
            flipTimer.interval = Animations.marqueePauseMs
            flipTimer.start()
        }
    }
    onOverflowingChanged: if (!overflowing) atEnd = false
    Text {
        id: label
        x: root.overflowing && root.atEnd ? -root.overflow : 0
        Behavior on x {
            enabled: root.overflowing
            NumberAnimation {
                duration: root.resetting ? Animations.durationFast : root.scrollDuration
                easing.type: root.resetting ? Animations.easingStandard : Animations.marqueeEasing
            }
        }
        width: root.overflowing ? implicitWidth : root.width
        height: root.height
        text: root.text
        color: root.textColor
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        verticalAlignment: Text.AlignVCenter
        horizontalAlignment: root.overflowing ? Text.AlignLeft : root.horizontalAlignment
        elide: Text.ElideNone
    }
}
