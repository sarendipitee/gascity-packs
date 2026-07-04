#!/bin/sh
# tmux-scroll.sh — LazyJJ tmux scrollback bindings.
# Usage: tmux-scroll.sh <session>
SESSION="$1"
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PACK_DIR=$(dirname "$(dirname "$SCRIPT_DIR")")
SHARED_SCRIPT="$PACK_DIR/../gastown/assets/scripts/tmux-keybindings.sh"
SHARED_CONFIG="$PACK_DIR/../gastown"

gcmux() { tmux ${GC_TMUX_SOCKET:+-L "$GC_TMUX_SOCKET"} "$@"; }

if [ -x "$SHARED_SCRIPT" ]; then
    exec "$SHARED_SCRIPT" "$SHARED_CONFIG" "$SESSION"
fi

if [ -n "$SESSION" ]; then
    gcmux set-option -t "$SESSION" mouse on
    gcmux set-option -t "$SESSION" history-limit 50000
else
    gcmux set-option -g mouse on
    gcmux set-option -g history-limit 50000
fi

# Trackpad scroll gestures arrive at tmux as WheelUpPane/WheelDownPane.
# Force tmux copy-mode scrollback instead of passing gestures into Codex.
gcmux bind-key -T root WheelUpPane if-shell -F -t= "#{pane_in_mode}" "send-keys -M" "copy-mode -e"
gcmux bind-key -T root WheelDownPane send-keys -M
