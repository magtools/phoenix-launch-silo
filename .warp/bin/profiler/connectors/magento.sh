#!/bin/bash

PROFILER_MAGENTO_ENV_FILE="$PROJECTPATH/app/etc/env.php"
PROFILER_MAGENTO_PHP_FLAG="$PROJECTPATH/var/profiler.flag"
PROFILER_MAGENTO_DB_LOG="$PROJECTPATH/var/debug/db.log"
PROFILER_MAGENTO_CSV_LOG="$PROJECTPATH/var/log/profiler.csv"

profiler_magento_warp_exec() {
    if [ -x "$PROJECTPATH/warp" ]; then
        printf '%s\n' "$PROJECTPATH/warp"
        return 0
    fi
    if [ -x "$PROJECTPATH/warp.sh" ]; then
        printf '%s\n' "$PROJECTPATH/warp.sh"
        return 0
    fi
    printf '%s\n' "warp"
}

profiler_magento_log_size() {
    local _file="$1"
    local _size=""

    [ -e "$_file" ] || {
        printf '%s\n' "missing"
        return 0
    }

    _size=$(du -h "$_file" 2>/dev/null | awk '{print $1; exit}')
    printf '%s\n' "${_size:-unknown}"
}

profiler_magento_php_state() {
    local _config=""

    [ -f "$PROFILER_MAGENTO_PHP_FLAG" ] || {
        printf '%s\n' "disabled"
        return 0
    }

    _config=$(tr -d '\n\r\t ' < "$PROFILER_MAGENTO_PHP_FLAG" 2>/dev/null)
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

profiler_magento_env_summary() {
    [ -f "$PROFILER_MAGENTO_ENV_FILE" ] || {
        printf '%s\n' "mode=missing"
        printf '%s\n' "db_logger=missing"
        printf '%s\n' "smile_profiler=missing"
        return 0
    }

    awk '
function trim(value) {
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
    sub(/,$/, "", value)
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
    gsub(/^["\047]|["\047]$/, "", value)
    return value
}
function delta(line, opens, closes) {
    opens = gsub(/\[/, "[", line)
    closes = gsub(/\]/, "]", line)
    return opens - closes
}
function read_value(line, parts) {
    split(line, parts, "=>")
    return trim(parts[2])
}
BEGIN {
    mode = "unknown"
    db_output = ""
    db_everything = ""
    db_threshold = ""
    db_stacktrace = ""
    smile = "missing"
    in_db_logger = 0
    db_depth = 0
    in_profiler = 0
    profiler_depth = 0
    profiler_has_smile = 0
    profiler_enabled = ""
}
/^[[:space:]]*["\047]MAGE_MODE["\047][[:space:]]*=>/ {
    mode = read_value($0)
}
in_db_logger {
    db_depth += delta($0)
    if ($0 ~ /^[[:space:]]*["\047]output["\047][[:space:]]*=>/) db_output = read_value($0)
    if ($0 ~ /^[[:space:]]*["\047]log_everything["\047][[:space:]]*=>/) db_everything = read_value($0)
    if ($0 ~ /^[[:space:]]*["\047]query_time_threshold["\047][[:space:]]*=>/) db_threshold = read_value($0)
    if ($0 ~ /^[[:space:]]*["\047]include_stacktrace["\047][[:space:]]*=>/) db_stacktrace = read_value($0)
    if (db_depth <= 0) in_db_logger = 0
    next
}
/^[[:space:]]*["\047]db_logger["\047][[:space:]]*=>[[:space:]]*\[/ {
    in_db_logger = 1
    db_depth = delta($0)
    next
}
in_profiler {
    profiler_depth += delta($0)
    if ($0 ~ /Smile\\\\DebugToolbar\\\\DB\\\\Profiler/) profiler_has_smile = 1
    if ($0 ~ /^[[:space:]]*["\047]enabled["\047][[:space:]]*=>/) profiler_enabled = read_value($0)
    if (profiler_depth <= 0) {
        if (profiler_has_smile) {
            smile = (profiler_enabled ~ /^(true|1)$/) ? "enabled" : "disabled"
        }
        in_profiler = 0
        profiler_has_smile = 0
        profiler_enabled = ""
    }
    next
}
/^[[:space:]]*["\047]profiler["\047][[:space:]]*=>[[:space:]]*\[/ {
    in_profiler = 1
    profiler_depth = delta($0)
    profiler_has_smile = 0
    profiler_enabled = ""
    next
}
END {
    print "mode=" mode
    if (db_output == "") {
        print "db_logger=missing"
    } else {
        print "db_logger=output:" db_output " log_everything:" db_everything " threshold:" db_threshold " stacktrace:" db_stacktrace
    }
    print "smile_profiler=" smile
}
' "$PROFILER_MAGENTO_ENV_FILE" 2>/dev/null || {
        printf '%s\n' "mode=unreadable"
        printf '%s\n' "db_logger=unreadable"
        printf '%s\n' "smile_profiler=unreadable"
    }
}

profiler_magento_mode() {
    local _mode=""

    _mode=$(profiler_magento_env_summary | awk -F= '$1 == "mode" {print $2; exit}')
    printf '%s\n' "${_mode:-unknown}"
}

profiler_magento_require_env_write_allowed() {
    local _mode=""

    [ -f "$PROFILER_MAGENTO_ENV_FILE" ] || {
        warp_message_error "Magento env.php not found: app/etc/env.php"
        return 1
    }

    _mode=$(profiler_magento_mode)
    [ "$_mode" = "developer" ] && return 0

    if [ "$PROFILER_FORCE" = "1" ]; then
        warp_message_warn "applying profiler change with --force; detected MAGE_MODE=${_mode}"
        return 0
    fi

    warp_message_error "env.php writes are allowed automatically only in MAGE_MODE=developer"
    warp_message_warn "detected MAGE_MODE=${_mode}; rerun with --force to apply this change"
    return 1
}

profiler_magento_backup_env() {
    local _ts=""
    local _backup=""
    local _i=0

    _ts=$(date '+%Y%m%d%H%M%S')
    _backup="${PROFILER_MAGENTO_ENV_FILE}.warp-profiler-backup-${_ts}"
    while [ -e "$_backup" ]; do
        _i=$((_i + 1))
        _backup="${PROFILER_MAGENTO_ENV_FILE}.warp-profiler-backup-${_ts}-${_i}"
    done
    cp "$PROFILER_MAGENTO_ENV_FILE" "$_backup" || return 1
    printf '%s\n' "$_backup"
}

profiler_magento_db_logger_block() {
    local _operation="$1"
    local _mode="$2"

    if [ "$_operation" = "enable-db" ] && [ "$_mode" = "controlled" ]; then
        cat <<'EOF'
    'db_logger' => [
        'output' => 'file',
        'log_everything' => 0,
        'query_time_threshold' => '0.05',
        'include_stacktrace' => 0,
    ],
EOF
        return 0
    fi

    if [ "$_operation" = "enable-db" ] && [ "$_mode" = "full" ]; then
        cat <<'EOF'
    'db_logger' => [
        'output' => 'file',
        'log_everything' => 1,
        'query_time_threshold' => '0.001',
        'include_stacktrace' => 1,
    ],
EOF
        return 0
    fi

    if [ "$_operation" = "disable-db" ]; then
        cat <<'EOF'
    'db_logger' => [
        'output' => 'disabled',
        'log_everything' => 0,
        'query_time_threshold' => '0.05',
        'include_stacktrace' => 0,
    ],
EOF
        return 0
    fi

    return 1
}

profiler_magento_update_db_logger_text() {
    local _block="$1"
    local _tmp="$2"

    awk -v block="$_block" '
function delta(line, opens, closes) {
    opens = gsub(/\[/, "[", line)
    closes = gsub(/\]/, "]", line)
    return opens - closes
}
{
    lines[NR] = $0
    if ($0 ~ /^[[:space:]]*\][[:space:]]*;[[:space:]]*$/) {
        last_close = NR
    }
}
END {
    replaced = 0
    for (i = 1; i <= NR; i++) {
        if (lines[i] ~ /^[[:space:]]*["\047]db_logger["\047][[:space:]]*=>[[:space:]]*\[/) {
            depth = delta(lines[i])
            while (depth > 0 && i < NR) {
                i++
                depth += delta(lines[i])
            }
            print block
            replaced = 1
            continue
        }
        if (!replaced && i == last_close) {
            print block
            replaced = 1
        }
        print lines[i]
    }
    if (!replaced) {
        exit 7
    }
}
' "$PROFILER_MAGENTO_ENV_FILE" > "$_tmp"
}

profiler_magento_disable_smile_text() {
    local _input="$1"
    local _output="$2"

    awk '
function delta(line, opens, closes) {
    opens = gsub(/\[/, "[", line)
    closes = gsub(/\]/, "]", line)
    return opens - closes
}
{
    lines[NR] = $0
}
END {
    for (i = 1; i <= NR; i++) {
        if (lines[i] ~ /^[[:space:]]*["\047]profiler["\047][[:space:]]*=>[[:space:]]*\[/) {
            start = i
            end = i
            depth = delta(lines[i])
            has_smile = (lines[i] ~ /Smile\\\\DebugToolbar\\\\DB\\\\Profiler/)
            while (depth > 0 && end < NR) {
                end++
                if (lines[end] ~ /Smile\\\\DebugToolbar\\\\DB\\\\Profiler/) has_smile = 1
                depth += delta(lines[end])
            }
            if (has_smile) {
                for (j = start; j <= end; j++) {
                    if (lines[j] ~ /^[[:space:]]*["\047]enabled["\047][[:space:]]*=>/) {
                        sub(/=>[[:space:]]*(true|false|1|0)/, "=> false", lines[j])
                    }
                }
            }
            for (j = start; j <= end; j++) {
                print lines[j]
            }
            i = end
            continue
        }
        print lines[i]
    }
}
' "$_input" > "$_output"
}

profiler_magento_write_env() {
    local _operation="$1"
    local _mode="$2"
    local _backup=""
    local _block=""
    local _tmp_db=""
    local _tmp_smile=""
    local _status=0

    profiler_magento_require_env_write_allowed || return 1

    _block=$(profiler_magento_db_logger_block "$_operation" "$_mode") || {
        warp_message_error "unknown env.php operation: $_operation $_mode"
        return 1
    }

    _backup=$(profiler_magento_backup_env) || {
        warp_message_error "could not create env.php backup"
        return 1
    }

    _tmp_db=$(mktemp 2>/dev/null) || {
        warp_message_error "could not create temporary env.php file"
        return 1
    }

    profiler_magento_update_db_logger_text "$_block" "$_tmp_db"
    _status=$?
    if [ $_status -ne 0 ]; then
        rm -f "$_tmp_db"
        warp_message_error "could not update env.php; backup kept at $_backup"
        return 1
    fi

    if [ "$_operation" = "disable-db" ]; then
        _tmp_smile=$(mktemp 2>/dev/null) || {
            rm -f "$_tmp_db"
            warp_message_error "could not create temporary env.php file"
            return 1
        }
        profiler_magento_disable_smile_text "$_tmp_db" "$_tmp_smile"
        _status=$?
        rm -f "$_tmp_db"
        if [ $_status -ne 0 ]; then
            rm -f "$_tmp_smile"
            warp_message_error "could not disable Smile profiler; backup kept at $_backup"
            return 1
        fi
        mv "$_tmp_smile" "$PROFILER_MAGENTO_ENV_FILE" || {
            rm -f "$_tmp_smile"
            warp_message_error "could not write env.php; backup kept at $_backup"
            return 1
        }
    else
        mv "$_tmp_db" "$PROFILER_MAGENTO_ENV_FILE" || {
            rm -f "$_tmp_db"
            warp_message_error "could not write env.php; backup kept at $_backup"
            return 1
        }
    fi

    profiler_print_kv "env.php backup" "${_backup#$PROJECTPATH/}"
}

profiler_magento_cache_clean() {
    local _warp_exec=""

    [ "$PROFILER_NO_CACHE_CLEAN" = "1" ] && {
        warp_message_warn "skipped Magento cache:clean config"
        return 0
    }

    _warp_exec=$(profiler_magento_warp_exec)
    "$_warp_exec" magento cache:clean config
}

profiler_magento_truncate_file() {
    local _file="$1"

    mkdir -p "$(dirname "$_file")" || return 1
    : > "$_file"
}

profiler_connector_logs_truncate() {
    local _target="${1:-all}"

    if [ ! -t 0 ] && [ "$PROFILER_FORCE" != "1" ]; then
        warp_message_error "log truncation in non-interactive mode requires --force"
        return 1
    fi

    case "$_target" in
        db)
            profiler_magento_truncate_file "$PROFILER_MAGENTO_DB_LOG" || return 1
            profiler_print_kv "truncated" "var/debug/db.log"
            ;;
        profiler|php)
            profiler_magento_truncate_file "$PROFILER_MAGENTO_CSV_LOG" || return 1
            profiler_print_kv "truncated" "var/log/profiler.csv"
            ;;
        all)
            profiler_magento_truncate_file "$PROFILER_MAGENTO_DB_LOG" || return 1
            profiler_magento_truncate_file "$PROFILER_MAGENTO_CSV_LOG" || return 1
            profiler_print_kv "truncated" "var/debug/db.log"
            profiler_print_kv "truncated" "var/log/profiler.csv"
            ;;
        *)
            warp_message_error "unknown profiler log target: $_target"
            return 1
            ;;
    esac
}

profiler_connector_status() {
    local _summary=""

    warp_message_info "Profiler status"
    warp_message "---------------"
    profiler_print_kv "connector" "magento"
    profiler_print_kv "php profiler" "$(profiler_magento_php_state)"
    profiler_print_kv "profiler flag" "var/profiler.flag"

    _summary=$(profiler_magento_env_summary)
    profiler_print_kv "MAGE_MODE" "$(printf '%s\n' "$_summary" | awk -F= '$1 == "mode" {print $2; exit}')"
    profiler_print_kv "DB logger" "$(printf '%s\n' "$_summary" | awk -F= '$1 == "db_logger" {print $2; exit}')"
    profiler_print_kv "Smile DB profiler" "$(printf '%s\n' "$_summary" | awk -F= '$1 == "smile_profiler" {print $2; exit}')"
    profiler_print_kv "var/debug/db.log" "$(profiler_magento_log_size "$PROFILER_MAGENTO_DB_LOG")"
    profiler_print_kv "var/log/profiler.csv" "$(profiler_magento_log_size "$PROFILER_MAGENTO_CSV_LOG")"
}

profiler_connector_php_enable() {
    local _mode="${1:-html}"

    mkdir -p "$PROJECTPATH/var/log" || return 1
    case "$_mode" in
        html)
            printf '%s' "html" > "$PROFILER_MAGENTO_PHP_FLAG" || return 1
            ;;
        csv)
            printf '%s' '{"drivers":[{"type":"csvfile","filePath":"var/log/profiler.csv"}]}' > "$PROFILER_MAGENTO_PHP_FLAG" || return 1
            profiler_magento_truncate_file "$PROFILER_MAGENTO_CSV_LOG" || return 1
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
    rm -f "$PROFILER_MAGENTO_PHP_FLAG" || return 1
    profiler_magento_truncate_file "$PROFILER_MAGENTO_CSV_LOG" || return 1
    warp_message_info "PHP profiler disabled."
    profiler_print_kv "truncated" "var/log/profiler.csv"
}

profiler_connector_db_enable() {
    local _mode="${1:-controlled}"

    case "$_mode" in
        controlled|full)
            ;;
        *)
            warp_message_error "unknown DB profiler mode: $_mode"
            return 1
            ;;
    esac

    profiler_magento_write_env "enable-db" "$_mode" || return 1
    profiler_magento_truncate_file "$PROFILER_MAGENTO_DB_LOG" || return 1
    warp_message_info "DB logger enabled: $_mode"
    profiler_print_kv "truncated" "var/debug/db.log"
    profiler_magento_cache_clean
}

profiler_connector_db_disable() {
    profiler_magento_write_env "disable-db" "disabled" || return 1
    profiler_magento_truncate_file "$PROFILER_MAGENTO_DB_LOG" || return 1
    warp_message_info "DB logger disabled."
    profiler_print_kv "Smile DB profiler" "disabled when present"
    profiler_print_kv "truncated" "var/debug/db.log"
    profiler_magento_cache_clean
}

profiler_connector_help() {
    profiler_help_usage
}
