#!/bin/bash

. "$PROJECTPATH/.warp/bin/cache_help.sh"

cache_load_context() {
    warp_fallback_bootstrap_if_needed cache >/dev/null 2>&1 || true
    warp_service_context_load cache >/dev/null 2>&1 || true
}

cache_pick_external_cli_bin() {
    if command -v redis-cli >/dev/null 2>&1; then
        echo "redis-cli"
        return 0
    fi
    if command -v valkey-cli >/dev/null 2>&1; then
        echo "valkey-cli"
        return 0
    fi
    echo ""
}

cache_external_cli_required() {
    CACHE_EXTERNAL_CLI_BIN=$(cache_pick_external_cli_bin)
    if [ -z "$CACHE_EXTERNAL_CLI_BIN" ]; then
        warp_message_error "redis-cli/valkey-cli not found on host."
        warp_message_warn "Install redis-tools or valkey tools and retry."
        return 1
    fi
    return 0
}

cache_external_cli_exec() {
    _cmd="$1"
    _bin="$CACHE_EXTERNAL_CLI_BIN"
    _host="$WARP_CTX_HOST"
    _port="$WARP_CTX_PORT"
    _user="$WARP_CTX_USER"
    _pass="$WARP_CTX_PASSWORD"

    [ -z "$_host" ] && warp_message_error "CACHE_HOST is empty in .env" && return 1
    [ -z "$_port" ] && _port="6379"

    if [ -n "$_user" ] && [ -n "$_pass" ]; then
        "$_bin" -h "$_host" -p "$_port" --user "$_user" -a "$_pass" $_cmd
        return $?
    fi

    if [ -n "$_pass" ]; then
        "$_bin" -h "$_host" -p "$_port" -a "$_pass" $_cmd
        return $?
    fi

    "$_bin" -h "$_host" -p "$_port" $_cmd
}

cache_info_external() {
    _health="unknown"
    _version="n/a"

    if cache_external_cli_required >/dev/null 2>&1; then
        _ping="$(cache_external_cli_exec "PING" 2>/dev/null | tr -d '\r' | head -n1)"
        if [ "$_ping" = "PONG" ]; then
            _health="reachable"
        else
            _health="unreachable"
        fi

        _version="$(cache_external_cli_exec "INFO server" 2>/dev/null | awk -F: '/^redis_version:/{gsub(/\r/,"",$2); print $2; exit}')"
        [ -z "$_version" ] && _version="$(cache_external_cli_exec "INFO server" 2>/dev/null | awk -F: '/^valkey_version:/{gsub(/\r/,"",$2); print $2; exit}')"
        [ -z "$_version" ] && _version="n/a"
    else
        _health="cli-missing"
    fi

    warp_message ""
    warp_message_info "* Cache (external)"
    warp_message "Mode:                       $(warp_message_info ${WARP_CTX_MODE:-external})"
    warp_message "Engine:                     $(warp_message_info ${WARP_CTX_ENGINE:-redis})"
    warp_message "Scope:                      $(warp_message_info ${WARP_CTX_SCOPE:-remote})"
    warp_message "Host:                       $(warp_message_info ${WARP_CTX_HOST})"
    warp_message "Port:                       $(warp_message_info ${WARP_CTX_PORT:-6379})"
    [ -n "$WARP_CTX_USER" ] && warp_message "User:                       $(warp_message_info ${WARP_CTX_USER})" || warp_message "User:                       $(warp_message_warn [not set])"
    [ -n "$WARP_CTX_PASSWORD" ] && warp_message "Password:                   $(warp_message_info ********)" || warp_message "Password:                   $(warp_message_warn [not set])"
    warp_message "Health:                     $(warp_message_info ${_health})"
    warp_message "Server version:             $(warp_message_info ${_version})"
    [ "$_health" = "cli-missing" ] && warp_message_warn "Install redis-cli/valkey-cli for runtime health checks."
    warp_message ""
}

cache_cli_main() {
    if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
        redis_cli_help_usage
        return 1
    fi

    cache_load_context
    if [ "$WARP_CTX_MODE" = "external" ]; then
        cache_external_cli_required || return 1
        cache_external_cli_exec "" || return 1
        return 0
    fi

    redis_cli "$@"
}

cache_monitor_main() {
    if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
        redis_monitor_help_usage
        return 1
    fi

    cache_load_context
    if [ "$WARP_CTX_MODE" = "external" ]; then
        cache_external_cli_required || return 1
        cache_external_cli_exec "monitor" || return 1
        return 0
    fi

    redis_monitor "$@"
}

cache_ssh_main() {
    if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
        redis_ssh_help
        return 0
    fi

    cache_load_context
    if [ "$WARP_CTX_MODE" = "external" ]; then
        warp_message_warn "cache ssh is not available for external mode."
        warp_message_info "Use: warp cache cli"
        return 1
    fi

    redis_simil_ssh "$@"
}

cache_flush_main() {
    if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
        redis_flush_help
        return 0
    fi

    for _arg in "$@"; do
        if [ "$_arg" = "--force" ]; then
            warp_message_error "--force is not supported for cache flush."
            return 1
        fi
    done

    cache_load_context
    if [ "$WARP_CTX_MODE" = "external" ]; then
        cache_external_cli_required || return 1
        warp_message_warn "External cache flush is destructive."
        if ! warp_fallback_confirm_explicit_yes "Type y to continue with external cache FLUSHALL: "; then
            warp_message_warn "Aborted."
            return 1
        fi
        cache_external_cli_exec "FLUSHALL" || return 1
        return 0
    fi

    redis_flush "$@"
}

function cache_main()
{
    case "$1" in
        cli)
            shift 1
            cache_cli_main "$@"
        ;;

        monitor)
            shift 1
            cache_monitor_main "$@"
        ;;

        info)
            if [ "$2" = "-h" ] || [ "$2" = "--help" ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
                redis_info_help
                return 0
            fi
            cache_load_context
            if [ "$WARP_CTX_MODE" = "external" ]; then
                cache_info_external
            else
                redis_info
            fi
        ;;

        ssh)
            shift
            cache_ssh_main "$@"
        ;;

        flush)
            shift
            cache_flush_main "$@"
        ;;

        -h | --help)
            cache_help_usage
        ;;

        *)
            cache_help_usage
        ;;
    esac
}
