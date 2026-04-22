#!/bin/bash

warp_php_config_ensure_bind_file() {
    local _target="$1"
    local _sample="${2:-}"
    local _label="${3:-PHP config file}"
    local _target_dir=""

    _target_dir=$(dirname "$_target")

    mkdir -p "$_target_dir" || {
        warp_message_error "could not create PHP config directory: $_target_dir"
        return 1
    }

    if [ -f "$_target" ]; then
        return 0
    fi

    if [ -d "$_target" ]; then
        if rmdir "$_target" 2>/dev/null; then
            warp_message_warn "${_label} was a directory; recreated it as a file: $_target"
        else
            warp_message_error "${_label} is a non-empty directory and cannot be used as a file bind mount: $_target"
            warp_message_error "move or remove that directory, then rerun warp"
            return 1
        fi
    fi

    if [ -n "$_sample" ] && [ -f "$_sample" ]; then
        cp "$_sample" "$_target" || {
            warp_message_error "could not create ${_label} from sample: $_target"
            return 1
        }
        return 0
    fi

    touch "$_target" || {
        warp_message_error "could not create ${_label}: $_target"
        return 1
    }
}

warp_php_config_ensure_xdebug_file() {
    local _config_dir="$PROJECTPATH/.warp/docker/config/php"
    local _target="$_config_dir/ext-xdebug.ini"
    local _managed_disabled="$_config_dir/managed/ext-xdebug.disabled.ini.sample"
    local _legacy_sample="$_config_dir/ext-xdebug.ini.sample"
    local _setup_managed_disabled="$PROJECTPATH/.warp/setup/php/config/php/managed/ext-xdebug.disabled.ini.sample"
    local _sample=""

    if [ -f "$_managed_disabled" ]; then
        _sample="$_managed_disabled"
    elif [ -f "$_legacy_sample" ]; then
        _sample="$_legacy_sample"
    elif [ -f "$_setup_managed_disabled" ]; then
        _sample="$_setup_managed_disabled"
    fi

    warp_php_config_ensure_bind_file "$_target" "$_sample" "Xdebug config file"
}

warp_php_config_ensure_opcache_file() {
    local _config_dir="$PROJECTPATH/.warp/docker/config/php"
    local _target="$_config_dir/zz-warp-opcache.ini"
    local _managed_disable="$_config_dir/managed/zz-warp-opcache-disable.ini.sample"
    local _setup_managed_disable="$PROJECTPATH/.warp/setup/php/config/php/managed/zz-warp-opcache-disable.ini.sample"
    local _volume=""
    local _sample=""

    _volume=$(warp_env_read_var WARP_PHP_OPCACHE_VOLUME)
    case "$_volume" in
        *".warp/docker/config/php/zz-warp-opcache.ini:"*)
            ;;
        *)
            return 0
            ;;
    esac

    if [ -f "$_managed_disable" ]; then
        _sample="$_managed_disable"
    elif [ -f "$_setup_managed_disable" ]; then
        _sample="$_setup_managed_disable"
    fi

    warp_php_config_ensure_bind_file "$_target" "$_sample" "OPcache config file"
}
