#!/bin/bash

    # IMPORT HELP

    . "$PROJECTPATH/.warp/bin/xdebug_help.sh"

xdebug_has_flag() {
    local _needle="$1"
    shift 1
    local _arg=""

    for _arg in "$@"; do
        [ "$_arg" = "$_needle" ] && return 0
    done

    return 1
}

xdebug_print_kv() {
    local _label="$1"
    local _value="$2"

    printf '%-28s %s\n' "${_label}:" "${_value:-unknown}"
}

xdebug_profile() {
    local _profile=""

    _profile=$(warp_env_read_var "WARP_PHP_INI_PROFILE")
    printf '%s\n' "${_profile:-legacy}"
}

xdebug_config_dir() {
    printf '%s\n' "$PROJECTPATH/.warp/docker/config/php"
}

xdebug_config_file() {
    printf '%s\n' "$(xdebug_config_dir)/ext-xdebug.ini"
}

xdebug_samples_dir() {
    printf '%s\n' "$PROJECTPATH/.warp/setup/php/config/php/managed"
}

xdebug_enable_sample() {
    printf '%s\n' "$(xdebug_samples_dir)/ext-xdebug.ini.sample"
}

xdebug_disable_sample() {
    printf '%s\n' "$(xdebug_samples_dir)/ext-xdebug.disabled.ini.sample"
}

xdebug_file_state() {
    local _file=""

    _file=$(xdebug_config_file)
    [ -f "$_file" ] || {
        printf '%s\n' "missing"
        return 0
    }

    if cmp -s "$_file" "$(xdebug_enable_sample)" 2>/dev/null; then
        printf '%s\n' "enabled"
        return 0
    fi

    if cmp -s "$_file" "$(xdebug_disable_sample)" 2>/dev/null; then
        printf '%s\n' "disabled"
        return 0
    fi

    if grep -Eq '^[[:space:]]*zend_extension[[:space:]]*=' "$_file"; then
        printf '%s\n' "enabled-custom"
        return 0
    fi

    if grep -Eq '^[[:space:]]*;[[:space:]]*zend_extension[[:space:]]*=' "$_file"; then
        printf '%s\n' "disabled-custom"
        return 0
    fi

    printf '%s\n' "custom"
}

xdebug_current_file_is_managed_sample() {
    local _file=""

    _file=$(xdebug_config_file)
    [ -f "$_file" ] || return 0
    cmp -s "$_file" "$(xdebug_enable_sample)" 2>/dev/null && return 0
    cmp -s "$_file" "$(xdebug_disable_sample)" 2>/dev/null && return 0

    return 1
}

xdebug_runtime_probe() {
    local _php_container=""
    local _module="unknown"

    command -v docker >/dev/null 2>&1 || return 0
    command -v docker-compose >/dev/null 2>&1 || return 0
    [ -f "$DOCKERCOMPOSEFILE" ] || return 0
    docker info >/dev/null 2>&1 || return 0

    _php_container=$(docker-compose -f "$DOCKERCOMPOSEFILE" ps -q php 2>/dev/null)
    [ -n "$_php_container" ] || return 0
    [ "$(docker inspect --format '{{.State.Running}}' "$_php_container" 2>/dev/null)" = "true" ] || return 0

    if docker exec "$_php_container" php -m 2>/dev/null | grep -qi '^xdebug$'; then
        _module="loaded"
    else
        _module="not loaded"
    fi

    xdebug_print_kv "runtime module" "$_module"
}

xdebug_managed_status() {
    warp_message_info "Xdebug profile"
    warp_message "--------------"
    xdebug_print_kv "php ini profile" "$(xdebug_profile)"
    xdebug_print_kv "config file" ".warp/docker/config/php/ext-xdebug.ini"
    xdebug_print_kv "file state" "$(xdebug_file_state)"
    [ -f "$(xdebug_config_file)" ] || warp_message_warn "Xdebug managed ini file is missing."

    xdebug_runtime_probe
}

xdebug_managed_change() {
    local _action="$1"
    shift 1
    local _config_dir=""
    local _file=""
    local _sample=""
    local _label=""
    local _force="no"

    _config_dir=$(xdebug_config_dir)
    _file=$(xdebug_config_file)
    xdebug_has_flag "--force" "$@" && _force="yes"

    case "$_action" in
        enable)
            _sample=$(xdebug_enable_sample)
            _label="enabled"
            ;;
        disable)
            _sample=$(xdebug_disable_sample)
            _label="disabled"
            ;;
    esac

    [ -f "$_sample" ] || {
        warp_message_error "sample not found: $_sample"
        return 1
    }

    warp_message_info "Xdebug ${_action} plan"
    xdebug_print_kv "target state" "$_label"
    xdebug_print_kv "config file" ".warp/docker/config/php/ext-xdebug.ini"

    if xdebug_has_flag "--dry-run" "$@"; then
        if [ -f "$_file" ] && ! xdebug_current_file_is_managed_sample && [ "$_force" != "yes" ]; then
            xdebug_print_kv "planned action" "keep custom file"
            warp_message_warn "custom Xdebug ini exists; rerun with --force to overwrite"
        else
            xdebug_print_kv "planned action" "copy sample"
        fi
        warp_message "No files were modified."
        return 0
    fi

    if [ -f "$_file" ] && ! xdebug_current_file_is_managed_sample && [ "$_force" != "yes" ]; then
        warp_message_error "custom Xdebug ini exists; rerun with --force to overwrite"
        xdebug_print_kv "file state" "$(xdebug_file_state)"
        return 1
    fi

    mkdir -p "$_config_dir" || {
        warp_message_error "could not create PHP config directory: $_config_dir"
        return 1
    }

    cp "$_sample" "$_file" || {
        warp_message_error "could not write Xdebug managed ini"
        return 1
    }

    warp_message_info "Xdebug is ${_label}."
    xdebug_print_kv "file state" "$(xdebug_file_state)"
    warp_message "Containers were not restarted."
}

function xdebug_legacy_command()
{

    if [ "$1" = "-h" ] || [ "$1" = "--help" ]
    then
        xdebug_help_usage 
        exit 1
    fi;

    hash docker 2>/dev/null || { warp_message_error "warp framework requires \"docker\""; exit 1; }
    declare -F warp_compose_bootstrap >/dev/null 2>&1 && warp_compose_bootstrap

    if [ "$(warp_check_is_running)" = false ]; then
        warp_message_error "The containers are not running"
        warp_message_error "please, first run warp start"

        exit 1;
    fi

    if [ "$1" == "--disable" ]; then
        sed -i -e 's/^zend_extension/\;zend_extension/g' "$PROJECTPATH/.warp/docker/config/php/ext-xdebug.ini"
        warp docker stop php 
        warp docker start php 
        warp_message "Xdebug has been disabled."    
    elif [ "$1" == "--enable" ]; then
        sed -i -e 's/^\;zend_extension/zend_extension/g' "$PROJECTPATH/.warp/docker/config/php/ext-xdebug.ini"
        warp docker stop php 
        warp docker start php 
        warp_message "Xdebug has been enabled."    
    elif [ "$1" == "--status" ]; then
            [ -f "$PROJECTPATH/.warp/docker/config/php/ext-xdebug.ini" ] && grep --quiet -w "^;zend_extension" "$PROJECTPATH/.warp/docker/config/php/ext-xdebug.ini"

            # Exit status 0 means string was found
            # Exit status 1 means string was not found
            if [ $? = 1 ] ; then
                warp_message "Xdebug is enabled."    
            else
                warp_message "Xdebug is disabled."    
            fi;
    else
        warp_message_warn "Please specify either '--enable', '--disable', '--status' as an argument"
    fi
}

function xdebug_main()
{
    local _action="${1:-}"
    local _profile=""

    case "$_action" in
        enable)
            _action="--enable"
        ;;
        disable)
            _action="--disable"
        ;;
        status)
            _action="--status"
        ;;
    esac

    _profile=$(xdebug_profile)

    if [ "$_profile" = "managed" ]; then
        case "$_action" in
            --enable)
                shift 1
                xdebug_managed_change "enable" "$@"
                exit $?
            ;;

            --disable)
                shift 1
                xdebug_managed_change "disable" "$@"
                exit $?
            ;;

            --status|"")
                xdebug_managed_status
                exit $?
            ;;

            -h | --help)
                xdebug_help_usage
                exit 0
            ;;

            *)
                xdebug_help_usage
                exit 1
            ;;
        esac
    fi

    case "$_action" in
        --enable)
            xdebug_legacy_command "$_action"
        ;;

        --disable)
            xdebug_legacy_command "$_action"
        ;;

        --status)
            xdebug_legacy_command "$_action"
        ;;

        -h | --help)
            xdebug_help_usage
        ;;

        *)            
            xdebug_help_usage
        ;;
    esac
}
