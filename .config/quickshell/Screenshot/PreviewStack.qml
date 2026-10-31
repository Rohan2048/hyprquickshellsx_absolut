pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import "../Services"
import "../Theme"
import "../Widgets"

PanelWindow {
    id: previewWindow

    readonly property int cardWidth: 168
    readonly property int cardHeight: 108
    readonly property int cardSpacing: 10
    readonly property int margin: 16

    property bool closingAll: false
    property bool _suppressDismiss: false
    property int previewGeneration: 0
    property int _prevStoreCount: ScreenshotQueue.store.count

    visible: ScreenshotQueue.store.count > 0
    color: "transparent"
    exclusiveZone: 0

    WlrLayershell.namespace: "quickshell:screenshot-preview"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.exclusionMode: ExclusionMode.Ignore

    anchors { bottom: true; left: true }

    implicitWidth: cardWidth + margin * 2
    implicitHeight: (ScreenshotQueue.maxItems * (cardHeight + cardSpacing)) + (margin * 2)

    mask: Region {
        item: stackArea
    }

    Connections {
        target: ScreenshotQueue.store
        function onCountChanged() {
            const newCount = ScreenshotQueue.store.count;
            // Only reset generation on a genuine empty -> non-empty transition
            // (a fresh toast group starting up). Removing an item via edit/dismiss
            // that happens to bring the count down to 1 must NOT bump this, or it
            // orphans the sessionGeneration on any still-pending timers.
            if (newCount === 1 && previewWindow._prevStoreCount === 0 && !closingAll) {
                previewGeneration++;
                closingAll = false;
            }
            previewWindow._prevStoreCount = newCount;
        }
    }

    onVisibleChanged: {
        if (!visible) {
            closingAll = false;
        }
    }

    ClickAwayCloser {
        targetWindows: [previewWindow]
        active: previewWindow.visible
        onDismissed: {
            if (previewWindow._suppressDismiss) {
                previewWindow._suppressDismiss = false;
                return;
            }
            if (previewWindow.closingAll) return;
            closeAllTimer.start();
        }
    }

    Timer {
        id: closeAllTimer
        interval: 140
        repeat: false
        property int sessionGeneration: previewGeneration
        onTriggered: {
            if (sessionGeneration !== previewGeneration) return;
            previewWindow.closingAll = true;

            // FIX: Removed ScreenshotQueue.dismissAll() here.
            // Calling it instantly wiped the model, destroying all delegates
            // at once and bypassing the staggered animations.
            // Now, we rely entirely on the individual staggerTimers to call
            // triggerClose("dismiss") one by one, which then lets the
            // cleanupTimer remove them individually after the animation.
            // This guarantees one-by-one closing regardless of Editor state.
        }
    }

    Item {
        id: stackArea
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.leftMargin: previewWindow.margin
        anchors.bottomMargin: previewWindow.margin
        width: previewWindow.cardWidth

        height: ScreenshotQueue.store.count * (previewWindow.cardHeight + previewWindow.cardSpacing)
        Behavior on height { NumberAnimation { duration: 250; easing.type: Easing.OutQuint } }

        Repeater {
            id: toastRepeater
            model: ScreenshotQueue.store

            delegate: Item {
                id: cardRoot
                required property int index
                required property int itemId
                required property string path
                required property real createdAt

                property bool paused: false
                property bool isClosing: false
                property bool isEntering: true
                property string _pendingAction: ""
                property real _elapsedMs: 0
                property real _runStart: cardRoot.createdAt
                property int cardGeneration: previewGeneration

                Connections {
                    target: ScreenshotSession
                    function onActiveChanged() {
                        if (ScreenshotSession.active) {
                            cardRoot.paused = false;
                            if (!cardRoot.isClosing && !previewWindow.closingAll) {
                                cardRoot._startTimer();
                            }
                        }
                    }
                }

                width: previewWindow.cardWidth
                height: previewWindow.cardHeight + previewWindow.cardSpacing

                y: index * (previewWindow.cardHeight + previewWindow.cardSpacing)
                Behavior on y { NumberAnimation { duration: 250; easing.type: Easing.OutQuint } }

                function triggerClose(action) {
                    if (cardRoot.isClosing) return;
                    if (cardGeneration !== previewGeneration) return;

                    cardRoot._pendingAction = action;
                    cardRoot.isClosing = true;
                    lifeTimer.stop();
                    cleanupTimer.restart();
                }

                Component.onCompleted: {
                    if (previewWindow.closingAll) {
                        staggerTimer.interval = index * 60;
                        staggerTimer.start();
                    } else {
                        cardRoot.isEntering = false;
                        cardRoot._startTimer();
                    }
                }

                Timer {
                    id: staggerTimer
                    repeat: false
                    property int sessionGeneration: cardGeneration
                    onTriggered: {
                        if (sessionGeneration !== previewGeneration) return;
                        cardRoot.triggerClose("dismiss");
                    }
                }

                Connections {
                    target: previewWindow
                    function onClosingAllChanged() {
                        if (previewWindow.closingAll) {
                            if (cardGeneration !== previewGeneration) return;
                            lifeTimer.stop();
                            staggerTimer.interval = index * 60;
                            staggerTimer.sessionGeneration = cardGeneration;
                            staggerTimer.start();
                        }
                    }
                }

                function _remainingMs() { return Math.max(50, ScreenshotQueue.lingerMs - cardRoot._elapsedMs); }
                function _startTimer() {
                    if (cardGeneration !== previewGeneration) return;
                    if (ScreenshotSession.active) {
                        cardRoot.paused = false;
                    }
                    cardRoot._runStart = Date.now();
                    lifeTimer.interval = cardRoot._remainingMs();
                    lifeTimer.sessionGeneration = cardGeneration;
                    lifeTimer.restart();
                }

                onPausedChanged: {
                    if (ScreenshotSession.active) {
                        cardRoot.paused = false;
                        if (!cardRoot.isClosing && !previewWindow.closingAll) {
                            cardRoot._startTimer();
                        }
                        return;
                    }

                    if (cardRoot.paused) {
                        cardRoot._elapsedMs += Date.now() - cardRoot._runStart;
                        lifeTimer.stop();
                    } else if (!cardRoot.isClosing && !previewWindow.closingAll) {
                        cardRoot._startTimer();
                    }
                }

                Timer {
                    id: lifeTimer
                    repeat: false
                    property int sessionGeneration: cardGeneration
                    onTriggered: {
                        if (sessionGeneration !== previewGeneration) return;
                        cardRoot.triggerClose("dismiss");
                    }
                }

                Timer {
                    id: cleanupTimer
                    interval: 250
                    repeat: false
                    property int sessionGeneration: cardGeneration
                    onTriggered: {
                        if (sessionGeneration !== previewGeneration) return;

                        if (cardRoot._pendingAction !== "") {
                            const action = cardRoot._pendingAction;
                            cardRoot._pendingAction = "";
                            if (action === "dismiss") ScreenshotQueue.dismiss(itemId);
                            else if (action === "discard") ScreenshotQueue.discard(itemId);
                            else if (action === "edit") {
                                previewWindow._suppressDismiss = true;
                                ScreenshotQueue.openInEditor(itemId);
                            }
                        }
                    }
                }

                Item {
                    id: visualCard
                    width: parent.width
                    height: previewWindow.cardHeight
                    anchors.bottom: parent.bottom

                    opacity: (cardRoot.isClosing || cardRoot.isEntering) ? 0 : 1
                    Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutQuint } }

                    transform: Translate {
                        y: (cardRoot.isClosing || cardRoot.isEntering) ? 25 : 0
                        Behavior on y { NumberAnimation { duration: 250; easing.type: Easing.OutQuint } }
                    }

                    clip: true
                    GlassPanel { id: cardBg; anchors.fill: parent }

                    Item {
                        id: clipArea
                        anchors.fill: parent; anchors.margins: 5; clip: true
                        Image {
                            anchors.fill: parent
                            source: "file://" + cardRoot.path
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true; cache: false
                            // Thumbnail only: decode at card size, not the full screenshot.
                            sourceSize: Qt.size(previewWindow.cardWidth * 2, previewWindow.cardHeight * 2)
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: !ScreenshotSession.active
                        cursorShape: Qt.PointingHandCursor
                        onEntered: {
                            if (!ScreenshotSession.active) {
                                cardRoot.paused = true;
                            }
                        }
                        onExited: {
                            if (!ScreenshotSession.active) {
                                cardRoot.paused = false;
                            }
                        }
                        onClicked: cardRoot.triggerClose("edit")
                    }

                    Rectangle {
                        id: closeBtn
                        z: 10; width: 20; height: 20; radius: 10
                        anchors { top: parent.top; right: parent.right; margins: 4 }
                        color: closeMouse.containsMouse ? Theme.hoverBgStrong : Theme.popupBg
                        border.width: 1; border.color: Theme.borderMuted
                        Text { anchors.centerIn: parent; text: "\u00D7"; color: Theme.foreground; font.bold: true }
                        MouseArea {
                            id: closeMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: cardRoot.triggerClose("discard")
                        }
                    }
                }
            }
        }
    }
}
