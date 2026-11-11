#!/usr/bin/env bash
CMD="$1"
TERMINAL="$2"
[ -z "$CMD" ] && exit 1

if [ "$TERMINAL" = "true" ]; then
    DEFAULT_TERM=$(gsettings get org.gnome.desktop.default-applications.terminal exec 2>/dev/null | tr -d "'")
    DEFAULT_SHELL=$(basename "$SHELL")

    case "$DEFAULT_SHELL" in
        fish) SHELL_CMD="fish -c 'commandline -i $(printf '%q' "$CMD"); exec fish'" ;;
        zsh)  SHELL_CMD="zsh -c 'print -z $(printf '%q' "$CMD"); exec zsh'" ;;
        *)    SHELL_CMD="bash -c 'read -e -i $(printf '%q' "$CMD") -p \"\$ \" CMD2; eval \"\$CMD2\"; exec bash'" ;;
    esac

    for TERM_EMU in "$DEFAULT_TERM" "$TERMINAL_EMULATOR" konsole kitty alacritty wezterm foot xterm; do
        [ -z "$TERM_EMU" ] && continue
        if command -v "$TERM_EMU" &>/dev/null; then
            case "$TERM_EMU" in
                konsole)
                    konsole --workdir ~ -e bash -c "$SHELL_CMD" &;;
                kitty)
                    kitty --directory ~ bash -c "$SHELL_CMD" &;;
                alacritty)
                    alacritty --working-directory ~ -e bash -c "$SHELL_CMD" &;;
                wezterm)
                    wezterm start --cwd ~ -- bash -c "$SHELL_CMD" &;;
                foot)
                    foot --working-directory=~ bash -c "$SHELL_CMD" &;;
                xterm)
                    xterm -e bash -c "$SHELL_CMD" &;;
                *)
                    QUOTED=$(printf '%q' "$CMD")
                    "$TERM_EMU" -e bash -c "read -e -i $QUOTED -p '\$ ' CMD2; eval \"\$CMD2\"; exec bash" &;;
            esac
            break
        fi
    done

else
    bash -c "$CMD" &
fi
