#!/usr/bin/env bash
# ==============================================================================
# Tiny Bash HTTP Microservice (via socat / netcat)
#
# Exposes a /health endpoint for smoke tests and Kubernetes probes.
# Strict ShellCheck compliant.
# ==============================================================================

set -eo pipefail

PORT="${PORT:-8080}"
APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION_FILE="${APP_DIR}/VERSION"

if [[ -f "$VERSION_FILE" ]]; then
    VERSION="$(cat "$VERSION_FILE" | tr -d '[:space:]')"
else
    VERSION="1.0.0-dev"
fi

START_TIME=$(date +%s)
HOSTNAME_STR="$(hostname 2>/dev/null || echo 'localhost')"

cleanup() {
    echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] Server shutting down cleanly..."
    exit 0
}

trap cleanup SIGINT SIGTERM

echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] Starting Bash HTTP service on port ${PORT} (Version: ${VERSION})..."

handle_request() {
    local request_line
    read -r request_line || return

    local method path proto
    read -r method path proto <<< "$request_line"

    # Consume remaining HTTP request headers until empty line (\r)
    while read -r header_line; do
        header_line="${header_line%%$'\r'}"
        [[ -z "$header_line" ]] && break
    done

    local now uptime
    now=$(date +%s)
    uptime=$((now - START_TIME))

    case "$path" in
        /health|/healthz)
            local body="{\"status\":\"ok\",\"version\":\"${VERSION}\",\"uptime_seconds\":${uptime},\"hostname\":\"${HOSTNAME_STR}\",\"service\":\"iac-quality-gate-app\"}"
            local content_length=${#body}
            printf "HTTP/1.1 200 OK\r\n"
            printf "Content-Type: application/json\r\n"
            printf "Content-Length: %d\r\n" "$content_length"
            printf "Connection: close\r\n"
            printf "\r\n"
            printf "%s" "$body"
            ;;
        /version)
            local body="{\"version\":\"${VERSION}\"}"
            local content_length=${#body}
            printf "HTTP/1.1 200 OK\r\n"
            printf "Content-Type: application/json\r\n"
            printf "Content-Length: %d\r\n" "$content_length"
            printf "Connection: close\r\n"
            printf "\r\n"
            printf "%s" "$body"
            ;;
        /)
            local body="{\"message\":\"Infrastructure-as-Code Quality Gate Service\",\"version\":\"${VERSION}\",\"endpoints\":[\"/health\",\"/version\"]}"
            local content_length=${#body}
            printf "HTTP/1.1 200 OK\r\n"
            printf "Content-Type: application/json\r\n"
            printf "Content-Length: %d\r\n" "$content_length"
            printf "Connection: close\r\n"
            printf "\r\n"
            printf "%s" "$body"
            ;;
        *)
            local body="{\"error\":\"Not Found\",\"path\":\"${path}\"}"
            local content_length=${#body}
            printf "HTTP/1.1 404 Not Found\r\n"
            printf "Content-Type: application/json\r\n"
            printf "Content-Length: %d\r\n" "$content_length"
            printf "Connection: close\r\n"
            printf "\r\n"
            printf "%s" "$body"
            ;;
    esac
}

export -f handle_request
export START_TIME VERSION HOSTNAME_STR

if command -v socat >/dev/null 2>&1; then
    echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] Listening with socat on TCP4-LISTEN:${PORT}..."
    exec socat -T 5 TCP4-LISTEN:"${PORT}",reuseaddr,fork SYSTEM:"bash -c handle_request"
elif command -v nc >/dev/null 2>&1; then
    echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] Listening with netcat on port ${PORT}..."
    while true; do
        # Traditional Netcat loop
        handle_request | nc -l -p "${PORT}" -q 1 2>/dev/null || handle_request | nc -l "${PORT}" 2>/dev/null
    done
else
    echo "Error: Neither 'socat' nor 'nc' (netcat) found in PATH." >&2
    exit 1
fi
