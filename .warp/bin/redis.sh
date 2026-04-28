#!/bin/bash

. "$PROJECTPATH/.warp/bin/redis_help.sh"

redis_runtime_engine() {
    warp_cache_engine_resolve "${CACHE_ENGINE:-$(warp_env_read_var CACHE_ENGINE)}"
}

redis_runtime_cli_bin() {
    warp_cache_engine_cli_bin "$(redis_runtime_engine)"
}

redis_runtime_container_user() {
    warp_cache_engine_container_user "$(redis_runtime_engine)"
}

redis_scope_to_service() {
    case "$1" in
        cache) printf '%s\n' "redis-cache" ;;
        session) printf '%s\n' "redis-session" ;;
        fpc) printf '%s\n' "redis-fpc" ;;
        *) printf '%s\n' "" ;;
    esac
}

redis_service_check() {
    case "$1" in
        cache)
            grep -q "REDIS_CACHE_VERSION" "$ENVIRONMENTVARIABLESFILE" || { warp_message_error "Redis $1 service not found." ; exit 1; }
            ;;
        session)
            grep -q "REDIS_SESSION_VERSION" "$ENVIRONMENTVARIABLESFILE" || { warp_message_error "Redis $1 service not found." ; exit 1; }
            ;;
        fpc)
            grep -q "REDIS_FPC_VERSION" "$ENVIRONMENTVARIABLESFILE" || { warp_message_error "Redis $1 service not found." ; exit 1; }
            ;;
        *)
            printf "\tWRONG INPUT ON redis_service_check FUNCTION.\n\tPLEASE REPORT THIS TO WARP DEV TEAM."
            exit 1
            ;;
    esac
}

redis_check_warp_running() {
    if [ "$(warp_check_is_running)" = false ]; then
        warp_message_error "The containers are not running"
        warp_message_error "please, first run warp start"
        exit 1
    fi
}

redis_compose_exec_cli() {
    local _service="$1"
    shift
    docker-compose -f "$DOCKERCOMPOSEFILE" exec -uroot "$_service" "$(redis_runtime_cli_bin)" "$@"
}

redis_info() {
    local REDIS_CACHE_VERSION=""
    local REDIS_SESSION_VERSION=""
    local REDIS_FPC_VERSION=""
    local _engine=""

    if ! warp_check_env_file; then
        warp_message_error "file not found $(basename "$ENVIRONMENTVARIABLESFILE")"
        exit 1
    fi

    REDIS_CACHE_VERSION=$(warp_env_read_var REDIS_CACHE_VERSION)
    REDIS_SESSION_VERSION=$(warp_env_read_var REDIS_SESSION_VERSION)
    REDIS_FPC_VERSION=$(warp_env_read_var REDIS_FPC_VERSION)
    _engine=$(redis_runtime_engine)

    if [ -n "$REDIS_CACHE_VERSION" ]; then
        warp_message ""
        warp_message_info "* Redis Cache"
        warp_message "Engine:                     $(warp_message_info "$_engine")"
        warp_message "Version:                    $(warp_message_info "$REDIS_CACHE_VERSION")"
        warp_message "Host:                       $(warp_message_info 'redis-cache')"
        warp_message "Port (container):           $(warp_message_info '6379')"
        warp_message ""
    fi

    if [ -n "$REDIS_SESSION_VERSION" ]; then
        warp_message ""
        warp_message_info "* Redis Session"
        warp_message "Engine:                     $(warp_message_info "$_engine")"
        warp_message "Version:                    $(warp_message_info "$REDIS_SESSION_VERSION")"
        warp_message "Host:                       $(warp_message_info 'redis-session')"
        warp_message "Port (container):           $(warp_message_info '6379')"
        warp_message ""
    fi

    if [ -n "$REDIS_FPC_VERSION" ]; then
        warp_message ""
        warp_message_info "* Redis Fpc"
        warp_message "Engine:                     $(warp_message_info "$_engine")"
        warp_message "Version:                    $(warp_message_info "$REDIS_FPC_VERSION")"
        warp_message "Host:                       $(warp_message_info 'redis-fpc')"
        warp_message "Port (container):           $(warp_message_info '6379')"
        warp_message ""
    fi
}

redis_cli() {
    local _service=""

    if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
        redis_cli_help_usage
        exit 1
    fi

    redis_check_warp_running
    redis_service_check "$1"
    _service=$(redis_scope_to_service "$1")
    if [ -z "$_service" ]; then
        warp_message_error "Please, choose a valid option:"
        warp_message_error "fpc, session, cache"
        warp_message_error "for more information please run: warp cache cli --help"
        exit 1
    fi

    redis_compose_exec_cli "$_service"
}

redis_monitor() {
    local _service=""

    if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
        redis_monitor_help_usage
        exit 1
    fi

    redis_check_warp_running
    redis_service_check "$1"
    _service=$(redis_scope_to_service "$1")
    if [ -z "$_service" ]; then
        warp_message_error "Please, choose a valid option:"
        warp_message_error "fpc, session, cache"
        warp_message_error "for more information please run: warp cache monitor --help"
        exit 1
    fi

    redis_compose_exec_cli "$_service" monitor
}

redis_ssh_wrong_input() {
    warp_message_error "Wrong input."
    redis_ssh_help
    exit 1
}

redis_flush_wrong_input() {
    warp_message_error "Wrong input."
    redis_flush_help
    exit 1
}

redis_simil_ssh_link() {
    local _service="$1"
    local _mode="$2"
    local _user=""

    if [[ "$_mode" == "--root" ]]; then
        docker-compose -f "$DOCKERCOMPOSEFILE" exec -u root "$_service" bash
        return 0
    fi

    if [[ -z "$_mode" || "$_mode" == "--redis" || "$_mode" == "--cache" ]]; then
        _user=$(redis_runtime_container_user)
        docker-compose -f "$DOCKERCOMPOSEFILE" exec -u "$_user" "$_service" bash
        return 0
    fi

    redis_ssh_wrong_input
}

redis_simil_ssh() {
    local _scope="$1"
    local _service=""

    if [[ $# -gt 2 ]]; then
        redis_ssh_wrong_input
        exit 1
    fi

    case "$_scope" in
        cache|session|fpc)
            if [[ "$2" == "-h" || "$2" == "--help" ]]; then
                redis_ssh_help
                exit 0
            fi
            redis_service_check "$_scope"
            redis_check_warp_running
            _service=$(redis_scope_to_service "$_scope")
            redis_simil_ssh_link "$_service" "$2"
            exit 0
            ;;
        *)
            redis_ssh_help
            exit 1
            ;;
    esac
}

redis_flush_one() {
    local _scope="$1"
    local _service=""

    redis_service_check "$_scope"
    _service=$(redis_scope_to_service "$_scope")
    [ -n "$_service" ] || return 1
    docker-compose -f "$DOCKERCOMPOSEFILE" exec "$_service" "$(redis_runtime_cli_bin)" FLUSHALL
}

redis_flush() {
    if [[ $# -gt 1 ]]; then
        redis_flush_wrong_input
        exit 1
    fi

    case "$1" in
        cache|session|fpc)
            redis_flush_one "$1"
            exit 0
            ;;
        --all)
            warp_message "redis-cache FLUSHALL:     $(redis_flush_one cache)"
            warp_message "redis-session FLUSHALL:   $(redis_flush_one session)"
            warp_message "redis-fpc FLUSHALL:       $(redis_flush_one fpc)"
            exit 0
            ;;
        -h|--help)
            redis_flush_help
            exit 0
            ;;
        *)
            redis_flush_wrong_input
            exit 1
            ;;
    esac
}

redis_main() {
    case "$1" in
        cli)
            shift
            redis_cli "$@"
            ;;
        monitor)
            shift
            redis_monitor "$@"
            ;;
        info)
            redis_info
            ;;
        ssh)
            shift
            redis_simil_ssh "$@"
            ;;
        flush)
            shift
            redis_flush "$@"
            ;;
        -h|--help)
            redis_help_usage
            ;;
        *)
            redis_help_usage
            ;;
    esac
}
