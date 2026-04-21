#!/bin/bash

. "$PROJECTPATH/.warp/bin/opcache_help.sh"

opcache_print_kv() {
    local _label="$1"
    local _value="$2"

    printf '%-28s %s\n' "${_label}:" "${_value:-unknown}"
}

opcache_has_flag() {
    local _needle="$1"
    shift 1
    local _arg=""

    for _arg in "$@"; do
        [ "$_arg" = "$_needle" ] && return 0
    done

    return 1
}

opcache_config_dir() {
    printf '%s\n' "$PROJECTPATH/.warp/docker/config/php"
}

opcache_config_file() {
    printf '%s\n' "$(opcache_config_dir)/zz-warp-opcache.ini"
}

opcache_samples_dir() {
    printf '%s\n' "$PROJECTPATH/.warp/setup/php/config/php/managed"
}

opcache_enable_sample() {
    printf '%s\n' "$(opcache_samples_dir)/zz-warp-opcache-enable.ini.sample"
}

opcache_disable_sample() {
    printf '%s\n' "$(opcache_samples_dir)/zz-warp-opcache-disable.ini.sample"
}

opcache_profile() {
    local _profile=""

    _profile=$(warp_env_read_var "WARP_PHP_INI_PROFILE")
    printf '%s\n' "${_profile:-not set}"
}

opcache_file_value() {
    local _key="$1"
    local _file=""
    local _value=""

    _file=$(opcache_config_file)
    [ -f "$_file" ] || {
        printf '%s\n' "unknown"
        return 0
    }

    _value=$(awk -F= -v key="$_key" '
        $0 !~ /^[[:space:]]*;/ && $1 ~ "^[[:space:]]*" key "[[:space:]]*$" {
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2)
            print $2
            exit
        }
    ' "$_file")

    printf '%s\n' "${_value:-unknown}"
}

opcache_file_state() {
    local _file=""
    local _enabled=""

    _file=$(opcache_config_file)
    [ -f "$_file" ] || {
        printf '%s\n' "missing"
        return 0
    }

    if cmp -s "$_file" "$(opcache_enable_sample)" 2>/dev/null; then
        printf '%s\n' "enabled"
        return 0
    fi

    if cmp -s "$_file" "$(opcache_disable_sample)" 2>/dev/null; then
        printf '%s\n' "disabled"
        return 0
    fi

    _enabled=$(opcache_file_value "opcache.enable")
    case "$_enabled" in
        1|On|on|true|True)
            printf '%s\n' "enabled-custom"
            ;;
        0|Off|off|false|False)
            printf '%s\n' "disabled-custom"
            ;;
        *)
            printf '%s\n' "custom"
            ;;
    esac
}

opcache_runtime_probe() {
    local _php_container=""
    local _module="unknown"
    local _enable="unknown"
    local _enable_cli="unknown"
    local _validate_timestamps="unknown"

    command -v docker >/dev/null 2>&1 || return 0
    command -v docker-compose >/dev/null 2>&1 || return 0
    [ -f "$DOCKERCOMPOSEFILE" ] || return 0
    docker info >/dev/null 2>&1 || return 0

    _php_container=$(docker-compose -f "$DOCKERCOMPOSEFILE" ps -q php 2>/dev/null)
    [ -n "$_php_container" ] || return 0
    [ "$(docker inspect --format '{{.State.Running}}' "$_php_container" 2>/dev/null)" = "true" ] || return 0

    if docker exec "$_php_container" php -m 2>/dev/null | grep -qi 'Zend OPcache'; then
        _module="loaded"
    else
        _module="not loaded"
    fi

    _enable=$(docker exec "$_php_container" php -i 2>/dev/null | awk -F'=> ' '/^opcache.enable =>/ {print $2; exit}' | awk '{print $1}')
    _enable_cli=$(docker exec "$_php_container" php -i 2>/dev/null | awk -F'=> ' '/^opcache.enable_cli =>/ {print $2; exit}' | awk '{print $1}')
    _validate_timestamps=$(docker exec "$_php_container" php -i 2>/dev/null | awk -F'=> ' '/^opcache.validate_timestamps =>/ {print $2; exit}' | awk '{print $1}')

    opcache_print_kv "runtime module" "$_module"
    opcache_print_kv "runtime opcache.enable" "${_enable:-unknown}"
    opcache_print_kv "runtime opcache.enable_cli" "${_enable_cli:-unknown}"
    opcache_print_kv "runtime validate_timestamps" "${_validate_timestamps:-unknown}"
}

opcache_status() {
    local _file=""

    _file=$(opcache_config_file)

    warp_message_info "OPcache profile"
    warp_message "---------------"
    opcache_print_kv "php ini profile" "$(opcache_profile)"
    opcache_print_kv "config file" ".warp/docker/config/php/zz-warp-opcache.ini"
    opcache_print_kv "file state" "$(opcache_file_state)"
    opcache_print_kv "file opcache.enable" "$(opcache_file_value "opcache.enable")"
    opcache_print_kv "file opcache.enable_cli" "$(opcache_file_value "opcache.enable_cli")"
    opcache_print_kv "file validate_timestamps" "$(opcache_file_value "opcache.validate_timestamps")"
    [ -f "$_file" ] || warp_message_warn "OPcache managed ini file is missing."

    opcache_runtime_probe
}

opcache_require_managed() {
    local _profile=""

    _profile=$(opcache_profile)
    [ "$_profile" = "managed" ] && return 0

    warp_message_error "OPcache can be changed only when WARP_PHP_INI_PROFILE=managed"
    warp_message_warn "run: warp phpini profile managed --dev"
    return 1
}

opcache_target_sample() {
    local _action="$1"

    case "$_action" in
        enable)
            opcache_enable_sample
            ;;
        disable)
            opcache_disable_sample
            ;;
    esac
}

opcache_target_label() {
    local _action="$1"

    case "$_action" in
        enable)
            printf '%s\n' "production"
            ;;
        disable)
            printf '%s\n' "development"
            ;;
    esac
}

opcache_current_file_is_managed_sample() {
    local _file=""

    _file=$(opcache_config_file)
    [ -f "$_file" ] || return 0
    cmp -s "$_file" "$(opcache_enable_sample)" 2>/dev/null && return 0
    cmp -s "$_file" "$(opcache_disable_sample)" 2>/dev/null && return 0

    return 1
}

opcache_write_sample() {
    local _sample="$1"
    local _file="$2"

    if [ -f "$_file" ]; then
        : > "$_file" || return 1
        cat "$_sample" > "$_file" || return 1
        return 0
    fi

    cp "$_sample" "$_file"
}

opcache_change() {
    local _action="$1"
    shift 1
    local _config_dir=""
    local _file=""
    local _sample=""
    local _label=""
    local _force="no"

    opcache_require_managed || return 1

    _config_dir=$(opcache_config_dir)
    _file=$(opcache_config_file)
    _sample=$(opcache_target_sample "$_action")
    _label=$(opcache_target_label "$_action")
    opcache_has_flag "--force" "$@" && _force="yes"

    [ -f "$_sample" ] || {
        warp_message_error "sample not found: $_sample"
        return 1
    }

    warp_message_info "OPcache ${_action} plan"
    opcache_print_kv "target profile" "$_label"
    opcache_print_kv "config file" ".warp/docker/config/php/zz-warp-opcache.ini"

    if opcache_has_flag "--dry-run" "$@"; then
        if [ -f "$_file" ] && ! opcache_current_file_is_managed_sample && [ "$_force" != "yes" ]; then
            opcache_print_kv "planned action" "keep custom file"
            warp_message_warn "custom OPcache ini exists; rerun with --force to overwrite"
        else
            opcache_print_kv "planned action" "write sample"
        fi
        warp_message "No files were modified."
        return 0
    fi

    if [ -f "$_file" ] && ! opcache_current_file_is_managed_sample && [ "$_force" != "yes" ]; then
        warp_message_error "custom OPcache ini exists; rerun with --force to overwrite"
        opcache_print_kv "file state" "$(opcache_file_state)"
        return 1
    fi

    mkdir -p "$_config_dir" || {
        warp_message_error "could not create PHP config directory: $_config_dir"
        return 1
    }

    opcache_write_sample "$_sample" "$_file" || {
        warp_message_error "could not write OPcache managed ini"
        return 1
    }

    warp_message_info "OPcache ${_label} profile is active."
    opcache_print_kv "file state" "$(opcache_file_state)"
    opcache_print_kv "opcache.enable" "$(opcache_file_value "opcache.enable")"
    opcache_print_kv "opcache.validate_timestamps" "$(opcache_file_value "opcache.validate_timestamps")"
    warp_php_fpm_reload_or_restart "OPcache ${_label} profile" || return 1
}

opcache_disable_if_enabled() {
    local _profile=""
    local _state=""

    _profile=$(opcache_profile)
    if [ "$_profile" != "managed" ]; then
        warp_message_warn "OPcache auto-disable requires WARP_PHP_INI_PROFILE=managed; skipping."
        return 0
    fi

    _state=$(opcache_file_state)
    case "$_state" in
        enabled|enabled-custom)
            opcache_change "disable" --force
            ;;
        disabled|disabled-custom|missing)
            warp_message "OPcache already inactive; no PHP reload needed."
            return 0
            ;;
        *)
            warp_message_warn "OPcache state is $_state; leaving it unchanged."
            return 0
            ;;
    esac
}

opcache_reload_if_enabled() {
    local _profile=""
    local _state=""

    _profile=$(opcache_profile)
    if [ "$_profile" != "managed" ]; then
        warp_message_warn "OPcache reload check requires WARP_PHP_INI_PROFILE=managed; skipping."
        return 0
    fi

    _state=$(opcache_file_state)
    case "$_state" in
        enabled|enabled-custom)
            warp_php_fpm_reload_or_restart "active OPcache profile" || return 1
            ;;
        disabled|disabled-custom|missing)
            warp_message "OPcache is inactive; no PHP reload needed."
            return 0
            ;;
        *)
            warp_message_warn "OPcache state is $_state; PHP reload skipped."
            return 0
            ;;
    esac
}

opcache_main() {
    local _action="${1:-status}"

    case "$_action" in
        enable|--enable)
            shift 1
            opcache_change "enable" "$@"
            exit $?
            ;;
        disable|--disable)
            shift 1
            opcache_change "disable" "$@"
            exit $?
            ;;
        status|--status|"")
            opcache_status
            exit $?
            ;;
        -h|--help)
            opcache_help_usage
            exit 0
            ;;
        *)
            warp_message_warn "unknown opcache action: $_action"
            opcache_help_usage
            exit 1
            ;;
    esac
}
