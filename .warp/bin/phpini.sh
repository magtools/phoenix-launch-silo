#!/bin/bash

. "$PROJECTPATH/.warp/bin/phpini_help.sh"

phpini_print_kv() {
    local _label="$1"
    local _value="$2"

    printf '%-28s %s\n' "${_label}:" "${_value:-unknown}"
}

phpini_env_value() {
    local _key="$1"

    warp_env_read_var "$_key"
}

phpini_configured_profile() {
    local _profile=""

    _profile=$(phpini_env_value "WARP_PHP_INI_PROFILE")
    case "$_profile" in
        legacy|managed)
            printf '%s\n' "$_profile"
            ;;
        "")
            printf '%s\n' "not set"
            ;;
        *)
            printf '%s\n' "invalid:${_profile}"
            ;;
    esac
}

phpini_php_version() {
    local _php_version=""

    _php_version=$(phpini_env_value "PHP_VERSION")
    [ -n "$_php_version" ] || _php_version=$(phpini_env_value "php_version")
    printf '%s\n' "${_php_version:-unknown}"
}

phpini_image_family() {
    local _family=""
    local _php_image=""
    local _php_image_repo=""
    local _php_version=""

    _family=$(phpini_env_value "WARP_PHP_IMAGE_FAMILY")
    case "$_family" in
        warp|magtools|summasolutions|66ecommerce|custom)
            printf '%s\n' "$_family"
            return 0
            ;;
    esac

    _php_image_repo=$(phpini_env_value "PHP_IMAGE_REPO")
    _php_version=$(phpini_php_version)
    [ -n "$_php_image_repo" ] && _php_image="${_php_image_repo}/php:${_php_version}"
    [ -n "$_php_image" ] || _php_image=$(phpini_env_value "PHP_IMAGE")
    [ -n "$_php_image" ] || _php_image=$(phpini_env_value "PHP_DOCKER_IMAGE")

    case "$_php_image" in
        warp/php:*|*/warp/php:*)
            printf '%s\n' "warp"
            ;;
        magtools/php:*|*/magtools/php:*)
            printf '%s\n' "magtools"
            ;;
        summasolutions/php:*|*/summasolutions/php:*)
            printf '%s\n' "summasolutions"
            ;;
        66ecommerce/php:*|*/66ecommerce/php:*)
            printf '%s\n' "66ecommerce"
            ;;
        "")
            printf '%s\n' "summasolutions"
            ;;
        *)
            printf '%s\n' "custom"
            ;;
    esac
}

phpini_version_is_84_or_newer() {
    local _php_version="$1"
    local _major=""
    local _minor=""

    _major=$(printf '%s\n' "$_php_version" | cut -d '.' -f1)
    _minor=$(printf '%s\n' "$_php_version" | cut -d '.' -f2 | sed 's/[^0-9].*//')

    [[ "$_major" =~ ^[0-9]+$ ]] || return 1
    [[ "$_minor" =~ ^[0-9]+$ ]] || return 1

    [ "$_major" -gt 8 ] && return 0
    [ "$_major" -eq 8 ] && [ "$_minor" -ge 4 ] && return 0

    return 1
}

phpini_effective_profile() {
    local _configured="$1"
    local _image_family="$2"
    local _php_version="$3"

    case "$_configured" in
        legacy|managed)
            printf '%s\n' "$_configured"
            return 0
            ;;
    esac

    if [ "$WARP_APP_COMPAT_PROFILE" = "magento-2.4.8+" ] \
        && [ "$_image_family" = "warp" ] \
        && phpini_version_is_84_or_newer "$_php_version"; then
        printf '%s\n' "managed"
        return 0
    fi

    printf '%s\n' "legacy"
}

phpini_profile_source() {
    local _configured="$1"

    case "$_configured" in
        legacy|managed|invalid:*)
            printf '%s\n' ".env"
            ;;
        *)
            printf '%s\n' "inferred"
            ;;
    esac
}

phpini_managed_compatible() {
    local _image_family="$1"
    local _php_version="$2"

    case "$_image_family" in
        summasolutions|66ecommerce)
            printf '%s\n' "no"
            return 0
            ;;
        warp|magtools)
            if phpini_version_is_84_or_newer "$_php_version"; then
                printf '%s\n' "yes"
            else
                printf '%s\n' "no"
            fi
            return 0
            ;;
        custom)
            printf '%s\n' "unknown"
            return 0
            ;;
    esac

    printf '%s\n' "unknown"
}

phpini_runtime_probe() {
    local _php_container=""
    local _xdebug="unknown"
    local _opcache="unknown"
    local _opcache_enable="unknown"

    command -v docker >/dev/null 2>&1 || return 0
    command -v docker-compose >/dev/null 2>&1 || return 0
    [ -f "$DOCKERCOMPOSEFILE" ] || return 0
    docker info >/dev/null 2>&1 || return 0

    _php_container=$(docker-compose -f "$DOCKERCOMPOSEFILE" ps -q php 2>/dev/null)
    [ -n "$_php_container" ] || return 0
    [ "$(docker inspect --format '{{.State.Running}}' "$_php_container" 2>/dev/null)" = "true" ] || return 0

    if docker exec "$_php_container" php -m 2>/dev/null | grep -qi '^xdebug$'; then
        _xdebug="loaded"
    else
        _xdebug="not loaded"
    fi

    if docker exec "$_php_container" php -m 2>/dev/null | grep -qi 'Zend OPcache'; then
        _opcache="loaded"
    else
        _opcache="not loaded"
    fi

    _opcache_enable=$(docker exec "$_php_container" php -i 2>/dev/null | awk -F'=> ' '/^opcache.enable =>/ {print $2; exit}' | awk '{print $1}')
    [ -n "$_opcache_enable" ] || _opcache_enable="unknown"

    phpini_print_kv "runtime xdebug" "$_xdebug"
    phpini_print_kv "runtime opcache" "$_opcache"
    phpini_print_kv "runtime opcache.enable" "$_opcache_enable"
}

phpini_status_values() {
    if declare -F warp_app_context_detect >/dev/null 2>&1; then
        warp_app_context_detect
    fi

    PHPINI_CONFIGURED_PROFILE=$(phpini_configured_profile)
    PHPINI_PHP_VERSION=$(phpini_php_version)
    PHPINI_IMAGE_FAMILY=$(phpini_image_family)
    PHPINI_EFFECTIVE_PROFILE=$(phpini_effective_profile "$PHPINI_CONFIGURED_PROFILE" "$PHPINI_IMAGE_FAMILY" "$PHPINI_PHP_VERSION")
    PHPINI_PROFILE_SOURCE=$(phpini_profile_source "$PHPINI_CONFIGURED_PROFILE")
    PHPINI_MANAGED_COMPATIBLE=$(phpini_managed_compatible "$PHPINI_IMAGE_FAMILY" "$PHPINI_PHP_VERSION")
}

phpini_profile_status() {
    phpini_status_values

    warp_message_info "PHP INI profile"
    warp_message "---------------"
    phpini_print_kv "configured profile" "$PHPINI_CONFIGURED_PROFILE"
    phpini_print_kv "effective profile" "$PHPINI_EFFECTIVE_PROFILE"
    phpini_print_kv "source" "$PHPINI_PROFILE_SOURCE"
    phpini_print_kv "app profile" "${WARP_APP_COMPAT_PROFILE:-unknown}"
    phpini_print_kv "app version" "${WARP_APP_VERSION:-unknown}"
    phpini_print_kv "php version" "$PHPINI_PHP_VERSION"
    phpini_print_kv "image family" "$PHPINI_IMAGE_FAMILY"
    phpini_print_kv "managed compatible" "$PHPINI_MANAGED_COMPATIBLE"

    phpini_runtime_probe

    if [[ "$PHPINI_CONFIGURED_PROFILE" == invalid:* ]]; then
        warp_message_warn "Invalid WARP_PHP_INI_PROFILE value: ${PHPINI_CONFIGURED_PROFILE#invalid:}"
        return 1
    fi

    return 0
}

phpini_has_flag() {
    local _needle="$1"
    shift 1
    local _arg=""

    for _arg in "$@"; do
        [ "$_arg" = "$_needle" ] && return 0
    done

    return 1
}

phpini_managed_mode() {
    local _mode="dev"
    local _arg=""

    for _arg in "$@"; do
        case "$_arg" in
            --prod)
                _mode="prod"
                ;;
            --dev)
                _mode="dev"
                ;;
        esac
    done

    printf '%s\n' "$_mode"
}

phpini_managed_validate_args() {
    local _has_dev=0
    local _has_prod=0

    phpini_has_flag "--dev" "$@" && _has_dev=1
    phpini_has_flag "--prod" "$@" && _has_prod=1

    if [ "$_has_dev" -eq 1 ] && [ "$_has_prod" -eq 1 ]; then
        warp_message_error "choose only one managed mode: --dev or --prod"
        return 1
    fi

    return 0
}

phpini_managed_opcache_sample() {
    local _mode="$1"

    case "$_mode" in
        prod)
            printf '%s\n' "zz-warp-opcache-enable.ini.sample"
            ;;
        *)
            printf '%s\n' "zz-warp-opcache-disable.ini.sample"
            ;;
    esac
}

phpini_managed_opcache_label() {
    local _mode="$1"

    case "$_mode" in
        prod)
            printf '%s\n' "production"
            ;;
        *)
            printf '%s\n' "development"
            ;;
    esac
}

phpini_samples_dir() {
    printf '%s\n' "$PROJECTPATH/features/warp-phpini-samples/managed"
}

phpini_config_dir() {
    printf '%s\n' "$PROJECTPATH/.warp/docker/config/php"
}

phpini_opcache_placeholder_volume() {
    printf '%s\n' "./.warp/docker/config/php/.warp-empty.ini:/tmp/.warp-opcache.ini"
}

phpini_opcache_managed_volume() {
    printf '%s\n' "./.warp/docker/config/php/zz-warp-opcache.ini:/usr/local/etc/php/conf.d/zz-warp-opcache.ini"
}

phpini_ensure_placeholder_file() {
    local _config_dir=""
    local _placeholder=""

    _config_dir=$(phpini_config_dir)
    _placeholder="$_config_dir/.warp-empty.ini"

    mkdir -p "$_config_dir" || return 1
    [ -f "$_placeholder" ] && return 0
    printf '%s\n' "; Empty Warp placeholder used for disabled optional PHP mounts." > "$_placeholder"
}

phpini_ensure_env_default() {
    local _key="$1"
    local _value="$2"

    if warp_env_ensure_var "$_key" "$_value"; then
        phpini_print_kv "$_key" "$(warp_env_read_var "$_key")"
        return 0
    fi

    warp_message_error "could not ensure ${_key} in .env"
    return 1
}

phpini_copy_effective_ini() {
    local _source="$1"
    local _target="$2"
    local _force="$3"
    local _label="$4"

    [ -f "$_source" ] || {
        warp_message_error "sample not found: $_source"
        return 1
    }

    if [ -f "$_target" ] && [ "$_force" != "yes" ]; then
        phpini_print_kv "$_label" "existing file kept"
        return 0
    fi

    if [ -f "$_target" ] && [ "$_force" = "yes" ]; then
        cp "$_source" "$_target" || return 1
        phpini_print_kv "$_label" "overwritten"
        return 0
    fi

    cp "$_source" "$_target" || return 1
    phpini_print_kv "$_label" "created"
}

phpini_profile_legacy_dry_run() {
    phpini_status_values

    warp_message_info "PHP INI profile dry-run"
    warp_message "-----------------------"
    phpini_print_kv "target profile" "legacy"
    phpini_print_kv "current configured" "$PHPINI_CONFIGURED_PROFILE"
    phpini_print_kv "current effective" "$PHPINI_EFFECTIVE_PROFILE"
    warp_message ""
    warp_message "Planned changes:"
    warp_message " - set WARP_PHP_INI_PROFILE=legacy in .env"
    warp_message " - keep existing .warp/docker/config/php/ext-xdebug.ini unchanged"
    warp_message " - keep existing .warp/docker/config/php/zz-warp-opcache.ini unchanged if present"
    warp_message " - do not restart containers"
    warp_message ""
    warp_message "No files were modified."
}

phpini_profile_legacy_write() {
    phpini_status_values

    warp_env_file_set_var "$ENVIRONMENTVARIABLESFILE" "WARP_PHP_INI_PROFILE" "legacy" || {
        warp_message_error "could not write WARP_PHP_INI_PROFILE=legacy to .env"
        return 1
    }

    warp_env_file_set_var "$ENVIRONMENTVARIABLESFILE" "WARP_PHP_OPCACHE_VOLUME" "$(phpini_opcache_placeholder_volume)" || {
        warp_message_error "could not write WARP_PHP_OPCACHE_VOLUME to .env"
        return 1
    }

    phpini_ensure_placeholder_file || {
        warp_message_error "could not ensure OPcache placeholder file"
        return 1
    }

    warp_message_info "PHP INI profile set to legacy."
    warp_message "Existing PHP ini files were not modified."
    phpini_print_kv "previous effective profile" "$PHPINI_EFFECTIVE_PROFILE"
    phpini_print_kv "configured profile" "legacy"
    phpini_print_kv "opcache mount" "placeholder"
}

phpini_profile_managed_dry_run() {
    local _mode=""
    local _opcache_sample=""
    local _opcache_label=""

    phpini_managed_validate_args "$@" || return 1
    _mode=$(phpini_managed_mode "$@")
    _opcache_sample=$(phpini_managed_opcache_sample "$_mode")
    _opcache_label=$(phpini_managed_opcache_label "$_mode")

    phpini_status_values

    warp_message_info "PHP INI profile dry-run"
    warp_message "-----------------------"
    phpini_print_kv "target profile" "managed"
    phpini_print_kv "current configured" "$PHPINI_CONFIGURED_PROFILE"
    phpini_print_kv "current effective" "$PHPINI_EFFECTIVE_PROFILE"
    phpini_print_kv "managed compatible" "$PHPINI_MANAGED_COMPATIBLE"
    phpini_print_kv "opcache init profile" "$_opcache_label"
    warp_message ""
    warp_message "Planned changes:"
    warp_message " - set WARP_PHP_INI_PROFILE=managed in .env"
    warp_message " - set WARP_PHP_OPCACHE_VOLUME to mount zz-warp-opcache.ini in PHP conf.d"
    warp_message " - ensure Xdebug env defaults exist in .env"
    warp_message " - copy ext-xdebug.disabled.ini.sample to .warp/docker/config/php/ext-xdebug.ini if missing"
    warp_message " - copy ${_opcache_sample} to .warp/docker/config/php/zz-warp-opcache.ini if missing"
    warp_message " - keep existing effective ini files unless --force is used"
    warp_message " - do not restart containers"
    warp_message ""

    if [ "$PHPINI_MANAGED_COMPATIBLE" = "no" ]; then
        warp_message_warn "Managed profile is not compatible with the detected PHP image family/version."
    elif [ "$PHPINI_MANAGED_COMPATIBLE" = "unknown" ]; then
        warp_message_warn "Managed profile compatibility is unknown; write mode will require --force."
    fi

    warp_message "No files were modified."
}

phpini_profile_managed_write() {
    local _mode=""
    local _opcache_sample=""
    local _opcache_label=""
    local _samples_dir=""
    local _config_dir=""
    local _force="no"

    phpini_managed_validate_args "$@" || return 1

    _mode=$(phpini_managed_mode "$@")
    _opcache_sample=$(phpini_managed_opcache_sample "$_mode")
    _opcache_label=$(phpini_managed_opcache_label "$_mode")
    _samples_dir=$(phpini_samples_dir)
    _config_dir=$(phpini_config_dir)
    phpini_has_flag "--force" "$@" && _force="yes"

    phpini_status_values

    if [ "$PHPINI_MANAGED_COMPATIBLE" = "no" ]; then
        warp_message_error "managed profile is not compatible with the detected PHP image family/version"
        phpini_print_kv "image family" "$PHPINI_IMAGE_FAMILY"
        phpini_print_kv "php version" "$PHPINI_PHP_VERSION"
        return 1
    fi

    if [ "$PHPINI_MANAGED_COMPATIBLE" = "unknown" ] && [ "$_force" != "yes" ]; then
        warp_message_error "managed profile compatibility is unknown; rerun with --force to opt in explicitly"
        phpini_print_kv "image family" "$PHPINI_IMAGE_FAMILY"
        phpini_print_kv "php version" "$PHPINI_PHP_VERSION"
        return 1
    fi

    mkdir -p "$_config_dir" || {
        warp_message_error "could not create PHP config directory: $_config_dir"
        return 1
    }

    phpini_ensure_placeholder_file || {
        warp_message_error "could not ensure OPcache placeholder file"
        return 1
    }

    warp_env_file_set_var "$ENVIRONMENTVARIABLESFILE" "WARP_PHP_INI_PROFILE" "managed" || {
        warp_message_error "could not write WARP_PHP_INI_PROFILE=managed to .env"
        return 1
    }

    warp_env_file_set_var "$ENVIRONMENTVARIABLESFILE" "WARP_PHP_OPCACHE_VOLUME" "$(phpini_opcache_managed_volume)" || {
        warp_message_error "could not write WARP_PHP_OPCACHE_VOLUME to .env"
        return 1
    }

    warp_message_info "PHP INI profile set to managed."
    phpini_print_kv "previous effective profile" "$PHPINI_EFFECTIVE_PROFILE"
    phpini_print_kv "configured profile" "managed"
    phpini_print_kv "opcache init profile" "$_opcache_label"
    phpini_print_kv "opcache mount" "managed"

    phpini_ensure_env_default "XDEBUG_MODE" "debug,develop" || return 1
    phpini_ensure_env_default "XDEBUG_START_WITH_REQUEST" "yes" || return 1
    phpini_ensure_env_default "XDEBUG_CLIENT_HOST" "host.docker.internal" || return 1
    phpini_ensure_env_default "XDEBUG_CLIENT_PORT" "9003" || return 1
    phpini_ensure_env_default "XDEBUG_IDEKEY" "PHPSTORM" || return 1

    phpini_copy_effective_ini \
        "$_samples_dir/ext-xdebug.disabled.ini.sample" \
        "$_config_dir/ext-xdebug.ini" \
        "$_force" \
        "xdebug effective config" || {
            warp_message_error "could not write Xdebug effective config"
            return 1
        }

    phpini_copy_effective_ini \
        "$_samples_dir/$_opcache_sample" \
        "$_config_dir/zz-warp-opcache.ini" \
        "$_force" \
        "opcache effective config" || {
            warp_message_error "could not write OPcache effective config"
            return 1
        }

    warp_message "Containers were not restarted."
}

phpini_profile_command() {
    local _action="${1:-status}"

    case "$_action" in
        status|"")
            phpini_profile_status
            ;;
        legacy)
            shift 1
            if phpini_has_flag "--dry-run" "$@"; then
                phpini_profile_legacy_dry_run "$@"
                return 0
            fi
            phpini_profile_legacy_write "$@"
            ;;
        managed)
            shift 1
            if phpini_has_flag "--dry-run" "$@"; then
                phpini_profile_managed_dry_run "$@"
                return $?
            fi
            phpini_profile_managed_write "$@"
            ;;
        -h|--help)
            phpini_help_usage
            ;;
        *)
            warp_message_warn "unknown phpini profile action: $_action"
            phpini_help_usage
            return 1
            ;;
    esac
}

phpini_main() {
    case "$1" in
        profile)
            shift 1
            phpini_profile_command "$@"
            exit $?
            ;;
        -h|--help|"")
            phpini_help_usage
            exit 0
            ;;
        *)
            warp_message_warn "unknown phpini command: $1"
            phpini_help_usage
            exit 1
            ;;
    esac
}
