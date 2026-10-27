#!/bin/bash

PROG="diagnostic"

usage() {
    cat << USAGE_TEXT
Usage: $PROG <command> [arguments]

Commands:
  system             Display system information (OS, kernel, uptime, CPU, memory)
  network <host>     Check a host: DNS resolution, ping and TCP ports 80/443
  disk               Display disk and inode usage
  help               Show this help

Exit codes:
  0   success
  1   a check failed (for example, the host is unreachable)
  2   invalid command, or missing/invalid arguments

Examples:
  $PROG system
  $PROG network example.com
  $PROG disk
USAGE_TEXT
}

# Print an error and exit 2 (invalid usage).
die_usage() {
    echo "Error: $1" >&2
    echo "Run '$PROG help' for usage." >&2
    exit 2
}

section() { printf '\n=== %s ===\n' "$1"; }
row()     { printf '%-18s : %s\n' "$1" "$2"; }

fmt_duration() {   # seconds -> "Xd Yh Zm"
    local s=$1
    printf '%dd %dh %dm' $((s/86400)) $((s%86400/3600)) $((s%3600/60))
}

# ----------------------------- system -----------------------------
cmd_system() {
    [ $# -eq 0 ] || die_usage "'system' takes no arguments."

    local os="$(uname -s)" up="Unavailable" cpu="Unavailable" cores="Unavailable"
    local load="Unavailable" mem_total="Unavailable" mem_used="Unavailable" mem_avail="Unavailable"
    local container="no"

    if [ -r /etc/os-release ]; then
        os="$(. /etc/os-release && echo "${PRETTY_NAME:-${NAME:-$os}}")"
    fi
    if [ -r /proc/uptime ]; then
        up="$(fmt_duration "$(cut -d. -f1 /proc/uptime)")"
    fi
    if [ -r /proc/cpuinfo ]; then
        cpu="$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2- | sed 's/^ *//')"
        [ -n "$cpu" ] || cpu="Unavailable"
    fi
    cores="$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo Unavailable)"
    if [ -r /proc/loadavg ]; then
        load="$(cut -d' ' -f1-3 /proc/loadavg)"
    fi
    if [ -r /proc/meminfo ]; then
        local total_kb avail_kb
        total_kb="$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)"
        avail_kb="$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)"
        if [ -n "$total_kb" ] && [ -n "$avail_kb" ]; then
            local used_kb=$((total_kb - avail_kb))
            mem_total="$((total_kb/1024)) MiB"
            mem_used="$((used_kb/1024)) MiB ($((used_kb*100/total_kb))%)"
            mem_avail="$((avail_kb/1024)) MiB"
        fi
    fi
    if [ -f /.dockerenv ] || grep -qaE 'docker|containerd|kubepods' /proc/1/cgroup 2>/dev/null; then
        container="yes"
    fi

    section "System information"
    row "Hostname"          "$(hostname)"
    row "Current user"      "$(id -un 2>/dev/null || whoami)"
    row "Date/time"         "$(date '+%Y-%m-%d %H:%M:%S %Z')"
    row "Operating system"  "$os"
    row "Kernel"            "$(uname -r)"
    row "Architecture"      "$(uname -m)"
    row "Uptime"            "$up"
    row "Load average"      "$load"
    row "Running in Docker" "$container"

    section "CPU"
    row "Model"             "$cpu"
    row "Cores"             "$cores"

    section "Memory"
    row "Total"             "$mem_total"
    row "Used"              "$mem_used"
    row "Available"         "$mem_avail"
    return 0
}

# ------------------------------ disk ------------------------------
cmd_disk() {
    [ $# -eq 0 ] || die_usage "'disk' takes no arguments."
    command -v df >/dev/null 2>&1 || { echo "Error: 'df' is not available." >&2; return 1; }

    local rc=0
    section "Filesystem usage"
    df -hP || rc=1

    section "Inode usage"
    df -i || rc=1

    section "Root filesystem"
    local line
    line="$(df -hP / 2>/dev/null | awk 'NR==2 {print $2" "$3" "$4" "$5}')"
    if [ -n "$line" ]; then
        # shellcheck disable=SC2086
        set -- $line
        row "Size"      "$1"
        row "Used"      "$2"
        row "Available" "$3"
        row "Use%"      "$4"
    else
        echo "Root filesystem information unavailable."
        rc=1
    fi
    return "$rc"
}

# ----------------------------- network ----------------------------
valid_host() {
    local h="$1"
    [ -n "$h" ] && [ "${#h}" -le 253 ] || return 1
    [[ "$h" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ ]] && return 0   # hostname / IPv4
    [[ "$h" =~ ^[0-9A-Fa-f:]*:[0-9A-Fa-f:]*$ ]] && return 0               # IPv6
    return 1
}

resolve_host() {
    local h="$1" ip=""
    if [[ "$h" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || [[ "$h" == *:* ]]; then
        echo "$h"; return 0
    fi
    if command -v getent >/dev/null 2>&1; then
        ip="$(getent ahosts "$h" 2>/dev/null | awk 'NR==1 {print $1}')"
    fi
    if [ -z "$ip" ] && command -v dscacheutil >/dev/null 2>&1; then
        ip="$(dscacheutil -q host -a name "$h" 2>/dev/null | awk '/^(ip_address|ipv6_address):/ {print $2; exit}')"
    fi
    if [ -z "$ip" ] && command -v host >/dev/null 2>&1; then
        ip="$(host "$h" 2>/dev/null | awk '/has (IPv6 )?address/ {print $NF; exit}')"
    fi
    [ -n "$ip" ] && echo "$ip"
}

cmd_network() {
    [ $# -ge 1 ] || die_usage "'network' requires a <host> argument."
    [ $# -le 1 ] || die_usage "'network' takes exactly one <host> argument."
    local host="$1"
    valid_host "$host" || die_usage "'$host' is not a valid hostname or IP address."

    section "Network check: $host"
    local addr
    addr="$(resolve_host "$host")"
    if [ -z "$addr" ]; then
        row "Resolution" "FAILED"
        row "Result"     "UNRESOLVED"
        return 1
    fi
    row "Host"             "$host"
    row "Resolved address" "$addr"

    local reachable=0

    # Ping (one packet)
    if command -v ping >/dev/null 2>&1; then
        local ping_cmd=(ping -c 1 -W 3 "$addr")
        [ "$(uname -s)" = "Darwin" ] && ping_cmd=(ping -c 1 -t 3 "$addr")
        if "${ping_cmd[@]}" >/dev/null 2>&1; then
            row "Ping" "OK"; reachable=1
        else
            row "Ping" "FAILED (host may block ICMP)"
        fi
    else
        row "Ping" "skipped (ping not installed)"
    fi

    # TCP checks on common web ports
    local port state
    for port in 80 443; do
        if command -v nc >/dev/null 2>&1; then
            if nc -z -w 3 "$addr" "$port" >/dev/null 2>&1; then
                state="open"; reachable=1
            else
                state="closed or unreachable"
            fi
        else
            state="skipped (nc not installed)"
        fi
        row "TCP $port" "$state"
    done

    if [ "$reachable" -eq 1 ]; then
        row "Result" "REACHABLE"
        return 0
    fi
    row "Result" "UNREACHABLE"
    return 1
}

# ------------------------------ main ------------------------------
main() {
    [ $# -ge 1 ] || { echo "Error: missing command." >&2; usage >&2; exit 2; }
    local cmd="$1"; shift
    case "$cmd" in
        system)          cmd_system "$@" ;;
        network)         cmd_network "$@" ;;
        disk)            cmd_disk "$@" ;;
        help|-h|--help)  usage ;;
        *)               echo "Error: unknown command '$cmd'." >&2; usage >&2; exit 2 ;;
    esac
}

main "$@"

