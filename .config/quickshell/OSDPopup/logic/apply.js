.pragma library

function apply(ctx, kind, value) {
    switch (kind) {
        case "touchpad_on":
            ctx.glyph.text = "󰟸"; ctx.label.text = "Touchpad On"; ctx.root.showPill = false
            break
        case "touchpad_off":
            ctx.glyph.text = "󰟹"; ctx.label.text = "Touchpad Off"; ctx.root.showPill = false
            break
        case "volume":
            ctx.glyph.text = "󰕾"
            ctx.root.pillValue = value
            ctx.root.showPill = true
            ctx.label.text = ""
            break
        case "volume_muted":
            ctx.glyph.text = "󰝟"; ctx.label.text = "Muted"; ctx.root.showPill = false
            break
        case "volume_unmuted":
            ctx.glyph.text = "󰕾"; ctx.label.text = "Unmuted"; ctx.root.showPill = false
            break
        case "brightness":
            ctx.glyph.text = "󰃟"; ctx.label.text = ""
            ctx.root.pillValue = value / 100; ctx.root.showPill = true
            break
        case "mic_on":
            ctx.glyph.text = "󰍬"; ctx.label.text = "Microphone On"; ctx.root.showPill = false
            break
        case "mic_off":
            ctx.glyph.text = "󰍭"; ctx.label.text = "Microphone Off"; ctx.root.showPill = false
            break
        case "vnc_on":
            ctx.glyph.text = "󰢹"; ctx.label.text = "VNC Server Enabled"; ctx.root.showPill = false
            break
        case "vnc_off":
            ctx.glyph.text = "󰢾"; ctx.label.text = "VNC Server Disabled"; ctx.root.showPill = false
            break
        default:
            ctx.glyph.text = "󰋼"; ctx.label.text = kind; ctx.root.showPill = false
            break
    }
}
