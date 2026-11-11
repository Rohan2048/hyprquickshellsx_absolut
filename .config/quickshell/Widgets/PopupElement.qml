import QtQuick
import "../Services"

// One movable, scalable piece of a popup (a title, a row of buttons, a graph ...).
//
//     PopupElement { elementId: "buttons"; Layout.alignment: Qt.AlignHCenter; RowLayout { ... } }
//
// It sizes itself to its content, so it sits in a layout exactly as the content would. The position
// and scale chosen in Settings > Popups > Popup styles are applied visually on top of that
// (an offset in px and a uniform scale, never a stretch), so moving one element never pushes the
// others around. Which popup it belongs to is found the same way the buttons find theirs (`popupId` of
// the nearest ancestor), so it works in the real popup and in the Settings preview alike.
Item {
    id: root

    property string elementId: ""
    // the layout editor sets this to draw / drag the element; the real popup never does
    property string popupIdOverride: ""
    readonly property string popupId: root.popupIdOverride !== "" ? root.popupIdOverride : PopupSettings.ctxOf(root)

    // current place (in memory at once; the file follows a moment later)
    property real liveX: PopupSettings.elemX(root.popupId, root.elementId)
    property real liveY: PopupSettings.elemY(root.popupId, root.elementId)
    property real livePct: PopupSettings.elemPct(root.popupId, root.elementId)

    // text alignment chosen in Settings: the piece sits at the left / centre / right of the space it was given
    readonly property string align: PopupSettings.elemAlign(root.popupId, root.elementId)
    readonly property real alignShift: {
        if (root.align === "" || !root.parent) return 0
            const pw = root.parent.width, w = root.width
            return root.align === "l" ? -root.x : (root.align === "c" ? (pw - w) / 2 - root.x : pw - w - root.x)
    }

    default property alias data: holder.data

        // A piece that fills its row has nowhere to shift to, so the alignment is also given to the text inside it
        // (not to a button's own label: that is aligned by the button).
        property var _texts: []
        function _collectTexts(item, depth) {
            if (!item || depth > 8) return
                const k = item.children
                for (let i = 0; i < k.length; i++) {
                    const o = k[i]
                    if (o.isGlassButton === true) continue
                        let clickable = false
                        for (let j = 0; j < o.children.length; j++) if (o.children[j].acceptedButtons !== undefined && o.children[j].containsMouse !== undefined) clickable = true
                            if (clickable) continue
                                if (typeof o.text === "string" && o.elide !== undefined && o.echoMode === undefined && o.horizontalAlignment !== undefined) {
                                    let known = false
                                    for (let t = 0; t < root._texts.length; t++) if (root._texts[t].item === o) known = true
                                        if (!known) root._texts.push({ item: o, ha: o.horizontalAlignment })
                                }
                                root._collectTexts(o, depth + 1)
                }
        }
        function applyTextAlign() {
            root._collectTexts(holder, 0)
            const a = root.align
            const ha = a === "l" ? Text.AlignLeft : (a === "r" ? Text.AlignRight : Text.AlignHCenter)
            for (let t = 0; t < root._texts.length; t++) {
                const e = root._texts[t]
                if (e.item) e.item.horizontalAlignment = a === "" ? e.ha : ha
            }
        }
        onAlignChanged: root.applyTextAlign()
        // lists fill in after the piece exists: pick their text up too while an alignment is set
        Timer { interval: 500; repeat: true; running: root.align !== ""; onTriggered: root.applyTextAlign() }
        Component.onCompleted: if (root.align !== "") root.applyTextAlign()

        // A piece that is just one GlassButton is a button: Settings stretches the button itself (its label keeps its size),
        // scales the label's font, moves the label and aligns it (see Popups/PopupLayoutEditor)
        readonly property Item soleButton: (holder.children.length === 1 && holder.children[0].isGlassButton === true) ? holder.children[0] : null
        readonly property bool isButton: root.soleButton !== null
        readonly property real _sw: PopupSettings.elemW(root.popupId, root.elementId) / 100
        readonly property real _sh: PopupSettings.elemH(root.popupId, root.elementId) / 100
        Binding { target: root.soleButton; property: "stretchW"; value: root._sw; when: root.soleButton !== null }
        Binding { target: root.soleButton; property: "stretchH"; value: root._sh; when: root.soleButton !== null }
        // styledWidth / styledHeight = the button's own size with the popup style and the stretch applied (see GlassButton)
        Binding { target: root.soleButton; property: "width"; value: root.soleButton ? root.soleButton.styledWidth : 0; when: root.soleButton !== null && root.soleButton._pinW }
        Binding { target: root.soleButton; property: "height"; value: root.soleButton ? root.soleButton.styledHeight : 0; when: root.soleButton !== null && root.soleButton._pinH }
        Binding { target: root.soleButton; property: "fontScale"; value: PopupSettings.elemFs(root.popupId, root.elementId) / 100; when: root.soleButton !== null }
        Binding { target: root.soleButton; property: "textDx"; value: PopupSettings.elemTx(root.popupId, root.elementId); when: root.soleButton !== null }
        Binding { target: root.soleButton; property: "textDy"; value: PopupSettings.elemTy(root.popupId, root.elementId); when: root.soleButton !== null }
        Binding { target: root.soleButton; property: "labelAlign"; value: root.align === "l" ? Qt.AlignLeft : (root.align === "r" ? Qt.AlignRight : Qt.AlignHCenter); when: root.soleButton !== null && root.align !== "" }
        // the moved / scaled box, so the layout editor can outline it
        readonly property Item box: holder

        implicitWidth: holder.childrenRect.width
        implicitHeight: holder.childrenRect.height

        Item {
            id: holder
            width: root.width
            height: root.height
            x: root.liveX + root.alignShift
            y: root.liveY
            scale: root.livePct / 100
            transformOrigin: Item.Center
        }
}
