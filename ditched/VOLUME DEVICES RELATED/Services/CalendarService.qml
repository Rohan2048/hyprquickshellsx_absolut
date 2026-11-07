pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    readonly property string scriptPath: Quickshell.env("HOME") + "/.config/quickshell/scripts/calendar.sh"
    readonly property string triggerFile: Quickshell.env("HOME") + "/.cache/quickshell/cal_trigger"

    readonly property var emptyMonth: ({
        year: 0, month: 0, month_name: "", today_day: -1,
        week0: [], week1: [], week2: [], week3: [], week4: [], week5: [],
        prev: ({ year: 0, month: 0 }), next: ({ year: 0, month: 0 })
    })
    readonly property var emptyDay: ({
        date: 0, weekday: 0, today: false, has_event: false,
        has_holiday: false, holiday_name: "", events: [], filler: true
    })

    property var calendarData: emptyMonth
    property int displayYear: new Date().getFullYear()
    property int displayMonth: new Date().getMonth() + 1

    property string view: "month"        // "month" | "detail"
    property string slideDirection: ""   // "left" | "right" | ""
    property var selectedDay: emptyDay

    property bool loading: false
    property bool refreshing: false

    // Guards ONLY the very first load. Component.onCompleted is the
    // guaranteed path (fires regardless of whether triggerFile exists on
    // disk yet); FileView.onLoaded is a second path that also happens to
    // fire on startup if the file already exists and loads fast. Without
    // this flag, both would fire and load() would run twice on launch.
    // After startup, this flag is irrelevant — onLoaded from real
    // triggerWatch.reload() calls goes straight to load() every time,
    // unguarded, so live refreshes still work.
    property bool _didInitialLoad: false

    Component.onCompleted: {
        if (root._didInitialLoad) return
            root._didInitialLoad = true
            load(displayYear, displayMonth, false)
    }

    // ── month view navigation ──────────────────────────────────────────
    signal aboutToNavigate(string direction)

    function goPrev() {
        const y = calendarData.prev.year, m = calendarData.prev.month
        aboutToNavigate("left")
        load(y, m, false, "left")
    }

    function goNext() {
        const y = calendarData.next.year, m = calendarData.next.month
        aboutToNavigate("right")
        load(y, m, false, "right")
    }

    function goToday() {
        const now = new Date()
        const targetYear = now.getFullYear()
        const targetMonth = now.getMonth() + 1

        if (targetYear === displayYear && targetMonth === displayMonth) {
            return
        }

        const current = displayYear * 12 + displayMonth
        const target = targetYear * 12 + targetMonth
        const direction = target < current ? "left" : "right"

        aboutToNavigate(direction)
        load(targetYear, targetMonth, false, direction)
    }

    function refresh() {
        refreshing = true
        load(displayYear, displayMonth, true)
    }

    Timer {
        id: slideResetTimer
        interval: 220
        onTriggered: root.slideDirection = ""
    }

    // ── detail view ───────────────────────────────────────────────────
    function selectDay(day) {
        if (day.filler || !(day.has_event || day.has_holiday)) return
            selectedDay = day
            view = "detail"
    }

    function backToMonth() {
        view = "month"
    }

    // ── process plumbing ─────────────────────────────────────────────
    Component {
        id: procComponent
        Process {
            id: proc
            property int reqYear
            property int reqMonth
            property string reqDirection
            stdout: StdioCollector {
                onStreamFinished: {
                    root._handleOutput(this.text, proc.reqYear, proc.reqMonth, proc.reqDirection)
                    proc.destroy()
                }
            }
        }
    }

    function load(year, month, doRefresh, direction = "") {
        loading = true
        const args = ["python3", scriptPath, String(year), String(month)]
        if (doRefresh) args.push("--refresh")
            const proc = procComponent.createObject(root, {
                command: args,
                reqYear: year,
                reqMonth: month,
                reqDirection: direction
            })
            proc.running = true
    }

    function _handleOutput(text, reqYear, reqMonth, reqDirection) {
        try {
            const data = JSON.parse(text)
            calendarData = data
            displayYear = data.year
            displayMonth = data.month
            if (reqDirection) {
                slideDirection = reqDirection
                slideResetTimer.restart()
            }
        } catch (e) {
            console.warn("CalendarService: failed to parse calendar.sh output for",
                         reqYear, reqMonth, "-", e)
        }
        loading = false
        refreshing = false
    }

    // Debounces triggerFile changes — scripts that touch this file via
    // write-then-rename (atomic write) commonly emit two filesystem change
    // events for one logical update.
    Timer {
        id: triggerDebounce
        interval: 50
        onTriggered: triggerWatch.reload()
    }

    FileView {
        id: triggerWatch
        path: root.triggerFile
        watchChanges: true
        printErrors: false        // add this
        onFileChanged: triggerDebounce.restart()
        onLoaded: {
            if (!root._didInitialLoad) {
                root._didInitialLoad = true
            }
            root.load(root.displayYear, root.displayMonth, false)
        }
    }
}
