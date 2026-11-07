pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// Backend for the Settings "Display" page (Services/DisplayPage.qml).
//
//  * monitors      : `hyprctl -j monitors all` (includes DISABLED outputs, which the
//                    Quickshell Hyprland module hides -- needed to switch back to a
//                    screen that is currently off).
//  * apply()       : resolution / refresh / scale through `hyprctl eval "hl.monitor{}"`
//                    (hyprctl keyword does not work under the Lua config), keeping the
//                    output's position and mirror relationship. Followed by a
//                    "keep these settings?" countdown that auto-reverts, so a mode the
//                    panel cannot show can never strand you.
//  * reset()       : preferred mode + automatic scale, same keep / revert flow.
//  * setMode()     : "only" / "extend" / "mirror" (the three-dot menu on an output). Hands off
//                    to scripts/display-switch.sh, which does what hdmi.sh does (kill qs
//                    BEFORE touching outputs, reconfigure, relaunch qs). It runs detached
//                    because it kills this very process.
//  * animation scale: same files/scripts as the Alt+R rofi picker.
//
// Changes made here apply to the running session (like hdmi.sh); a Hyprland
// restart returns to whatever hyprland.lua says.
Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property string scriptsDir: home + "/.config/quickshell/scripts"
    readonly property string stateDir: home + "/.config/quickshell/state"

    // The page sets this while it is open: events/refresh only run then.
    property bool active: false

    property var monitors: []
    property string selected: ""
    property bool loading: false
    property string statusText: ""
    property bool switching: false

    // { name, secs } while the "keep these settings?" countdown is running.
    property var pending: null
    property var _prev: null
    property var _expect: null
    property bool _wantRevert: false
    property bool _busy: false
    readonly property int revertSeconds: 12

    // ---------------- derived ----------------
    readonly property var visibleMonitors: monitors.filter(m => !/^Unknown-/i.test(m.name))
    readonly property int connectedCount: visibleMonitors.length
    readonly property int enabledCount: visibleMonitors.filter(m => !m.disabled).length
    readonly property var current: {
        for (let i = 0; i < root.monitors.length; i++)
            if (root.monitors[i].name === root.selected) return root.monitors[i]
                return null
    }
    function byName(name) {
        for (let i = 0; i < root.monitors.length; i++)
            if (root.monitors[i].name === name) return root.monitors[i]
                return null
    }

    function fmtRate(r) {
        const x = Math.round(r * 100) / 100
        return (Math.abs(x - Math.round(x)) < 0.005 ? String(Math.round(x)) : x.toFixed(2)) + " Hz"
    }
    function fmtScale(s) { return Math.round(s * 100) + "%" }

    // ---------------- querying ----------------
    onActiveChanged: if (active) root.refresh()

    function refresh() {
        root.loading = true
        _query.running = false
        _query.running = true
    }
    property Timer _refreshSoon: Timer { interval: 250; onTriggered: root.refresh() }
    property Timer _settle: Timer { interval: 700; onTriggered: root.refresh() }

    property Connections _events: Connections {
        target: Hyprland
        enabled: root.active
        function onRawEvent(event) {
            const n = event.name
            if (n === "monitoradded" || n === "monitorremoved" || n === "monitoraddedv2"
                || n === "monitorremovedv2" || n === "configreloaded")
                root._refreshSoon.restart()
        }
    }

    function _round2(x) { return Math.round(x * 100) / 100 }

    function _norm(j) {
        const resMap = {}
        const modes = j.availableModes || []
        for (let i = 0; i < modes.length; i++) {
            const m = /^(\d+)x(\d+)@([\d.]+)/.exec(modes[i])
            if (!m) continue
                const k = m[1] + "x" + m[2]
                if (!resMap[k]) resMap[k] = { w: +m[1], h: +m[2], rates: [] }
                resMap[k].rates.push(_round2(parseFloat(m[3])))
        }
        const resolutions = Object.keys(resMap).map(k => resMap[k])
        resolutions.sort((a, b) => (b.w * b.h) - (a.w * a.h))
        resolutions.forEach(r => {
            r.rates = r.rates.filter((v, i, a) => a.indexOf(v) === i).sort((a, b) => b - a)
        })
        const scale = (j.scale && j.scale > 0) ? j.scale : 1
        return {
            id: j.id,
            name: j.name,
            description: j.description || "",
            make: j.make || "",
            model: j.model || "",
            w: j.width || 0,
            h: j.height || 0,
            rate: j.refreshRate || 0,
            scale: scale,
            x: j.x || 0,
            y: j.y || 0,
            focused: j.focused === true,
            disabled: j.disabled === true,
            internal: /^(eDP|LVDS)-/.test(j.name),
            mirrorRaw: j.mirrorOf,
            mirrorOf: "",
            resolutions: resolutions,
            logicalW: Math.round((j.width || 0) / scale),
            logicalH: Math.round((j.height || 0) / scale)
        }
    }

    function _onMonitors(list) {
        // resolve mirrorOf (name, numeric id, or "none")
        list.forEach(m => {
            const r = m.mirrorRaw
            if (r === undefined || r === null || r === "none" || r === "" || r === -1) return
                for (let i = 0; i < list.length; i++)
                    if (String(list[i].id) === String(r) || list[i].name === r) { m.mirrorOf = list[i].name; return }
        })
        root.monitors = list

        // keep the editor pointed at something real
        const cur = root.byName(root.selected)
        if (!cur || cur.disabled) {
            let pick = list.find(m => m.focused && !m.disabled)
            || list.find(m => !m.disabled && !/^Unknown-/i.test(m.name))
            || list.find(m => !/^Unknown-/i.test(m.name))
            root.selected = pick ? pick.name : ""
        }

        // verify an apply() and start the revert countdown
        if (root._expect) {
            const e = root._expect
            const m = root.byName(e.name)
            root._expect = null
            if (m && !m.disabled && (e.w === 0 || (m.w === e.w && m.h === e.h))) {
                if (root._wantRevert) {
                    root.pending = { name: e.name, secs: root.revertSeconds }
                    root._countdown.restart()
                }
            } else if (root._wantRevert) {
                root.statusText = "That mode was not accepted by the display."
            }
            root._wantRevert = false
        }
    }

    property Process _query: Process {
        command: ["timeout", "3", "hyprctl", "-j", "monitors", "all"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.loading = false
                try {
                    const arr = JSON.parse(text)
                    root._onMonitors(arr.map(j => root._norm(j)))
                } catch (e) {
                    root.statusText = "Could not read monitor list from hyprctl."
                }
            }
        }
    }

    // ---------------- applying a mode / scale ----------------
    function _lua(m, w, h, r, scale) {
        const sc = Number(Number(scale).toFixed(3))
        const mirror = m.mirrorOf !== "" ? m.mirrorOf : "none"
        return 'hl.monitor({ output = "' + m.name + '", mode = "' + w + 'x' + h + '@' + r
        + '", position = "' + m.x + 'x' + m.y + '", scale = ' + sc
        + ', disabled = false, mirror = "' + mirror + '" })'
    }

    function _runEval(lua) {
        root._busy = true
        _eval.running = false
        _eval.command = ["timeout", "5", "hyprctl", "eval", lua]
        _eval.running = true
    }

    property Process _eval: Process {
        stdout: StdioCollector {}
        onExited: (code) => {
            root._busy = false
            if (code !== 0) {
                root.statusText = "hyprctl eval failed (exit " + code + ")."
                root._wantRevert = false
                root._expect = null
                root.refresh()
            } else {
                root._settle.restart()
            }
        }
    }

    function apply(name, w, h, r, scale) {
        const m = root.byName(name)
        if (!m || m.disabled || root.pending || root._busy) return
            root.statusText = ""
            root._prev = { name: name, w: m.w, h: m.h, r: root._round2(m.rate), scale: m.scale }
            root._expect = { name: name, w: w, h: h }
            root._wantRevert = true
            root._runEval(root._lua(m, w, h, r, scale))
    }

    // Back to what hyprland.lua asks for: the monitor's preferred mode and
    // automatic scale. Position and mirror are kept. Goes through the same
    // keep / revert countdown as any other change.
    function reset(name) {
        const m = root.byName(name)
        if (!m || m.disabled || root.pending || root._busy) return
            root.statusText = ""
            root._prev = { name: name, w: m.w, h: m.h, r: root._round2(m.rate), scale: m.scale }
            root._expect = { name: name, w: 0, h: 0 }      // 0 = any mode is fine, "preferred" decides
            root._wantRevert = true
            const mirror = m.mirrorOf !== "" ? m.mirrorOf : "none"
            root._runEval('hl.monitor({ output = "' + m.name + '", mode = "preferred", position = "'
            + m.x + 'x' + m.y + '", scale = "auto", disabled = false, mirror = "' + mirror + '" })')
    }

    function keep() {
        root.pending = null
        root._countdown.stop()
        root._prev = null
        // refresh rate may have changed: Auto animation scale follows it
        if (root.animMode === "auto") root.setAnim("auto")
    }

    function revert() {
        const p = root._prev
        root.pending = null
        root._countdown.stop()
        root._wantRevert = false
        root._expect = null
        root._prev = null
        if (!p) return
            const m = root.byName(p.name)
            if (m) root._runEval(root._lua(m, p.w, p.h, p.r, p.scale))
    }

    property Timer _countdown: Timer {
        interval: 1000
        repeat: true
        onTriggered: {
            const p = root.pending
            if (!p) { stop(); return }
            if (p.secs <= 1) root.revert()
                else root.pending = { name: p.name, secs: p.secs - 1 }
        }
    }

    // ---------------- display mode (same choices as hdmi.sh) ----------------
    // mode: "only"   -> show ONLY `name`            (Laptop Only / External Only)
    //       "extend" -> laptop panel + `name` to its right
    //       "mirror" -> `name` mirrors the laptop panel
    // extend / mirror take the EXTERNAL display as `name`. The script kills and
    // relaunches Quickshell, so this process will be restarted.
    function setMode(name, mode) {
        const m = root.byName(name)
        if (!m) return
            const sc = m.disabled ? "" : String(Number(m.scale.toFixed(3)))
            root.switching = true
            Quickshell.execDetached(["setsid", "-f", "bash", root.scriptsDir + "/display-switch.sh",
                                    mode, name, sc])
    }
    function switchTo(name) { root.setMode(name, "only") }

    // How the given (enabled) output is currently being used.
    function modeOf(m) {
        if (!m || m.disabled) return "off"
            if (m.mirrorOf !== "") return "mirror"
                for (let i = 0; i < root.monitors.length; i++)
                    if (root.monitors[i].mirrorOf === m.name) return "mirror"
                        return root.enabledCount > 1 ? "extend" : "only"
    }

    // ---------------- animation scale (shared with the Alt+R rofi picker) ----------------
    readonly property var animOptions: [
        { id: "auto", label: "Auto" },
        { id: "0.75", label: "0.75\u00D7" },
        { id: "1.0",  label: "1\u00D7" },
        { id: "1.25", label: "1.25\u00D7" },
        { id: "1.5",  label: "1.5\u00D7" },
        { id: "2.0",  label: "2\u00D7" }
    ]
    readonly property string animMode: modeAd.animMode
    property real animValue: 1.0

    // Rate Auto is derived from (same maths as set-animation-scale.sh).
    readonly property real _focusedRate: {
        for (let i = 0; i < root.monitors.length; i++)
            if (root.monitors[i].focused && !root.monitors[i].disabled) return root.monitors[i].rate
                for (let j = 0; j < root.monitors.length; j++)
                    if (!root.monitors[j].disabled) return root.monitors[j].rate
                        return 60
    }

    function animActive(id) {
        if (id === "auto")
            return root.animMode === "auto" && Math.abs(root.animValue - Math.round(root._focusedRate) / 60) < 0.03
            return !(root.animMode === "auto" && Math.abs(root.animValue - Math.round(root._focusedRate) / 60) < 0.03)
            && Math.abs(root.animValue - parseFloat(id)) < 0.001
    }

    function setAnim(id) {
        modeAd.animMode = id
        Quickshell.execDetached(["bash", root.scriptsDir + "/set-animation-scale.sh", id])
    }

    // Animations.qml already watches this file; we read it to highlight the active option.
    property FileView _animFile: FileView {
        path: root.home + "/.config/quickshell/.animation-scale"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            const v = parseFloat(text().trim())
            if (!isNaN(v) && v > 0) root.animValue = v
        }
    }

    property FileView _modeFile: FileView {
        path: root.stateDir + "/display-settings.json"
        blockLoading: true
        watchChanges: true
        onFileChanged: reload()
        onAdapterUpdated: writeAdapter()
        onLoadFailed: (err) => writeAdapter()
        adapter: JsonAdapter {
            id: modeAd
            property string animMode: "1.0"
        }
    }
}
