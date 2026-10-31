import QtQuick
import QtQuick.Layouts
import "../Services"
import "../Theme"
import "../Widgets"

// Settings > Battery: every battery detail on one page.
//   summary      percentage, state, power draw, time left
//   details      energy, capacities, health, cycles, manufacturer, model ...
//   charge limit stop charging at 80 % (only where the laptop's firmware / kernel driver offers it)
//   last 24 h    battery level and power draw graphs (hover for the exact value)
//   history      the last two weeks: energy used, health and cycle count per day
// Data: Services/BatteryInfo.qml  <-  scripts/battery-info.py
Item {
    id: page

    readonly property var info: BatteryInfo.info
    readonly property var lim: info.limit ?? ({ supported: false })
    readonly property var hist: BatteryInfo.hist
    readonly property string code: info.code ?? "u"

    Component.onCompleted: BatteryInfo.watching = true
    Component.onDestruction: BatteryInfo.watching = false

    // ── helpers ──
    function f1(x) { return (x === null || x === undefined) ? "\u2013" : Number(x).toFixed(1) }
    function f2(x) { return (x === null || x === undefined) ? "\u2013" : Number(x).toFixed(2) }
    function dur(mins) {
        if (mins === null || mins === undefined) return ""
            const h = Math.floor(mins / 60), m = mins % 60
            return h + " h " + (m < 10 ? "0" : "") + m + " min"
    }
    readonly property string statusText: {
        if (code === "c") return "Charging"
            if (code === "d") return "On battery"
                if (code === "f") return "Fully charged"
                    if (code === "n") return lim.supported && lim.on ? "Plugged in \u00B7 charge limit reached" : "Plugged in \u00B7 not charging"
                        return info.status ?? "Unknown"
    }
    readonly property string powerText: {
        const w = info.watts ?? 0
        if (code === "d") return "Using " + f1(w) + " W"
            if (code === "c") return "Charging at " + f1(w) + " W"
                return f1(w) + " W"
    }
    readonly property string leftText: {
        if (info.minutesLeft === null || info.minutesLeft === undefined) return ""
            return dur(info.minutesLeft) + (code === "c" ? " until full" : " left")
    }

    component Hint: Text {
        color: Theme.foreground
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSm
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
    }
    component Section: Text {
        color: Theme.foreground
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        font.bold: true
        Layout.fillWidth: true
        Layout.topMargin: 2
    }
    component Divider: Rectangle { Layout.fillWidth: true; height: 1; color: Theme.borderMuted }

    // "label ........ value"
    component KV: RowLayout {
        id: kv
        property string k: ""
        property string v: ""
        Layout.fillWidth: true
        spacing: 10
        Text {
            text: kv.k
            color: Theme.foreground
            opacity: 0.7
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            Layout.preferredWidth: 190
        }
        Text {
            text: kv.v
            color: Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            font.bold: true
            elide: Text.ElideRight
            Layout.fillWidth: true
        }
    }

    // A 24 h line graph. mode "level" = battery % (0..100), "power" = watts (scales to the peak).
    // Charging periods get a green band; holes in the data (shell was off) are left empty.
    component Chart: Item {
        id: ch
        property var points: []
        property real now: 0
        property string mode: "level"
        readonly property real span: 24 * 3600
        readonly property real peak: {
            let m = 0
            for (let i = 0; i < points.length; i++) m = Math.max(m, points[i].w)
                return m
        }
        readonly property real yMax: mode === "level" ? 100 : Math.max(5, Math.ceil(peak / 5) * 5)
        property int hoverIdx: -1
        readonly property color lineCol: Theme.accentActive
        readonly property color areaCol: Qt.rgba(Theme.accentActive.r, Theme.accentActive.g, Theme.accentActive.b, 0.18)
        readonly property color bandCol: Qt.rgba(0.25, 0.78, 0.45, 0.16)
        readonly property color gridCol: Qt.rgba(Theme.foreground.r, Theme.foreground.g, Theme.foreground.b, 0.12)

        implicitHeight: 128

        function valueOf(p) { return ch.mode === "level" ? p.p : p.w }
        function hoverText() {
            if (ch.hoverIdx < 0 || ch.hoverIdx >= points.length) return ""
                const p = points[ch.hoverIdx]
                const st = ({ c: "charging", d: "on battery", f: "full", n: "not charging" })[p.s] ?? ""
                return Qt.formatDateTime(new Date(p.t * 1000), "ddd HH:mm") + "  \u00B7  " + p.p + "%  \u00B7  "
                + Number(p.w).toFixed(1) + " W" + (st !== "" ? "  \u00B7  " + st : "")
        }

        onPointsChanged: cv.requestPaint()
        onYMaxChanged: cv.requestPaint()
        onNowChanged: cv.requestPaint()
        Connections { target: Theme; function onIsDarkChanged() { cv.requestPaint() } }

        // axis labels
        Text {
            x: 0; y: 0
            text: ch.mode === "level" ? "100%" : ch.yMax + " W"
            color: Theme.foreground; opacity: 0.6
            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeXs
        }
        Text {
            x: 0; y: cv.y + cv.height - height
            text: ch.mode === "level" ? "0%" : "0 W"
            color: Theme.foreground; opacity: 0.6
            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeXs
        }
        Text {
            x: cv.x; y: ch.height - height
            text: ch.now > 0 ? Qt.formatDateTime(new Date((ch.now - ch.span) * 1000), "ddd HH:mm") : ""
            color: Theme.foreground; opacity: 0.6
            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeXs
        }
        Text {
            x: cv.x + (cv.width - width) / 2; y: ch.height - height
            text: ch.now > 0 ? Qt.formatDateTime(new Date((ch.now - ch.span / 2) * 1000), "ddd HH:mm") : ""
            color: Theme.foreground; opacity: 0.6
            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeXs
        }
        Text {
            x: cv.x + cv.width - width; y: ch.height - height
            text: "now"
            color: Theme.foreground; opacity: 0.6
            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeXs
        }
        // value under the pointer
        Text {
            x: cv.x + cv.width - width; y: 0
            text: ch.hoverText()
            color: Theme.foreground
            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeXs; font.bold: true
        }

        Canvas {
            id: cv
            x: 40; y: 14
            width: ch.width - 40
            height: ch.height - 14 - 16
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()

            onPaint: {
                const ctx = getContext("2d")
                ctx.reset()
                const w = width, h = height
                const t0 = ch.now - ch.span
                const pts = ch.points

                ctx.lineWidth = 1
                ctx.strokeStyle = ch.gridCol
                for (let g = 0; g <= 4; g++) {
                    const gy = Math.round(h * g / 4) + 0.5
                    ctx.beginPath(); ctx.moveTo(0, gy); ctx.lineTo(w, gy); ctx.stroke()
                }
                if (pts.length < 2 || ch.now <= 0) return

                    const X = (t) => (t - t0) / ch.span * w
                    const Y = (v) => h - Math.max(0, Math.min(1, v / ch.yMax)) * h

                    // charging bands
                    ctx.fillStyle = ch.bandCol
                    for (let i = 0; i < pts.length - 1; i++) {
                        const a = pts[i], b = pts[i + 1]
                        if (a.s !== "c" || b.t - a.t > 900) continue
                            ctx.fillRect(X(a.t), 0, Math.max(1, X(b.t) - X(a.t)), h)
                    }

                    // continuous runs of samples
                    const runs = []
                    let run = [pts[0]]
                    for (let i = 1; i < pts.length; i++) {
                        if (pts[i].t - pts[i - 1].t > 900) { runs.push(run); run = [] }
                        run.push(pts[i])
                    }
                    runs.push(run)

                    ctx.lineJoin = "round"
                    for (let r = 0; r < runs.length; r++) {
                        const seg = runs[r]
                        if (seg.length < 2) continue
                            ctx.beginPath()
                            ctx.moveTo(X(seg[0].t), Y(ch.valueOf(seg[0])))
                            for (let i = 1; i < seg.length; i++) ctx.lineTo(X(seg[i].t), Y(ch.valueOf(seg[i])))
                                ctx.strokeStyle = ch.lineCol
                                ctx.lineWidth = 2
                                ctx.stroke()
                                ctx.lineTo(X(seg[seg.length - 1].t), h)
                                ctx.lineTo(X(seg[0].t), h)
                                ctx.closePath()
                                ctx.fillStyle = ch.areaCol
                                ctx.fill()
                    }

                    // hovered sample
                    if (ch.hoverIdx >= 0 && ch.hoverIdx < pts.length) {
                        const p = pts[ch.hoverIdx]
                        ctx.strokeStyle = ch.lineCol
                        ctx.lineWidth = 1
                        ctx.beginPath(); ctx.moveTo(X(p.t) + 0.5, 0); ctx.lineTo(X(p.t) + 0.5, h); ctx.stroke()
                        ctx.fillStyle = ch.lineCol
                        ctx.beginPath(); ctx.arc(X(p.t), Y(ch.valueOf(p)), 3.5, 0, Math.PI * 2); ctx.fill()
                    }
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                onExited: { ch.hoverIdx = -1; cv.requestPaint() }
                onPositionChanged: (m) => {
                    const t = (ch.now - ch.span) + m.x / Math.max(1, cv.width) * ch.span
                    let best = -1, bd = 1e12
                    for (let i = 0; i < ch.points.length; i++) {
                        const d = Math.abs(ch.points[i].t - t)
                        if (d < bd) { bd = d; best = i }
                    }
                    if (bd > 900) best = -1
                        if (best !== ch.hoverIdx) { ch.hoverIdx = best; cv.requestPaint() }
                }
            }
        }
    }

    Flickable {
        id: flick
        anchors.fill: parent
        anchors.leftMargin: -14; anchors.rightMargin: -14   // horizontal gutter only (hover-scaled buttons); top/bottom clip at the real edge
        clip: true
        contentWidth: width
        contentHeight: col.implicitHeight + 8
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: col
            x: 14; y: 4
            width: flick.width - 28
            spacing: 12

            Hint {
                visible: BatteryInfo.loaded && info.present === false
                text: "No battery found. This looks like a desktop (or a machine whose battery Linux cannot see)."
            }
            Hint {
                visible: !BatteryInfo.loaded
                text: "Reading the battery..."
            }

            // ───────────── summary ─────────────
            Rectangle {
                visible: BatteryInfo.loaded && info.present !== false
                Layout.fillWidth: true
                implicitHeight: sumRow.implicitHeight + 24
                radius: Theme.radiusMd
                color: "transparent"
                border.width: 1
                border.color: Theme.borderMuted

                RowLayout {
                    id: sumRow
                    x: 14; y: 12
                    width: parent.width - 28
                    spacing: 18

                    Text {
                        text: (info.percent ?? 0) + "%"
                        color: Theme.foreground
                        font.family: Theme.fontFamily
                        font.pixelSize: 40
                        font.bold: true
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        Text {
                            text: page.statusText
                            color: Theme.foreground
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                            font.bold: true
                        }
                        Text {
                            text: page.powerText + (page.leftText !== "" ? "  \u00B7  " + page.leftText : "")
                            color: Theme.foreground
                            opacity: 0.75
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                        }
                    }
                    // slim bar: charge, with the 80 % mark
                    Rectangle {
                        Layout.preferredWidth: 150
                        Layout.preferredHeight: 12
                        radius: 6
                        color: Theme.pillOffBg
                        border.width: 1
                        border.color: Theme.borderMuted
                        Rectangle {
                            height: parent.height
                            radius: 6
                            width: parent.width * Math.max(0, Math.min(100, info.percent ?? 0)) / 100
                            color: (info.percent ?? 100) <= 15 && page.code === "d" ? "#e5484d" : Theme.accentActive
                        }
                        Rectangle {
                            x: parent.width * 0.8
                            width: 1
                            height: parent.height
                            color: Theme.foreground
                            opacity: 0.5
                        }
                    }
                }
            }

            // ───────────── details ─────────────
            Section { visible: BatteryInfo.loaded && info.present !== false; text: "Details" }
            ColumnLayout {
                visible: BatteryInfo.loaded && info.present !== false
                Layout.fillWidth: true
                spacing: 6

                KV { k: "Percentage"; v: (info.percent ?? "\u2013") + "%" }
                KV { k: "Power draw"; v: page.f1(info.watts) + " W" + (page.code === "d" ? "  (being used)" : page.code === "c" ? "  (going in)" : "") }
                KV { k: "Voltage"; v: info.voltage ? page.f2(info.voltage) + " V" : "\u2013" }
                KV { k: "Energy in the battery"; v: info.energyNow !== null && info.energyNow !== undefined ? page.f1(info.energyNow) + " Wh" : "\u2013" }
                KV { k: "Full-charge capacity"; v: info.energyFull !== null && info.energyFull !== undefined ? page.f1(info.energyFull) + " Wh" : "\u2013" }
                KV { k: "Design capacity"; v: info.energyDesign !== null && info.energyDesign !== undefined ? page.f1(info.energyDesign) + " Wh" : "\u2013" }
                KV { k: "Health"; v: info.health !== null && info.health !== undefined ? page.f1(info.health) + "%  of its original capacity" : "\u2013" }
                KV {
                    k: "Charge cycles"
                    v: (info.cycles !== null && info.cycles !== undefined && info.cycles > 0) ? String(info.cycles) : "Not reported by this battery"
                }
                KV { k: "Manufacturer"; v: info.manufacturer || "\u2013" }
                KV { k: "Model"; v: info.model || "\u2013" }
                KV { k: "Technology"; v: info.technology || "\u2013" }
            }

            Divider { visible: BatteryInfo.loaded && info.present !== false }

            // ───────────── charge limit ─────────────
            Section { visible: BatteryInfo.loaded && info.present !== false; text: "Charge limit" }
            ColumnLayout {
                visible: BatteryInfo.loaded && info.present !== false
                Layout.fillWidth: true
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    Text {
                        text: page.lim.kind === "conservation" ? "Battery conservation mode" : "Do not charge above 80%"
                        color: Theme.foreground
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        Layout.preferredWidth: 190
                        opacity: page.lim.supported ? 1 : 0.5
                    }
                    Row {
                        spacing: 6
                        GlassButton {
                            text: "On"
                            active: page.lim.supported && page.lim.on
                            disabled: !page.lim.supported || BatteryInfo.limitBusy
                            onClicked: BatteryInfo.setLimit(true)
                        }
                        GlassButton {
                            text: "Off"
                            active: page.lim.supported && !page.lim.on
                            disabled: !page.lim.supported || BatteryInfo.limitBusy
                            onClicked: BatteryInfo.setLimit(false)
                        }
                    }
                    Text {
                        visible: BatteryInfo.limitBusy
                        text: "Applying..."
                        color: Theme.foreground
                        opacity: 0.7
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSm
                    }
                }

                Hint {
                    visible: page.lim.supported && page.lim.kind === "threshold"
                    text: "Charge limit: the battery stops charging at a chosen level instead of going to 100% (it is at " + (page.lim.value ?? "?") + "% now). A lithium battery wears faster the fuller it is kept, so a lower limit helps a laptop that stays plugged in. Your laptop's firmware remembers the setting, and the shell puts it back if the firmware forgets it after suspend."
                }
                Hint {
                    visible: page.lim.supported && page.lim.kind === "conservation"
                    text: "Battery conservation mode: while it is on, the laptop's firmware stops charging before the battery is full, to slow wear when the laptop stays plugged in. The laptop maker chooses the level (it varies by model, often somewhere between about 55% and 80%), so unlike a plain charge limit it is a simple on / off switch."
                }
                Hint {
                    visible: !page.lim.supported
                    text: "Not every laptop can limit charging. It is a feature of the laptop itself, not of Linux or the processor: the maker's firmware has to offer it and the kernel driver has to expose it. This one does not expose it, so the switch is off. Many laptops have no such feature at all; on others it only exists in the BIOS / UEFI setup or in the maker's own app, which is the place to look."
                }

                Hint {
                    visible: BatteryInfo.limitError !== "" || (page.lim.supported && (page.lim.error ?? "") !== "")
                    color: "#e5484d"
                    text: BatteryInfo.limitError !== "" ? BatteryInfo.limitError : (page.lim.error ?? "")
                }
                // when sudo is not set up for the one file
                ColumnLayout {
                    visible: page.lim.supported && (BatteryInfo.limitError !== "" || (page.lim.error ?? "") !== "") && (page.lim.sudoers ?? "") !== ""
                    Layout.fillWidth: true
                    spacing: 4
                    Hint { text: "Writing the limit needs root. Allow just that one file once: run  sudo visudo -f /etc/sudoers.d/battery-limit  and paste this line (select it to copy):" }
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: sudoText.implicitHeight + 14
                        radius: Theme.radiusSm
                        color: Theme.pillOffBg
                        border.width: 1
                        border.color: Theme.borderMuted
                        TextEdit {
                            id: sudoText
                            x: 8; y: 7
                            width: parent.width - 16
                            readOnly: true
                            selectByMouse: true
                            wrapMode: TextEdit.WrapAnywhere
                            text: page.lim.sudoers ?? ""
                            color: Theme.foreground
                            font.family: "monospace"
                            font.pixelSize: Theme.fontSizeSm
                        }
                    }
                }
            }

            Divider { visible: BatteryInfo.loaded && info.present !== false }

            // ───────────── last 24 h ─────────────
            Section { visible: BatteryInfo.loaded && info.present !== false; text: "Last 24 hours" }
            ColumnLayout {
                visible: BatteryInfo.loaded && info.present !== false
                Layout.fillWidth: true
                spacing: 8

                Hint {
                    text: hist.points && hist.points.length > 1
                    ? "Used " + page.f1(hist.summary.usedWh) + " Wh  \u00B7  charged " + page.f1(hist.summary.chargedWh) + " Wh  \u00B7  average draw " + page.f1(hist.summary.avgW) + " W  \u00B7  peak " + page.f1(hist.summary.peakW) + " W"
                    : "The graph fills in as the shell runs: one point every 2 minutes, kept for 48 hours."
                }

                Text {
                    text: "Battery level"
                    color: Theme.foreground; opacity: 0.75
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSm; font.bold: true
                }
                Chart { Layout.fillWidth: true; mode: "level"; points: hist.points ?? []; now: hist.now ?? 0 }

                Text {
                    text: "Power draw"
                    color: Theme.foreground; opacity: 0.75
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSm; font.bold: true
                    Layout.topMargin: 4
                }
                Chart { Layout.fillWidth: true; mode: "power"; points: hist.points ?? []; now: hist.now ?? 0 }

                Hint { text: "Green bands are times it was charging. Gaps are times the shell was not running. Hover a graph for the exact value." }
            }

            Divider { visible: BatteryInfo.loaded && info.present !== false }

            // ───────────── day by day ─────────────
            Section { visible: BatteryInfo.loaded && info.present !== false; text: "Day by day" }
            ColumnLayout {
                visible: BatteryInfo.loaded && info.present !== false
                Layout.fillWidth: true
                spacing: 4

                readonly property var days: (hist.daily ?? []).slice(0, 14)
                readonly property real usedAll: {
                    let s = 0
                    const d = hist.daily ?? []
                    for (let i = 0; i < d.length; i++) s += d[i].used_wh ?? 0
                        return s
                }

                Hint {
                    text: (info.energyDesign ?? 0) > 0 && parent.usedAll > 0
                    ? "Energy used over the last " + (hist.daily ?? []).length + " tracked days equals about " + page.f1(parent.usedAll / info.energyDesign) + " full battery cycles (an estimate from the power the battery gave out)."
                    : "Starts counting from the first day the shell logged the battery."
                }

                RowLayout {
                    Layout.fillWidth: true
                    visible: parent.days.length > 0
                    spacing: 8
                    Text { text: "Day"; Layout.preferredWidth: 110; color: Theme.foreground; opacity: 0.6; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSm }
                    Text { text: "Used"; Layout.preferredWidth: 80; color: Theme.foreground; opacity: 0.6; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSm }
                    Text { text: "Charged"; Layout.preferredWidth: 80; color: Theme.foreground; opacity: 0.6; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSm }
                    Text { text: "Health"; Layout.preferredWidth: 70; color: Theme.foreground; opacity: 0.6; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSm }
                    Text { text: "Cycles"; Layout.fillWidth: true; color: Theme.foreground; opacity: 0.6; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSm }
                }
                Repeater {
                    model: parent.days
                    delegate: RowLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 8
                        Text { text: Qt.formatDate(new Date(modelData.date + "T12:00:00"), "ddd d MMM"); Layout.preferredWidth: 110; color: Theme.foreground; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize }
                        Text { text: page.f1(modelData.used_wh) + " Wh"; Layout.preferredWidth: 80; color: Theme.foreground; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize }
                        Text { text: page.f1(modelData.charged_wh) + " Wh"; Layout.preferredWidth: 80; color: Theme.foreground; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize }
                        Text { text: modelData.health !== undefined ? page.f1(modelData.health) + "%" : "\u2013"; Layout.preferredWidth: 70; color: Theme.foreground; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize }
                        Text { text: (modelData.cycles !== undefined && modelData.cycles > 0) ? String(modelData.cycles) : "\u2013"; Layout.fillWidth: true; color: Theme.foreground; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize }
                    }
                }
            }

            Item { Layout.preferredHeight: 4 }
        }
    }
}
