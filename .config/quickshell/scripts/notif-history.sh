#!/usr/bin/env bash
dunstctl history 2>/dev/null | python3 -c "
import json, sys, os
try:
    data = json.load(sys.stdin)
    entries = data.get('data', [[]])[0][:20]
    result = []
    os.makedirs('/tmp/quickshell-notifs', exist_ok=True)
    for e in entries:
        summary = e.get('summary', {}).get('data', 'No title')
        body    = e.get('body',    {}).get('data', '')
        app     = e.get('appname',{}).get('data', '')
        nid     = str(e.get('id', {}).get('data', ''))
        title   = f'{app}: {summary}' if app else summary
        full    = f'{app}: {summary}\n{body}' if body else title
        with open(f'/tmp/quickshell-notifs/{nid}', 'w') as f:
            f.write(full)
        result.append({'title': title, 'body': body, 'hash': nid})
    if not result:
        result = [{'title': 'No notifications', 'body': '', 'hash': ''}]
    print(json.dumps(result))
except Exception as ex:
    print(json.dumps([{'title': 'No notifications', 'body': '', 'hash': ''}]))
"
