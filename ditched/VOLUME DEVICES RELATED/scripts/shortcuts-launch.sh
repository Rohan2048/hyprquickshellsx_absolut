#!/usr/bin/env bash
EXEC=$(echo "$1" | sed 's/ @@[^ ]*//g' | sed 's/@@u//g' | xargs)
nohup bash -c "$EXEC" >/dev/null 2>&1 &
