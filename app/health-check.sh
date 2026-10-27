#!/bin/bash

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIAG="$DIR/diagnostic.sh"

unhealthy() { echo "unhealthy: $1" >&2; exit 1; }

[ -r "$DIAG" ]                         || unhealthy "diagnostic.sh is missing or unreadable"
bash "$DIAG" help >/dev/null 2>&1      || unhealthy "'diagnostic help' failed"
[ -r /proc/meminfo ] && [ -r /proc/uptime ] || unhealthy "/proc is not readable"

for tool in df getent ping nc; do
    command -v "$tool" >/dev/null 2>&1 || unhealthy "required tool missing: $tool"
done

echo "healthy"
exit 0

