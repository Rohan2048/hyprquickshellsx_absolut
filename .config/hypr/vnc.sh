#VNC SERVER(INSTALL IF HAVEN'T DONE YET):
#sudo dnf install wayvnc
#Normally,
#killall wayvnc 2>/dev/null
#wayvnc --render-cursor 0.0.0.0 5900 &

#!/bin/bash
if pgrep -x wayvnc > /dev/null; then
    killall wayvnc
    qs msg osd show vnc_off 0
else
    wayvnc --render-cursor 0.0.0.0 5900 &
    qs msg osd show vnc_on 0
fi
