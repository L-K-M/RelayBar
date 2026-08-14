#!/bin/sh

host=""
for argument in "$@"; do
    host="$argument"
done

IFS= read -r command
local_path=$(printf '%s\n' "$command" | sed -E 's/.*"([^"]*)"[[:space:]]*$/\1/')

case "$host" in
    listing|shared)
        case "$command" in
        get*)
            mkdir -p "$(dirname "$local_path")"
            printf 'downloaded' > "$local_path"
            ;;
        *)
            printf '%s\n' '-rw-r--r-- 1 alice staff 12 Jul 29 12:00 report.txt'
            printf '%s\n' 'drwxr-xr-x 2 alice staff 64 Jul 29 12:01 output'
            ;;
        esac
        ;;
    directfile)
        printf '%s\n' '-rw-r--r-- 1 linxy97 staff 4096 Aug 3 20:30 /home/linxy97/workspace/2026/youtube-video-transcript/TRANSCRIPTION_LEARNINGS.md'
        ;;
    sharedslow)
        case "$command" in
        get*)
            mkdir -p "$(dirname "$local_path")"
            printf 'partial' > "$local_path"
            exec /bin/sleep 60
            ;;
        *)
            printf '%s\n' '-rw-r--r-- 1 alice staff 12 Jul 29 12:00 report.txt'
            printf '%s\n' 'drwxr-xr-x 2 alice staff 64 Jul 29 12:01 output'
            ;;
        esac
        ;;
    RelayBarCancelledSFTP-*)
        : > "/tmp/$host"
        printf '%s\n' '-rw-r--r-- 1 alice staff 12 Jul 29 12:00 report.txt'
        ;;
    success)
        mkdir -p "$(dirname "$local_path")"
        printf 'downloaded' > "$local_path"
        ;;
    folder)
        mkdir -p "$local_path"
        printf 'visible' > "$local_path/visible.txt"
        printf 'hidden' > "$local_path/.hidden"
        ;;
    failure)
        mkdir -p "$(dirname "$local_path")"
        printf 'partial' > "$local_path"
        printf 'Permission denied\n' >&2
        exit 1
        ;;
    notfound)
        printf 'Can'\''t ls: "/workspace" not found\n' >&2
        exit 1
        ;;
    hostkey)
        printf 'Host key verification failed.\nConnection closed\n' >&2
        exit 1
        ;;
    refused)
        printf 'ssh: connect to host 127.0.0.1 port 1: Connection refused\nConnection closed\n' >&2
        exit 1
        ;;
    invalidutf8)
        printf '\377\n'
        exit 0
        ;;
    unreadable)
        # Requires a non-root test harness; root ignores the 000 mode.
        chmod 000 /dev/fd/1 || exit 1
        exit 0
        ;;
    empty)
        exit 0
        ;;
    invaliddiagnostic)
        printf 'Permission denied: \377\n' >&2
        exit 1
        ;;
    successdiagnostic)
        printf 'warning\n' >&2
        exit 0
        ;;
    slow)
        mkdir -p "$(dirname "$local_path")"
        printf 'partial' > "$local_path"
        exec /bin/sleep 60
        ;;
    stubborn)
        mkdir -p "$(dirname "$local_path")"
        trap '' TERM
        printf 'partial' > "$local_path"
        while :; do
            :
        done
        ;;
    *)
        printf 'Unknown fake host\n' >&2
        exit 1
        ;;
esac
