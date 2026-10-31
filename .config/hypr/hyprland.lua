-- Hyprland 0.55 Lua Configuration
-- https://wiki.hypr.land/Configuring/Start/

--------------------
---- MONITORS ----
--------------------

hl.monitor({
    output   = "",
    mode     = "preferred",
    position = "auto",
    scale    = "auto",
})

---------------------
---- MY PROGRAMS ----
---------------------

local terminal    = "konsole"
local fileManager = "dolphin"
-- Goes through launcher.sh so Quickshell > Settings > Popups > Applications can pick Rofi or the in-shell launcher.
local menu        = "bash ~/.config/quickshell/scripts/launcher.sh"
local mainMod     = "SUPER"

-------------------------------
---- SUPER BATTERY SAVER ----
-------------------------------
-- Reads the same state file SBS/SBSState.qml owns and writes to
-- (~/.config/quickshell/state/sbs-mode.json, written as
-- JSON.stringify({ active }, null, 2)). No JSON lib available in this
-- Lua environment, so this is a plain substring match rather than a
-- real parse -- safe here only because SBSState.qml is the sole writer
-- of this file and its output shape is fixed.
local function sbsModeActive()
local f = io.open(os.getenv("HOME") .. "/.config/quickshell/state/sbs-mode.json", "r")
if not f then return false end
    local content = f:read("*a")
    f:close()
    return content:find('"active"%s*:%s*true') ~= nil
    end
    local sbsMode = sbsModeActive()

    --------------------
    ---- LAYER RULES ----
    --------------------

    hl.layer_rule({ match = { namespace = "eww"              }, blur = true })
    hl.layer_rule({ match = { namespace = "quickshell:.*" }, blur = true })
    hl.layer_rule({ match = { namespace = "quickshell:.*" }, ignore_alpha = 0.1 })
    hl.layer_rule({ match = { namespace = "volume-popup" },  ignore_alpha = 0.1 })
    -- hl.layer_rule({ match = { namespace = "bar" },  ignore_alpha = 0.05 })
    hl.layer_rule({ match = { namespace = "gtk-layer-shell"  }, blur = true })
    hl.layer_rule({
        match       = { namespace = "rofi" },
        blur        = true,
        ignore_alpha = 0.1,
        animation   = "popin 70%",
    })
    hl.layer_rule({ match = { namespace = "notifications"    }, blur = true })
    -- hl.layer_rule({ match = { namespace = "quickshell:screenshot" }, blur = true })
    hl.layer_rule({ match = { namespace = "quickshell:commands" }, blur = true, ignore_alpha = 0.05 })
    hl.layer_rule({ match = { namespace = "quickshell:screenshot-noblur" }, blur = false, animation = "false" })
    hl.layer_rule({ match = { namespace = "volume-popup"     }, blur = true })
    hl.layer_rule({ match = { namespace = "brightness-popup" }, blur = true })
    hl.layer_rule({ match = { namespace = "bt-popup"         }, blur = true })
    hl.layer_rule({ match = { namespace = "wifi-popup"       }, blur = true })
    hl.layer_rule({ match = { namespace = "bar-window" }, blur = true, ignore_alpha = 0.1, animation = "false" })
    hl.layer_rule({
        match = { namespace = "bar-trigger" },
        animation = "false",
    })
    hl.layer_rule({
        match = { namespace = "quickshell:popup:battery" },
        blur = true,
        ignore_alpha = 0.1,
        animation = "false",
    })
    hl.layer_rule({
        match = { namespace = "quickshell:screenshot" },
        blur = true,
        ignore_alpha = 0.4,
        animation = "false",
        --     xray = true,
    })
    hl.layer_rule({
        match = { namespace = "quickshell:settings" },
        blur = true,
        ignore_alpha = 0.1,
        animation = "false",
    })
    hl.layer_rule({
        match = { namespace = "quickshell:screenshot-preview" },
        blur = true,
        ignore_alpha = 0.1,
        animation = "false",
        --     xray = true,
    })
    hl.layer_rule({
        match = { namespace = "quickshell:taskbar-thumb" },
        blur = true,
        ignore_alpha = 0.05,
        animation = "false"
    })
    hl.layer_rule({
        match = { namespace = "quickshell:musicPicker" },
        blur = true,
        ignore_alpha = 0.05,
        animation = "false"
    })
    hl.layer_rule({
        match = { namespace = "quickshell:screenshot-fontbrowser" },
        blur = true,
        ignore_alpha = 0.4,
    })
    hl.layer_rule({
        match = { namespace = "osd-popup" },
        blur = true,
        ignore_alpha = 0.1,
        animation = "false",
    })
    hl.layer_rule({
        match = { namespace = "quickshell:screenshot-saveas" },
        blur = true,
        ignore_alpha = 0.4,
    })
    hl.layer_rule({
        match = { namespace = "quickshell:popup:wifi" },
        blur = true,
        ignore_alpha = 0.1,
        animation = "false",
    })
    hl.layer_rule({
        match = { namespace = "quickshell:wallpaper" },
        animation = "false",
    })
    -- hl.layer_rule({
    --     match = { namespace = "quickshell:videowallpaper" },
--     animation = "false",
-- })
hl.layer_rule({
    match = { namespace = "quickshell:fontPicker" },
    blur = true,
    ignore_alpha = 0.05,
    animation = "false",
})
hl.layer_rule({
    match = { namespace = "quickshell:popup:notifications" },
    blur = true,
    ignore_alpha = 0.1,
    animation = "false",
})
hl.layer_rule({
    match = { namespace = "quickshell:musicPopup" },
    blur = true,
    ignore_alpha = 0.1,
    animation = "false",
})
hl.layer_rule({
    match = { namespace = "volume-popup" },
    blur = true,
    ignore_alpha = 0.1,
    animation = "false",
})
hl.layer_rule({
    match = { namespace = "quickshell:popup:bluetooth" },
    blur = true,
    ignore_alpha = 0.1,
    animation = "false",
})
-- hl.layer_rule({ match = { namespace = "top-bar-window"   }, blur = true, ignore_alpha = 0.05 })
hl.layer_rule({ match = { namespace = "battery-popup"    }, blur = true, ignore_alpha = 0.05 })
hl.layer_rule({ match = { namespace = "shortcuts-window" }, blur = true, ignore_alpha = 0.1  })
hl.layer_rule({ match = { namespace = "commands-window"  }, blur = true, ignore_alpha = 0.05  })
hl.layer_rule({ match = { namespace = "music-popup"      }, blur = true, ignore_alpha = 0.1,
              animation = "false" })
hl.layer_rule({
    match = { namespace = "datetime-popup" },
    blur = true,
    ignore_alpha = 0.1,
    animation = "false",
})
-- hl.layer_rule({
--     match = { namespace = "quickshell:popup:applications" },
--     blur = true,
--     ignore_alpha = 0.1,
--     animation = "false",
-- })
hl.layer_rule({
    match = { namespace = "quickshell:toast" },
    blur = true,
    ignore_alpha = 0.4,
    animation = "false",
})
hl.layer_rule({ match = { namespace = "selection"        }, no_anim = true })
hl.layer_rule({ match = { namespace = "hyprlock" }, animation = "slide top" })

hl.layer_rule({ match = { namespace = "quickshell:sbs" }, animation = "false" })
hl.layer_rule({ match = { namespace = "quickshell:sbs-osd" }, animation = "false" })

-------------------
---- AUTOSTART ----
-------------------

hl.on("hyprland.start", function()
hl.exec_cmd("~/.config/hypr/preload.sh &")
hl.exec_cmd("~/.config/hypr/shellwrapper.sh")
hl.exec_cmd("~/.config/hypr/volume-osd --daemon &")
-- hl.exec_cmd("dunst")
-- hl.exec_cmd("~/.config/hypr/autoplay.sh")
-- hl.exec_cmd("pkill cava; rm -f /tmp/cava.fifo; mkfifo /tmp/cava.fifo; cava -p ~/.config/cava/config")
hl.exec_cmd("sleep 5; python3 ~/.config/quickshell/scripts/sound-devices.py restore &")
hl.exec_cmd("kdeconnectd")
hl.exec_cmd("kded")
hl.exec_cmd("kglobalaccel6")
hl.exec_cmd("/usr/lib/kdeconnectd")
hl.exec_cmd("kdeconnect-indicator")
hl.exec_cmd("bash ~/.config/hypr/lock-before-suspend.sh &")

-- hl.exec_cmd("playerctld daemon")
-- hl.exec_cmd("bash ~/.config/eww/popup-monitor.sh")
-- hl.exec_cmd("bash ~/.config/eww/player-daemon.sh")
-- hl.exec_cmd("bash ~/.config/eww/player-start.sh")
-- hyprexpo plugin config (set after plugin loads)
-- hl.exec_cmd("hyprctl keyword plugin:hyprexpo:columns 3")
-- hl.exec_cmd("hyprctl keyword plugin:hyprexpo:gap_size 5")
-- hl.exec_cmd("hyprctl keyword plugin:hyprexpo:bg_col 'rgb(111111)'")
-- hl.exec_cmd("hyprctl keyword plugin:hyprexpo:workspace_method 'center current'")
-- hl.exec_cmd("hyprctl keyword plugin:hyprexpo:enable_gesture false")
-- hl.exec_cmd("hyprctl keyword plugin:hyprexpo:gesture_distance 300")
end)

-- ── Cursor ────────────────────────────────────────────────────────────────
-- Cursor theme and size come from Quickshell Settings > Cursor (state/cursor-theme.txt, "<theme><TAB><size>").
-- Nothing chosen yet = Bibata at 20.
local cursor_theme, cursor_size = "Bibata-Modern-Classic", "20"
do
    local f = io.open((os.getenv("HOME") or "") .. "/.config/quickshell/state/cursor-theme.txt", "r")
    if f then
        local line = f:read("l")
        f:close()
        local t, sz = (line or ""):match("^([^\t]+)\t?(%d*)")
        if t and t ~= "" then cursor_theme = t end
            if sz and sz ~= "" then cursor_size = sz end
                end
                end
                hl.env("XCURSOR_SIZE",                        cursor_size)
                hl.env("XCURSOR_THEME",                       cursor_theme)
                hl.env("HYPRCURSOR_SIZE",                     cursor_size)

                -- ── Qt / Electron ─────────────────────────────────────────────────────────
                hl.env("QT_QPA_PLATFORM",                     "wayland")
                hl.env("QT_QPA_PLATFORMTHEME",                "kde")
                hl.env("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1")
                hl.env("ELECTRON_OZONE_PLATFORM_HINT",        "auto")

                -- ── Intel rendering ───────────────────────────────────────────────────────
                hl.env("__GL_THREADED_OPTIMIZATIONS",         "1")
                hl.env("mesa_glthread",                       "true")
                hl.env("LIBGL_DRI3_DISABLE",                  "0")
                hl.env("ANV_QUEUE_THREAD_DISABLE",            "0")
                -- hl.env("WAYLAND_DISABLE_FRACTIONAL_SCALE,      1")
                -- ── AMD rendering (swap with Intel block if on AMD) ───────────────────────
                -- hl.env("mesa_glthread",                    "true")
                -- hl.env("RADV_PERFTEST",                    "aco,rt")
                -- hl.env("AMD_VULKAN_ICD",                   "RADV")
                -- hl.env("WLR_RENDERER",                     "vulkan")  -- test first, may break screenshare

                -- ── Wayland / wlroots ─────────────────────────────────────────────────────
                hl.env("WLR_DRM_NO_ATOMIC",                   "1")

                -----------------------
                ----- PERMISSIONS -----
                -----------------------

                hl.permission("/usr/(bin|local/bin)/hyprpm", "plugin", "allow")

                -----------------------
                ---- LOOK AND FEEL ----
                -----------------------

                hl.config({
                    xwayland = {
                        force_zero_scaling = true,
                    },
                    cursor = {
                        no_warps = true
                    },
                    misc = {
                        force_default_wallpaper = 0,
                            disable_hyprland_logo   = true,
                    },

                    general = {
                        gaps_in          = 0,
                        gaps_out         = 0,
                        border_size      = 2,
                        resize_on_border = true,
                        allow_tearing    = true,
                        layout           = "dwindle",
                    },

                    decoration = {
                        rounding         = 10,
                        rounding_power   = 2,
                        active_opacity   = 1.0,
                        inactive_opacity = 0.75,

                        --        dim_inactive = true,
                        --        dim_strength = 0.08,

                        shadow = {
                            enabled        = true,
                            range          = 20,
                            render_power   = 2,
                            --          color          = "rgba(0,0,0,0.4)",
                          --          color_inactive = "rgba(0,0,0,0.2)",
                        },

                        blur = {
                            enabled           = true,
                            size              = 4,        -- was 6
                            passes            = 3,        -- was 3
                            noise             = 0.02,
                            contrast          = 0.9,      -- was 0.9 - disabled, one less multiply per pixel per pass
                            brightness        = 0.8,      -- was 0.85 - disabled, same reason
                            vibrancy          = 0.2,        -- was 0.20 - disabled
                            vibrancy_darkness = 0.5,
                            special           = true,
                            popups            = true,
                            new_optimizations = true,
                            ignore_opacity    = true,
                            --             xray              =true,
                        },
                    },

                    animations = {
                        enabled = true,
                    },

                    dwindle = {
                        preserve_split = true,
                    },

                    master = {
                        new_status = "master",
                    },

                    input = {
                        kb_layout    = "us",
                        follow_mouse = 1,
                        sensitivity  = 0,
                        touchpad = {
                            natural_scroll = false,
                        },
                    },
                })

                -- SOURCE: ~/.cache/wal/hyprland-colours.conf
                dofile(os.getenv("HOME") .. "/.cache/wal/hyprland-colours.lua")

                ----------------------
                ---- BEZIER CURVES ----
                ----------------------

                -- Snappy deceleration — windows land fast and crisp
                hl.curve("snap",          { type = "bezier", points = { {0.13, 0.99}, {0.22, 1.0}  } })
                -- Smooth ease for fades and layers
                hl.curve("easeOutQuint",  { type = "bezier", points = { {0.23, 1},    {0.32, 1}    } })
                -- Slightly overshooting — the "bouncy" feel
                hl.curve("overshot",      { type = "bezier", points = { {0.05, 0.9},  {0.1,  1.05} } })
                -- Elastic exit for windows closing/leaving
                hl.curve("easeInBack",    { type = "bezier", points = { {0.36, 0},    {0.66, -0.56}} })
                -- Quick linear-ish ramp for things that need no personality
                hl.curve("linear",        { type = "bezier", points = { {0, 0},       {1, 1}       } })
                hl.curve("almostLinear",  { type = "bezier", points = { {0.5, 0.5},   {0.75, 1}    } })
                hl.curve("quick",         { type = "bezier", points = { {0.15, 0},    {0.1, 1}     } })
                -- Smooth cubic for layer transitions
                hl.curve("easeInOutCubic",{ type = "bezier", points = { {0.65, 0.05}, {0.36, 1}    } })

                --------------------
                ---- ANIMATIONS ----
                --------------------

                -- Global master switch
                hl.animation({ leaf = "global",        enabled = true,  speed = 7,    bezier = "default" })
                -- Borders — snappy colour transitions
                hl.animation({ leaf = "border",        enabled = true,  speed = 5.5,  bezier = "snap" })

                -- Windows — snappy in, clean out with slight pop
                hl.animation({ leaf = "windows",       enabled = true,  speed = 3.5,  bezier = "snap" })
                hl.animation({ leaf = "windowsIn",     enabled = true,  speed = 3.2,  bezier = "overshot",  style = "popin 85%" })
                hl.animation({ leaf = "windowsOut",    enabled = true,  speed = 1.9,  bezier = "easeInBack",style = "popin 85%" })
                --hl.animation({ leaf = "windowsMove",   enabled = true,  speed = 3.5,  bezier = "overshot" })

                -- Fades — smooth, not sluggish
                hl.animation({ leaf = "fadeIn",        enabled = true,  speed = 2.5,  bezier = "easeOutQuint" })
                hl.animation({ leaf = "fadeOut",       enabled = true,  speed = 2.5,  bezier = "easeInOutCubic" })
                hl.animation({ leaf = "fade",          enabled = true,  speed = 2.5,  bezier = "quick" })
                --hl.animation({ leaf = "fadeDim",       enabled = true,  speed = 2.5,  bezier = "quick" })

                -- Layers (eww popups etc.) — bouncy slide in, quick out
                hl.animation({ leaf = "layersIn",      enabled = true,  speed = 3.2,  bezier = "overshot",      style = "slide" })
                hl.animation({ leaf = "layersOut",     enabled = true,  speed = 2.2,  bezier = "easeInOutCubic",style = "slide" })
                hl.animation({ leaf = "fadeLayersIn",  enabled = true,  speed = 2.0,  bezier = "almostLinear" })
                hl.animation({ leaf = "fadeLayersOut", enabled = true,  speed = 1.4,  bezier = "almostLinear" })

                -- Workspaces — fast fade, feels snappy without being jarring
                hl.animation({ leaf = "workspaces",    enabled = true,  speed = 2.2,  bezier = "snap",      style = "fade" })
                hl.animation({ leaf = "workspacesIn",  enabled = true,  speed = 1.4,  bezier = "snap",      style = "fade" })
                hl.animation({ leaf = "workspacesOut", enabled = true,  speed = 2.0,  bezier = "almostLinear", style = "fade" })

                ------------------------
                ---- WORKSPACE RULES ----
                ------------------------

                hl.workspace_rule({ workspace = "w[tv1]", gaps_out = 0, gaps_in = 0 })
                hl.workspace_rule({ workspace = "f[1]",   gaps_out = 0, gaps_in = 0 })

                -----------------------
                ---- WINDOW RULES ----
                -----------------------

                -- No borders/rounding on tiled windows in single-window or fullscreen workspaces
                hl.window_rule({
                    match       = { float = false, workspace = "w[tv1]" },
                    border_size = 0,
                    rounding    = 0,
                })
                hl.window_rule({
                    match       = { float = false, workspace = "f[1]" },
                    border_size = 0,
                    rounding    = 0,
                })

                -- Suppress maximize events
                hl.window_rule({
                    match          = { class = ".*" },
                    suppress_event = "maximize",
                })

                -- Ignore phantom xwayland popups
                hl.window_rule({
                    match    = { class = "^$", title = "^$", xwayland = true,
                        float = true, fullscreen = false, pin = false },
                        no_focus = true,
                })

                -- Dunst opacity
                hl.window_rule({
                    match   = { class = "^dunst$" },
                    opacity = "0.45 0.45",
                })

                -- In hyprland.lua
                hl.window_rule({
                    match = { class = "eww-calendar" },
                    animation = "popin 80%",
                    float = true,
                })


                --------------
                -- RULES------
                --------------

                -- Prevent the popup from stealing focus when it opens.
                -- This allows workspace clicks to pass through to the window beneath it.
                -- 1. Prevent the popup from stealing focus when it spawns.
                hl.window_rule({
                    name = "volume-popup-no-focus",
                    match = {
                        class = "quickshell",       -- IMPORTANT: Run `hyprctl clients` in terminal to get your exact class
                        title = "VolumePopup"       -- IMPORTANT: Run `hyprctl clients` to get your exact title
                    },
                    float = true,
                    no_initial_focus = true,        -- CRITICAL: Keeps focus on the background window
                })

                -- 2. Listen for focus changes. If the popup loses focus, close it.
                hl.on("window.active", function(active_win, focus_reason)
                -- If the popup itself just gained focus (e.g., you clicked inside it), do nothing.
                if active_win and active_win.class == "quickshell" and active_win.title == "VolumePopup" then
                    return
                    end

                    -- Otherwise, the user clicked outside. Find the popup and close it.
                    for _, win in ipairs(hl.get_windows()) do
                        if win.class == "quickshell" and win.title == "VolumePopup" then
                            hl.dsp.closewindow(win.address)
                            break
                            end
                            end
                            end)


                --------------------
                ---- PLUGINS ----
                --------------------

                ------------------
                ---- GESTURES ----
                ------------------

                hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })
                hl.gesture({ fingers = 3, direction = "down",       modifiers = "ALT", action = "close" })

                --------------------
                ---- KEYBINDINGS ----
                --------------------
                -- Rebindable from Quickshell: Settings -> Keybindings.
                -- Every rebindable bind is   bindk(id, default combo, dispatcher [, opts])
                -- Changed keys are written by Quickshell to
                --   ~/.config/quickshell/state/keybinds.lua   (generated, do not edit by hand)
                -- as   return { ["lock"] = "SUPER + ALT + L", ["touchpad"] = "" }   ("" = unbound).
                -- A missing file / id simply means "use the default written here".
                -- ids and defaults must match quickshell/Services/Keybinds.qml.
                -- Volume, brightness and the mouse drag/resize binds are plain hl.bind lines.

                local overrides = {}
                do
                    local ok, t = pcall(dofile, os.getenv("HOME") .. "/.config/quickshell/state/keybinds.lua")
                    if ok and type(t) == "table" then overrides = t end
                        end

                        local function combo(id, default)
                        local c = overrides[id]
                        if c == nil then c = default end
                            return c
                            end

                            local function bindk(id, default, dispatcher, opts)
                            local c = combo(id, default)
                            if c == "" then return end
                                if opts then hl.bind(c, dispatcher, opts) else hl.bind(c, dispatcher) end
                                    end

                                    -- Shell
                                    bindk("toggle_bar", "SUPER + SHIFT + T", hl.dsp.exec_cmd("~/.config/hypr/toggle-bar.sh"))

                                    if not sbsMode then
                                        bindk("settings",    "SUPER + SHIFT + A", hl.dsp.exec_cmd("qs ipc call settings toggle"))
                                        bindk("commands",    "SUPER + A",         hl.dsp.exec_cmd("qs ipc call commands toggle"))
                                        bindk("shortcuts",   "SUPER + W",         hl.dsp.exec_cmd("qs ipc call shortcuts toggle"))
                                        --                         bindk("font_picker", "SUPER + SHIFT + F", hl.dsp.exec_cmd("qs ipc call fontPicker toggle"))
                                        bindk("rofi_anim",   "ALT + R",           hl.dsp.exec_cmd("bash ~/.config/quickshell/scripts/rofi-animation-scale.sh"))
                                        end
                                        if sbsMode then
                                            bindk("sbs_hide", "CTRL + H", hl.dsp.exec_cmd("qs ipc call sbs toggleHide"))
                                            end

                                            bindk("music_picker", "SUPER + T", hl.dsp.exec_cmd("qs ipc call musicPicker toggle"))
                                            bindk("screenshot",   "SUPER + S", hl.dsp.exec_cmd("qs ipc call screenshot capture"))
                                            bindk("lock",         "SUPER + L", hl.dsp.exec_cmd("qs ipc call lock lock"))

                                            -- Workspace overview: toggle on the combo, confirm when its (first) modifier is released.
                                            do
                                                local modRelease = { SUPER = "SUPER_L", ALT = "ALT_L", CTRL = "CONTROL_L", CONTROL = "CONTROL_L", SHIFT = "SHIFT_L" }
                                                local c = combo("overview", "ALT + Tab")
                                                if c ~= "" then
                                                    hl.bind(c, hl.dsp.global("quickshell:workspaceOverviewToggle"))
                                                    local first = c:match("^%s*(%a+)")
                                                    local rel = first and modRelease[first:upper()]
                                                    if rel and c:find("+", 1, true) then
                                                        hl.bind(rel, hl.dsp.global("quickshell:workspaceOverviewConfirm"), { release = true })
                                                        end
                                                        end
                                                        end

                                                        -- Apps
                                                        bindk("terminal",  "SUPER + Q", hl.dsp.exec_cmd(terminal))
                                                        bindk("files",     "SUPER + E", hl.dsp.exec_cmd(fileManager))
                                                        if not sbsMode then
                                                            bindk("launcher", "SUPER + R", hl.dsp.exec_cmd(menu))
                                                            end
                                                            bindk("clipboard", "SUPER + P", hl.dsp.exec_cmd("bash ~/.config/quickshell/scripts/clipboard.sh"))

                                                            -- System
                                                            bindk("powermenu",    "SUPER + escape",         hl.dsp.exec_cmd("~/.config/rofi/powermenu.sh"))
                                                            bindk("schedule",     "SUPER + SHIFT + escape", hl.dsp.exec_cmd("~/.config/hypr/schedule_action.sh"))
                                                            bindk("touchpad",     "ALT + M",                hl.dsp.exec_cmd("bash ~/.config/hypr/toggle_touchpad.sh"))
                                                            bindk("hdmi",         "ALT + S",                hl.dsp.exec_cmd("~/.config/hypr/hdmi.sh"))
                                                            bindk("hdmi_refresh", "ALT + SHIFT + S",        hl.dsp.exec_cmd("~/.config/hypr/hdmi-refresh.sh"))
                                                            bindk("vnc",          "ALT + V",                hl.dsp.exec_cmd("~/.config/hypr/vnc.sh"))
                                                            if not sbsMode then
                                                                bindk("wallpaper", "SUPER + SHIFT + W", hl.dsp.exec_cmd("~/.config/hypr/wallpaper_switcher.sh"))
                                                                end
                                                                --                                                 bindk("video_wallpaper", "SUPER + SHIFT + V", hl.dsp.exec_cmd("~/.config/hypr/video-wallpaper-selector.sh"))

                                                                -- Media
                                                                bindk("player_next", "ALT + N", hl.dsp.exec_cmd('playerctl --ignore-player=kdeconnect next'),     { locked = true })
                                                                bindk("player_prev", "ALT + P", hl.dsp.exec_cmd('playerctl --ignore-player=kdeconnect previous'), { locked = true })
                                                                bindk("media_next",  "XF86AudioNext",  hl.dsp.exec_cmd('playerctl --player="%any,!kdeconnect" next'),       { locked = true })
                                                                bindk("media_pause", "XF86AudioPause", hl.dsp.exec_cmd('playerctl --player="%any,!kdeconnect" play-pause'), { locked = true })
                                                                bindk("media_play",  "XF86AudioPlay",  hl.dsp.exec_cmd('playerctl --player="%any,!kdeconnect" play-pause'), { locked = true })
                                                                bindk("media_prev",  "XF86AudioPrev",  hl.dsp.exec_cmd('playerctl --player="%any,!kdeconnect" previous'),   { locked = true })

                                                                -- Window management
                                                                bindk("close",      "SUPER + C",         hl.dsp.window.close())
                                                                bindk("float",      "SUPER + V",         hl.dsp.window.float({ action = "toggle" }))
                                                                bindk("split",      "SUPER + J",         hl.dsp.layout("togglesplit"))
                                                                bindk("fullscreen", "SUPER + F",         hl.dsp.window.fullscreen({ mode = 0 }))
                                                                bindk("maximize",   "SUPER + SHIFT + F", hl.dsp.window.fullscreen({ mode = 1 }))

                                                                -- Minimize to special workspace
                                                                bindk("minimize",       "SUPER + N",         hl.dsp.window.move({ workspace = "special:minimized" }))
                                                                bindk("show_minimized", "SUPER + SHIFT + N", hl.dsp.workspace.toggle_special("minimized"))

                                                                -- Focus movement
                                                                bindk("focus_left",  "SUPER + left",  hl.dsp.focus({ direction = "left" }))
                                                                bindk("focus_right", "SUPER + right", hl.dsp.focus({ direction = "right" }))
                                                                bindk("focus_up",    "SUPER + up",    hl.dsp.focus({ direction = "up" }))
                                                                bindk("focus_down",  "SUPER + down",  hl.dsp.focus({ direction = "down" }))

                                                                -- Workspace switching (the modifier is rebindable; keys 1..0 are fixed)
                                                                do
                                                                    local goMod   = combo("ws_goto", "SUPER")
                                                                    local moveMod = combo("ws_move", "SUPER + SHIFT")
                                                                    for i = 1, 10 do
                                                                        local key = i % 10  -- 10 maps to key 0
                                                                        if goMod ~= ""   then hl.bind(goMod   .. " + " .. key, hl.dsp.focus({ workspace = i })) end
                                                                            if moveMod ~= "" then hl.bind(moveMod .. " + " .. key, hl.dsp.window.move({ workspace = i })) end
                                                                                end
                                                                                end

                                                                                -- Mouse window management (not rebindable from Settings)
                                                                                hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
                                                                                hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

                                                                                --- Volume (not rebindable from Settings)
                                                                                hl.bind(
                                                                                    "XF86AudioRaiseVolume",
                                                                                    hl.dsp.exec_cmd(os.getenv("HOME") .. "/.config/hypr/volume-osd up"),
                                                                                        { repeating = true }
                                                                                )

                                                                                hl.bind(
                                                                                    "XF86AudioLowerVolume",
                                                                                    hl.dsp.exec_cmd(os.getenv("HOME") .. "/.config/hypr/volume-osd down"),
                                                                                        { repeating = true }
                                                                                )

                                                                                hl.bind(
                                                                                    "XF86AudioMute",
                                                                                    hl.dsp.exec_cmd(os.getenv("HOME") .. "/.config/hypr/volume-osd mute")
                                                                                )

                                                                                hl.bind(
                                                                                    "XF86AudioMicMute",
                                                                                    hl.dsp.exec_cmd(os.getenv("HOME") .. "/.config/hypr/volume-osd micmute")
                                                                                )

                                                                                hl.bind(
                                                                                    "F4",
                                                                                    hl.dsp.exec_cmd(os.getenv("HOME") .. "/.config/hypr/volume-osd micmute")
                                                                                )

                                                                                --- Brightness (not rebindable from Settings)
                                                                                hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd(
                                                                                    'brightnessctl -e4 -n2 set 5%+ && qs msg osd show brightness "$(brightnessctl -m | cut -d, -f4 | tr -d %)"'
                                                                                ), { repeating = true })
                                                                                hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd(
                                                                                    'brightnessctl -e4 -n2 set 5%- && qs msg osd show brightness "$(brightnessctl -m | cut -d, -f4 | tr -d %)"'
                                                                                ), { repeating = true })
