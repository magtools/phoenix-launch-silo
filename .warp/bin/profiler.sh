#!/bin/bash

. "$PROJECTPATH/.warp/bin/profiler_help.sh"

PROFILER_CONNECTOR=""
PROFILER_FORCE=0
PROFILER_NO_CACHE_CLEAN=0

profiler_print_kv() {
    local _label="$1"
    local _value="$2"

    printf '%-30s %s\n' "${_label}:" "${_value:-unknown}"
}

profiler_has_flag() {
    local _needle="$1"
    shift 1
    local _arg=""

    for _arg in "$@"; do
        [ "$_arg" = "$_needle" ] && return 0
    done

    return 1
}

profiler_parse_global_flags() {
    PROFILER_FORCE=0
    PROFILER_NO_CACHE_CLEAN=0

    profiler_has_flag "--force" "$@" && PROFILER_FORCE=1
    profiler_has_flag "--no-cache-clean" "$@" && PROFILER_NO_CACHE_CLEAN=1
}

profiler_detect_connector() {
    local _configured=""
    local _framework=""

    _configured=$(warp_env_read_var "WARP_PROFILER_CONNECTOR" 2>/dev/null)
    if [ -n "$_configured" ]; then
        printf '%s\n' "$_configured"
        return 0
    fi

    if command -v warp_app_context_detect_framework >/dev/null 2>&1; then
        _framework=$(warp_app_context_detect_framework)
        [ -n "$_framework" ] && [ "$_framework" != "unknown" ] && {
            printf '%s\n' "$_framework"
            return 0
        }
    fi

    if [ -f "$PROJECTPATH/app/etc/env.php" ] || [ -f "$PROJECTPATH/bin/magento" ]; then
        printf '%s\n' "magento"
        return 0
    fi

    printf '%s\n' "generic"
}

profiler_load_connector() {
    local _connector="$1"
    local _file=""

    _file="$PROJECTPATH/.warp/bin/profiler/connectors/${_connector}.sh"
    [ -f "$_file" ] || {
        warp_message_error "profiler connector not found: $_connector"
        return 1
    }

    . "$_file"
    PROFILER_CONNECTOR="$_connector"
}

profiler_require_connector() {
    local _connector=""

    [ -n "$PROFILER_CONNECTOR" ] && return 0

    _connector=$(profiler_detect_connector)
    profiler_load_connector "$_connector"
}

profiler_main() {
    local _action="${1:-status}"
    local _mode=""
    local _target=""

    profiler_parse_global_flags "$@"

    case "$_action" in
        -h|--help|help)
            profiler_help_usage
            exit 0
            ;;
    esac

    profiler_require_connector || exit 1

    case "$_action" in
        status|--status|"")
            profiler_connector_status
            exit $?
            ;;
        php)
            shift 1
            case "${1:-}" in
                --enable|enable)
                    _mode="${2:-html}"
                    profiler_connector_php_enable "$_mode"
                    exit $?
                    ;;
                --disable|disable)
                    profiler_connector_php_disable
                    exit $?
                    ;;
                -h|--help|help)
                    profiler_connector_help
                    exit 0
                    ;;
                *)
                    warp_message_warn "unknown profiler php action: ${1:-}"
                    profiler_help_usage
                    exit 1
                    ;;
            esac
            ;;
        db)
            shift 1
            case "${1:-}" in
                --enable|enable)
                    _mode="${2:-controlled}"
                    profiler_connector_db_enable "$_mode"
                    exit $?
                    ;;
                --disable|disable)
                    profiler_connector_db_disable
                    exit $?
                    ;;
                -h|--help|help)
                    profiler_connector_help
                    exit 0
                    ;;
                *)
                    warp_message_warn "unknown profiler db action: ${1:-}"
                    profiler_help_usage
                    exit 1
                    ;;
            esac
            ;;
        logs)
            shift 1
            case "${1:-}" in
                --truncate|truncate)
                    _target="${2:-all}"
                    profiler_connector_logs_truncate "$_target"
                    exit $?
                    ;;
                *)
                    warp_message_warn "unknown profiler logs action: ${1:-}"
                    profiler_help_usage
                    exit 1
                    ;;
            esac
            ;;
        --disable|disable)
            if profiler_has_flag "--all" "$@"; then
                profiler_connector_php_disable || exit $?
                profiler_connector_db_disable
                exit $?
            fi
            warp_message_warn "use: warp profiler --disable --all"
            profiler_help_usage
            exit 1
            ;;
        *)
            warp_message_warn "unknown profiler action: $_action"
            profiler_help_usage
            exit 1
            ;;
    esac
}
