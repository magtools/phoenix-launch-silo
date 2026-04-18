#!/bin/bash

PROFILER_GENERIC_PHP_FLAG="$PROJECTPATH/var/profiler.flag"
PROFILER_GENERIC_CSV_LOG="$PROJECTPATH/var/log/profiler.csv"

profiler_generic_log_size() {
    local _file="$1"
    local _size=""

    [ -e "$_file" ] || {
        printf '%s\n' "missing"
        return 0
    }

    _size=$(du -h "$_file" 2>/dev/null | awk '{print $1; exit}')
    printf '%s\n' "${_size:-unknown}"
}

profiler_generic_file_mode() {
    local _file="$1"
    local _mode=""

    [ -e "$_file" ] || {
        printf '%s\n' "missing"
        return 0
    }

    _mode=$(stat -c '%a' "$_file" 2>/dev/null)
    if [ -z "$_mode" ]; then
        _mode=$(stat -f '%Lp' "$_file" 2>/dev/null)
    fi

    printf '%s\n' "${_mode:-unknown}"
}

profiler_generic_csv_log_state() {
    local _php_state="$1"
    local _size=""
    local _mode=""

    [ -e "$PROFILER_GENERIC_CSV_LOG" ] || {
        if [ "$_php_state" = "enabled-csv" ]; then
            printf '%s\n' "missing (CSV profiler enabled; file should be created by Warp with mode 666 before the request)"
            return 0
        fi
        printf '%s\n' "missing"
        return 0
    }

    _size=$(profiler_generic_log_size "$PROFILER_GENERIC_CSV_LOG")
    _mode=$(profiler_generic_file_mode "$PROFILER_GENERIC_CSV_LOG")
    if [ "$_php_state" = "enabled-csv" ] && [ "$_mode" != "666" ]; then
        printf '%s\n' "${_size} (mode ${_mode}; expected 666 for CSV writes)"
        return 0
    fi

    printf '%s\n' "${_size} (mode ${_mode})"
}

profiler_generic_php_state() {
    local _config=""

    [ -f "$PROFILER_GENERIC_PHP_FLAG" ] || {
        printf '%s\n' "disabled"
        return 0
    }

    _config=$(tr -d '\n\r\t ' < "$PROFILER_GENERIC_PHP_FLAG" 2>/dev/null)
    case "$_config" in
        "")
            printf '%s\n' "disabled-empty-flag"
            ;;
        html)
            printf '%s\n' "enabled-html"
            ;;
        *csvfile*)
            printf '%s\n' "enabled-csv"
            ;;
        *)
            printf '%s\n' "enabled-custom"
            ;;
    esac
}

profiler_generic_php_flag_value() {
    [ -f "$PROFILER_GENERIC_PHP_FLAG" ] || {
        printf '%s\n' "missing"
        return 0
    }

    [ -s "$PROFILER_GENERIC_PHP_FLAG" ] || {
        printf '%s\n' "empty"
        return 0
    }

    tr -d '\n\r' < "$PROFILER_GENERIC_PHP_FLAG" 2>/dev/null
}

profiler_generic_truncate_file() {
    local _file="$1"

    mkdir -p "$(dirname "$_file")" || return 1
    : > "$_file"
}

profiler_generic_prepare_csv_log() {
    profiler_generic_truncate_file "$PROFILER_GENERIC_CSV_LOG" || return 1
    chmod 666 "$PROFILER_GENERIC_CSV_LOG" || {
        warp_message_error "could not set mode 666 on var/log/profiler.csv"
        return 1
    }
}

profiler_connector_status() {
    local _php_state=""

    warp_message ""
    warp_message_info "Profiler status"
    warp_message "---------------"
    profiler_print_kv "connector" "generic"
    _php_state=$(profiler_generic_php_state)
    profiler_print_kv "php profiler" "$_php_state"
    profiler_print_kv "php var/profiler.flag" "$(profiler_generic_php_flag_value)"
    profiler_print_kv "DB logger" "unsupported"
    profiler_print_kv "var/log/profiler.csv" "$(profiler_generic_csv_log_state "$_php_state")"
    warp_message ""
}

profiler_connector_php_enable() {
    local _mode="${1:-html}"

    mkdir -p "$PROJECTPATH/var/log" || return 1
    case "$_mode" in
        html)
            printf '%s' "html" > "$PROFILER_GENERIC_PHP_FLAG" || return 1
            ;;
        csv)
            printf '%s' '{"drivers":[{"type":"standard","output":{"type":"csvfile","filePath":"var/log/profiler.csv"}}]}' > "$PROFILER_GENERIC_PHP_FLAG" || return 1
            profiler_generic_prepare_csv_log || return 1
            ;;
        *)
            warp_message_error "unknown PHP profiler mode: $_mode"
            return 1
            ;;
    esac

    warp_message_info "PHP profiler enabled: $_mode"
    profiler_print_kv "profiler flag" "var/profiler.flag"
}

profiler_connector_php_disable() {
    rm -f "$PROFILER_GENERIC_PHP_FLAG" || return 1
    profiler_generic_prepare_csv_log || return 1
    warp_message_info "PHP profiler disabled."
    profiler_print_kv "truncated" "var/log/profiler.csv"
}

profiler_connector_db_enable() {
    warp_message_error "DB profiler requires the Magento connector"
    return 1
}

profiler_connector_db_disable() {
    warp_message_error "DB profiler requires the Magento connector"
    return 1
}

profiler_connector_logs_truncate() {
    local _target="${1:-all}"

    if [ ! -t 0 ] && [ "$PROFILER_FORCE" != "1" ]; then
        warp_message_error "log truncation in non-interactive mode requires --force"
        return 1
    fi

    case "$_target" in
        profiler|php|all)
            profiler_generic_prepare_csv_log || return 1
            profiler_print_kv "truncated" "var/log/profiler.csv"
            ;;
        db)
            warp_message_error "DB logs require the Magento connector"
            return 1
            ;;
        *)
            warp_message_error "unknown profiler log target: $_target"
            return 1
            ;;
    esac
}

profiler_connector_help() {
    profiler_help_usage
}
