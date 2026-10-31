import QtQml
import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
// Qualified: Qt5Compat also defines ConicalGradient, which would shadow the
// QtQuick.Shapes one (centerX/centerY/angle) used in the warm-up below.
import Qt5Compat.GraphicalEffects as GE
import "./Bar"
import "./Popups"
import "./Background"
import "./Services"
import "./Widgets"
import "./Lock"
import "./Screenshot"
import "./OSDPopup"
import "./SBS"
// import "./WinBtn"   // only used by the commented-out WinDecorations loader below; the folder is not part of this tree

ShellRoot {
    id: shellRoot

    // The Bar instance running on the primary screen, so WinDecorations
    // can reuse its toggleMinimize/isMinimizedFake machinery.
    property var primaryBar: {
        var insts = barVariants.instances
        for (var i = 0; i < insts.length; i++) {
            if (insts[i].modelData === Quickshell.screens[0]) return insts[i]
        }
        return null
    }

    Component.onCompleted: {
        ScreenshotSession.active
        BatteryInfo.start()
    }

    // Preload the music picker backend (folder listing, mpv state, icon
    // decode) after login instead of on first use. It waits until the shader
    // warm-up window below has finished (6 s) so the two never overlap, and
    // the listing itself runs at the lowest CPU priority.
    Timer {
        interval: 7000
        running: true
        onTriggered: MusicPicker.preload()
    }

    // The screenshot editor and the preview stack are only needed while a
    // screenshot is being edited / queued. Building their QML trees (and
    // keeping their windows around) at startup cost RAM and login CPU for
    // something used rarely, so they are created on demand and destroyed
    // when done. Each one's own `visible` already tracked these same
    // conditions, so nothing is shown or hidden any differently.
    Loader {
        id: screenshotLoader
        active: ScreenshotSession.active
        sourceComponent: ScreenshotWindow {}
        // The window used to restore direct scanout from its onVisibleChanged;
        // a destroyed window can't, so do it here.
        onActiveChanged: if (!active) directScanoutRestore.running = true
    }
    Process {
        id: directScanoutRestore
        command: ["hyprctl", "keyword", "render:direct_scanout", "1"]
    }
    Loader {
        active: ScreenshotQueue.store.count > 0
        sourceComponent: PreviewStack {}
    }

    Variants {
        model: SBSState._loaded && !SBSState.active ? Quickshell.screens : []
        Wallpaper {}
    }
    Variants {
        id: barVariants
        model: {
            if (!SBSState._loaded || SBSState.active) return []
                const internal = Quickshell.screens.filter(s => /^(eDP|LVDS)-/.test(s.name))
                return internal.length > 0 ? internal : Quickshell.screens
        }
        BarHost {}
    }
    Variants {
        model: {
            if (!SBSState._loaded || !SBSState.active) return []
                const internal = Quickshell.screens.filter(s => /^(eDP|LVDS)-/.test(s.name))
                return internal.length > 0 ? internal : Quickshell.screens
        }
        SBSShell {}
    }

    Loader {
        id: shortcutsLoader
        // created by the first keybind / IPC call, or right away when the hover zone is on
        // (Settings > Popups > Shortcuts palette > Trigger) so the zone can see the pointer
        property bool forced: false
        active: forced || PopupSettings.shortcutsTrigger !== "keybind"
        sourceComponent: ShortcutsWindow {}
    }
    Loader {
        id: commandsLoader
        active: false
        sourceComponent: CommandsPopup {}
    }

    IpcHandler {
        target: "shortcuts"
        function toggle(): void {
            shortcutsLoader.forced = true
            if (shortcutsLoader.item) shortcutsLoader.item.keybindToggle()
        }
        function open(): void {
            shortcutsLoader.forced = true
            if (shortcutsLoader.item) shortcutsLoader.item.keybindOpen()
        }
        function close(): void {
            if (shortcutsLoader.item) shortcutsLoader.item.keybindClose()
        }
    }
    IpcHandler {
        target: "commands"
        function toggle(): void {
            commandsLoader.active = true
            commandsLoader.item.shown = !commandsLoader.item.shown
        }
    }

    WorkspaceOverview { id: workspaceOverview }
    MusicPickerPopup {}
    SettingsPopup {}
    CommandAddDialog {}
    AppLauncherPopup {}
    ClipboardPopup {}
    ChoicePopup {}
    WallpaperPickerPopup {}
    ShortcutPickerPopup {}
    NotificationToast {}
    Loader {
        id: osdPopupLoader
        active: !SBSState.active
        sourceComponent: OSDPopup {}
    }
    Loader {
        active: true
        sourceComponent: (SBSState._loaded && SBSState.active) ? sbsLockComponent : mainLockComponent
    }
    Component { id: mainLockComponent; LockScreen {} }
    Component { id: sbsLockComponent; SBSLockScreen {} }

    // Window button decorations — main screen only for now.
    // Off during SBS: one PanelWindow per open window is extra
    // layer-shell surfaces we don't want eating battery in that mode.
    // Loader {
    //     id: winDecorationsLoader
    //     active: SBSState._loaded && !SBSState.active && shellRoot.primaryBar !== null
    //     sourceComponent: WinDecorations { bar: shellRoot.primaryBar }
    // }

    // One-off shader warm-up (DirectionalBlur) so the first real animation
    // doesn't stall on shader compilation. Only needs to exist briefly at
    // startup; keeping a permanent layer-shell surface + render target alive
    // for the whole session just to have compiled it once was wasted RAM.
    Loader {
        id: shaderWarmupLoader
        active: true
        sourceComponent: shaderWarmupComponent
    }
    Timer {
        interval: 6000
        running: true
        onTriggered: shaderWarmupLoader.active = false
    }
    Component {
        id: shaderWarmupComponent
        PanelWindow {
            id: shaderWarmup
            visible: true
            color: "transparent"
            implicitWidth: 1
            implicitHeight: 1
            exclusiveZone: -1

            WlrLayershell.namespace: "quickshell:warmup"
            WlrLayershell.layer: WlrLayer.Background
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            anchors { top: true; left: true }
            margins { top: -10000; left: -10000 }

            Item {
                anchors.fill: parent
                layer.enabled: true
                layer.effect: GE.DirectionalBlur { angle: 0; length: 1; samples: 4 }
            }
            // Also compile the MultiEffect blur used by the lock screen so
            // the first lock of a session doesn't wait on shader compilation.
            Rectangle {
                id: lockWarmSrc
                width: 1; height: 1; color: "black"; visible: false
                layer.enabled: true
            }
            // ...and the ColorOverlay used to tint the music picker icons.
            GE.ColorOverlay {
                width: 1; height: 1
                source: lockWarmSrc
                color: "black"
            }
            // ...and the border: a ring filled with a conical gradient on the curve renderer (rotate / pulse
            // effects, Widgets/PanelBorder.qml) plus the plain rounded border. Compiling these here means the
            // first popup with an animated border doesn't stall on shader / pipeline creation.
            Shape {
                width: 24; height: 24
                preferredRendererType: Shape.CurveRenderer
                opacity: 0.99
                ShapePath {
                    strokeWidth: -1
                    fillRule: ShapePath.OddEvenFill
                    fillGradient: ConicalGradient {
                        centerX: 12; centerY: 12; angle: 30
                        GradientStop { position: 0.0; color: "#ffffff" }
                        GradientStop { position: 0.5; color: "#808080" }
                        GradientStop { position: 1.0; color: "#ffffff" }
                    }
                    PathSvg { path: "M 6 0 H 18 A 6 6 0 0 1 24 6 V 18 A 6 6 0 0 1 18 24 H 6 A 6 6 0 0 1 0 18 V 6 A 6 6 0 0 1 6 0 Z M 2 2 H 22 V 22 H 2 Z" }
                }
            }
            Rectangle {
                width: 16; height: 16; radius: 5; color: "transparent"
                border.width: 1; border.color: "#ffffff"
                topLeftRadius: 5; topRightRadius: 3
            }
            MultiEffect {
                width: 1; height: 1
                source: lockWarmSrc
                autoPaddingEnabled: false
                blurEnabled: true; blur: 1.0; blurMax: 96; blurMultiplier: 1.6
                saturation: -0.08; brightness: -0.06; contrast: 0.05
            }
        }
    }
}
