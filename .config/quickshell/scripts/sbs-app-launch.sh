#!/usr/bin/env bash
# Launch an app from its .desktop file path (used by SBSApplicationsPanel,
# which reads name/path pairs straight out of the existing
# icons/.app_cache.tsv built by shortcuts-add.sh rather than re-scanning).
DESKTOP_PATH="$1"
[ -z "$DESKTOP_PATH" ] && exit 1
[ ! -f "$DESKTOP_PATH" ] && exit 1

EXEC=$(grep -m1 "^Exec=" "$DESKTOP_PATH" | cut -d= -f2- | sed 's/ %[a-zA-Z]//g')
[ -z "$EXEC" ] && exit 1

nohup bash -c "$EXEC" >/dev/null 2>&1 &
