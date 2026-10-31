pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property string status: "Stopped"
    property string title: ""
    property string artist: ""
    property string album: ""
    property string art: ""
    property real duration: 0
    property string durationFmt: "00:00"
    property real position: 0
    property string positionFmt: "00:00"
    property bool seeking: false

    readonly property bool playing: status === "Playing"
    readonly property bool active: status === "Playing" || status === "Paused"

    // Name of the mpris player currently driving the popup. All controls
    // (play/pause/next/prev/seek/position-poll) target this explicitly —
    // this is the actual fix: previously every playerctl call had no
    // --player flag, so it silently used playerctl's own default player,
    // which ignores playback state entirely.
    property string activePlayerName: ""

    // Per-player live state, keyed by playerctl's playerName.
    // { status, title, artist, album, art, duration, ts }
    property var _players: ({})

    // Art cache keyed by playerName+title+artist, same reasoning as
    // before: some MPRIS bridges (plasma-browser-integration) emit a
    // blank mpris:artUrl mid-track, and flap the title between e.g.
    // "Song Name" / "Song Name - YouTube" for the same track.
    property var _artCache: ({})

    readonly property string _sep: "\x1f"

    function fmt(secs) {
        secs = Math.max(0, Math.floor(secs))
        const m = Math.floor(secs / 60)
        const s = secs % 60
        return (m < 10 ? "0" + m : m) + ":" + (s < 10 ? "0" + s : s)
    }

    function playPause() { if (root.activePlayerName !== "") ctl.run(["playerctl", "--player=" + root.activePlayerName, "play-pause"]) }
    function next()      { if (root.activePlayerName !== "") ctl.run(["playerctl", "--player=" + root.activePlayerName, "next"]) }
    function previous()  { if (root.activePlayerName !== "") ctl.run(["playerctl", "--player=" + root.activePlayerName, "previous"]) }

    // percent: 0-100, mirrors music-seek.sh
    function seek(percent) {
        if (duration <= 0 || root.activePlayerName === "") return
            const target = (percent / 100.0) * duration
            root.position = target
            root.positionFmt = fmt(target)
            ctl.run(["playerctl", "--player=" + root.activePlayerName, "position", target.toFixed(2)])
    }

    function _reset() {
        root.status           = "Stopped"
        root.title            = ""
        root.artist           = ""
        root.album            = ""
        root.art              = ""
        root.duration         = 0
        root.durationFmt      = "00:00"
        root.position         = 0
        root.positionFmt      = "00:00"
        root.activePlayerName = ""
    }

    // The actual priority fix: a Playing player always wins over a
    // Paused one, regardless of which was started first or which
    // playerctl would've picked by default. Among ties (e.g. two
    // simultaneously Playing, which shouldn't normally happen, or two
    // Paused with nothing playing) the most recently-updated one wins,
    // so starting playback on a second source takes over immediately.
    function _pickActivePlayer() {
        let bestName = ""
        let bestTs = -1

        for (const name in root._players) {
            const p = root._players[name]
            if (p.status === "Playing" && p.ts > bestTs) {
                bestName = name
                bestTs = p.ts
            }
        }

        if (bestName === "") {
            for (const name in root._players) {
                const p = root._players[name]
                if (p.status === "Paused" && p.ts > bestTs) {
                    bestName = name
                    bestTs = p.ts
                }
            }
        }

        if (bestName === "") {
            root._reset()
            return
        }

        const p = root._players[bestName]
        root.activePlayerName = bestName
        root.status      = p.status
        root.title       = p.title
        root.artist      = p.artist
        root.album       = p.album
        root.art         = p.art
        root.duration    = p.duration
        root.durationFmt = root.fmt(p.duration)
        // root.position/positionFmt are refreshed independently by the
        // poll timer below, keyed off activePlayerName, so they snap to
        // the newly-active player's position rather than showing the
        // previous player's stale value for a second.
    }

    // Debounce _pickActivePlayer(): metaFollow can emit several players'
    // lines in quick succession (e.g. mpv + a browser tab both reporting
    // in around startup), and picking after every single line makes the
    // active player flicker/flip before all of them have checked in.
    // Restarting this timer on every line and only picking once it fires
    // collapses a burst into a single, stable decision.
    Timer {
        id: pickSettleTimer
        interval: 150
        onTriggered: root._pickActivePlayer()
    }

    // fire-and-forget control commands (play-pause, next, previous, seek)
    Process {
        id: ctl
        function run(cmd) {
            ctl.command = cmd
            ctl.running = true
        }
    }

    // Single follow process covering every MPRIS player at once (-a).
    // Format includes playerName + status, so we track every source's
    // playback state and let _pickActivePlayer choose — this replaces
    // the old single-player statusFollow + metaFollow pair, which had
    // no way to even know a second player existed.
    Process {
        id: metaFollow
        command: ["playerctl", "-a", "--follow", "metadata", "--format",
        "{{playerName}}" + root._sep + "{{status}}" + root._sep + "{{title}}" + root._sep +
        "{{artist}}" + root._sep + "{{album}}" + root._sep + "{{mpris:artUrl}}" + root._sep +
        "{{mpris:length}}"]
        running: true

        stdout: SplitParser {
            onRead: line => {
                const parts = line.split(root._sep)
                if (parts.length < 7) return

                    const playerName = parts[0]
                    if (playerName.trim() === "") return

                        const status = parts[1]

                        // same blank-mid-track guard as before (plasma-browser-
                        // integration periodically emits a blank line mid-track) —
                        // just skip it, per-player, instead of clobbering good data
                        if (parts[2].trim() === "") return

                            // strip the "- YouTube" suffix some browser bridges flap
                            // the title with, so it doesn't look like a track change
                            const normalizedTitle = parts[2].replace(/\s*-\s*YouTube\s*$/i, "").trim()
                            const cacheKey = playerName + root._sep + normalizedTitle + root._sep + parts[3]
                            const newArt = parts[5]

                            let resolvedArt
                            if (newArt !== "") {
                                root._artCache[cacheKey] = newArt
                                resolvedArt = newArt
                            } else if (root._artCache[cacheKey]) {
                                resolvedArt = root._artCache[cacheKey]
                            } else {
                                resolvedArt = ""
                            }

                            const lenUs = parseFloat(parts[6])
                            const durationSecs = (!isNaN(lenUs) && lenUs > 0) ? lenUs / 1_000_000.0 : 0

                            root._players[playerName] = {
                                status: status,
                                title: parts[2],
                                artist: parts[3],
                                album: parts[4],
                                art: resolvedArt,
                                duration: durationSecs,
                                ts: Date.now()
                            }

                            // a player that stopped/exited shouldn't be able to
                            // keep "winning" the active-player pick
                            if (status !== "Playing" && status !== "Paused") {
                                delete root._players[playerName]
                            }

                            pickSettleTimer.restart()
            }
        }

        onExited: (code, status) => metaRestart.start()
    }

    Timer {
        id: metaRestart
        interval: 1500
        onTriggered: metaFollow.running = true
    }

    // playerctl -a --follow never emits a final line when a player just
    // closes (browser tab closed, app quit) — it goes quiet instead of
    // signaling removal. Poll the live player list and drop anything
    // from _players no longer present, so a closed source can't keep
    // winning _pickActivePlayer on stale state.
    Process {
        id: playerListProc
        command: ["playerctl", "-l"]
        stdout: StdioCollector {
            onStreamFinished: {
                const live = text.split("\n").map(s => s.trim()).filter(s => s.length > 0)
                let changed = false
                for (const name in root._players) {
                    if (live.indexOf(name) === -1) {
                        delete root._players[name]
                        changed = true
                    }
                }
                if (changed) pickSettleTimer.restart()
            }
        }
    }

    Timer {
        interval: 3000
        running: true
        repeat: true
        onTriggered: playerListProc.running = true
    }

    // Position polling for whichever player is currently active. Skipped
    // while the user is dragging the seek bar (root.seeking).
    Timer {
        interval: 1000
        running: root.active
        repeat: true
        onTriggered: if (!root.seeking && root.activePlayerName !== "") posProc.running = true
    }

    Process {
        id: posProc
        command: root.activePlayerName !== "" ? ["playerctl", "--player=" + root.activePlayerName, "position"] : []

        stdout: StdioCollector {
            onStreamFinished: {
                const val = parseFloat(text)
                if (!isNaN(val) && !root.seeking) {
                    root.position = val
                    root.positionFmt = root.fmt(val)
                }
            }
        }
    }
}
