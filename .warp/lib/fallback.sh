#!/bin/bash

# Generic fallback/config helper for capability-first commands.
# Stage A goal: centralize env/compose detection and compatibility mapping.

warp_fallback_env_has() {
    _key="$1"
    [ -n "$_key" ] || return 1
    [ -f "$ENVIRONMENTVARIABLESFILE" ] || return 1
    grep -q "^${_key}=" "$ENVIRONMENTVARIABLESFILE"
}

warp_fallback_env_get() {
    _key="$1"
    [ -n "$_key" ] || { echo ""; return 1; }
    [ -f "$ENVIRONMENTVARIABLESFILE" ] || { echo ""; return 1; }
    grep -m1 "^${_key}=" "$ENVIRONMENTVARIABLESFILE" | cut -d '=' -f2-
}

warp_fallback_env_set() {
    _key="$1"
    _value="$2"
    _tmp="$ENVIRONMENTVARIABLESFILE.warp_tmp"

    [ -n "$_key" ] || return 1
    [ -f "$ENVIRONMENTVARIABLESFILE" ] || return 1

    _safe=$(printf '%s' "$_value" | sed -e 's/[\/&#]/\\&/g')

    if grep -q "^${_key}=" "$ENVIRONMENTVARIABLESFILE" 2>/dev/null; then
        sed -e "s#^${_key}=.*#${_key}=${_safe}#g" "$ENVIRONMENTVARIABLESFILE" > "$_tmp" || return 1
        mv "$_tmp" "$ENVIRONMENTVARIABLESFILE" || return 1
    else
        echo "${_key}=${_value}" >> "$ENVIRONMENTVARIABLESFILE" || return 1
    fi

    return 0
}

warp_fallback_compose_has_service() {
    _service="$1"

    [ -n "$_service" ] || { echo false; return 0; }
    [ -f "$DOCKERCOMPOSEFILE" ] || { echo false; return 0; }

    if docker-compose -f "$DOCKERCOMPOSEFILE" config --services 2>/dev/null | grep -qx "$_service"; then
        echo true
        return 0
    fi

    if grep -Eq "^[[:space:]]*${_service}:[[:space:]]*$" "$DOCKERCOMPOSEFILE"; then
        echo true
    else
        echo false
    fi
}

warp_fallback_detect_db_mode() {
    _mode=$(warp_fallback_env_get DB_MODE)
    [ -n "$_mode" ] && { echo "$_mode"; return 0; }

    _mysql_version=$(warp_fallback_env_get MYSQL_VERSION)
    if [ "$_mysql_version" = "rds" ]; then
        echo "external"
        return 0
    fi

    _has_mysql=$(warp_fallback_compose_has_service mysql)
    if [ "$_has_mysql" = "true" ]; then
        echo "local"
        return 0
    fi

    _db_host=$(warp_fallback_env_get DATABASE_HOST)
    [ -n "$_db_host" ] && { echo "external"; return 0; }

    echo "unknown"
}

warp_fallback_detect_db_engine() {
    _engine=$(warp_fallback_env_get DB_ENGINE)
    [ -n "$_engine" ] && { echo "$_engine"; return 0; }

    _mysql_image=$(warp_fallback_env_get MYSQL_DOCKER_IMAGE)
    case "$_mysql_image" in
        mariadb:*|*/mariadb:*|*mariadb*)
            echo "mariadb"
            ;;
        *)
            echo "mysql"
            ;;
    esac
}

warp_fallback_detect_cache_mode() {
    _mode=$(warp_fallback_env_get CACHE_MODE)
    [ -n "$_mode" ] && { echo "$_mode"; return 0; }

    _has_cache=$(warp_fallback_compose_has_service redis-cache)
    _has_session=$(warp_fallback_compose_has_service redis-session)
    _has_fpc=$(warp_fallback_compose_has_service redis-fpc)
    if [ "$_has_cache" = "true" ] || [ "$_has_session" = "true" ] || [ "$_has_fpc" = "true" ]; then
        echo "local"
        return 0
    fi

    _legacy_cache_ver=$(warp_fallback_env_get REDIS_CACHE_VERSION)
    _legacy_session_ver=$(warp_fallback_env_get REDIS_SESSION_VERSION)
    _legacy_fpc_ver=$(warp_fallback_env_get REDIS_FPC_VERSION)
    if [ -n "$_legacy_cache_ver" ] || [ -n "$_legacy_session_ver" ] || [ -n "$_legacy_fpc_ver" ]; then
        echo "local"
        return 0
    fi

    _cache_host=$(warp_fallback_env_get CACHE_HOST)
    [ -z "$_cache_host" ] && _cache_host=$(warp_fallback_env_get CACHE_CACHE_HOST)
    [ -z "$_cache_host" ] && _cache_host=$(warp_fallback_env_get CACHE_FPC_HOST)
    [ -z "$_cache_host" ] && _cache_host=$(warp_fallback_env_get CACHE_SESSION_HOST)
    [ -n "$_cache_host" ] && { echo "external"; return 0; }

    echo "unknown"
}

warp_fallback_detect_cache_engine() {
    _engine=$(warp_fallback_env_get CACHE_ENGINE)
    [ -n "$_engine" ] && { echo "$_engine"; return 0; }

    if [ -f "$DOCKERCOMPOSEFILE" ] && grep -Eq 'image:[[:space:]]*(valkey|.*/valkey):' "$DOCKERCOMPOSEFILE"; then
        echo "valkey"
        return 0
    fi

    echo "redis"
}

warp_fallback_detect_search_mode() {
    _mode=$(warp_fallback_env_get SEARCH_MODE)
    [ -n "$_mode" ] && { echo "$_mode"; return 0; }

    _has_es=$(warp_fallback_compose_has_service elasticsearch)
    _has_os=$(warp_fallback_compose_has_service opensearch)
    if [ "$_has_es" = "true" ] || [ "$_has_os" = "true" ]; then
        echo "local"
        return 0
    fi

    _legacy_es_ver=$(warp_fallback_env_get ES_VERSION)
    [ -n "$_legacy_es_ver" ] && { echo "local"; return 0; }

    _search_host=$(warp_fallback_env_get SEARCH_HOST)
    [ -n "$_search_host" ] && { echo "external"; return 0; }

    echo "unknown"
}

warp_fallback_detect_search_engine() {
    _engine=$(warp_fallback_env_get SEARCH_ENGINE)
    [ -n "$_engine" ] && { echo "$_engine"; return 0; }

    if [ -f "$DOCKERCOMPOSEFILE" ] && grep -Eq 'image:[[:space:]]*opensearchproject/opensearch:' "$DOCKERCOMPOSEFILE"; then
        echo "opensearch"
        return 0
    fi

    echo "elasticsearch"
}

warp_fallback_autopopulate_mode_engine() {
    _capability="$1"

    [ -f "$ENVIRONMENTVARIABLESFILE" ] || return 10

    case "$_capability" in
        db)
            _mode=$(warp_fallback_detect_db_mode)
            _engine=$(warp_fallback_detect_db_engine)
            [ -n "$(warp_fallback_env_get DB_MODE)" ] || [ "$_mode" = "unknown" ] || warp_fallback_env_set DB_MODE "$_mode"
            [ -n "$(warp_fallback_env_get DB_ENGINE)" ] || [ "$_engine" = "unknown" ] || warp_fallback_env_set DB_ENGINE "$_engine"
            ;;
        cache)
            _mode=$(warp_fallback_detect_cache_mode)
            _engine=$(warp_fallback_detect_cache_engine)
            _scope=$(warp_fallback_env_get CACHE_SCOPE)
            [ -n "$(warp_fallback_env_get CACHE_MODE)" ] || [ "$_mode" = "unknown" ] || warp_fallback_env_set CACHE_MODE "$_mode"
            [ -n "$(warp_fallback_env_get CACHE_ENGINE)" ] || [ "$_engine" = "unknown" ] || warp_fallback_env_set CACHE_ENGINE "$_engine"
            if [ -z "$_scope" ]; then
                if [ "$_mode" = "external" ]; then
                    warp_fallback_env_set CACHE_SCOPE "remote"
                elif [ "$_mode" = "local" ]; then
                    warp_fallback_env_set CACHE_SCOPE "cache"
                fi
            fi
            ;;
        search)
            _mode=$(warp_fallback_detect_search_mode)
            _engine=$(warp_fallback_detect_search_engine)
            [ -n "$(warp_fallback_env_get SEARCH_MODE)" ] || [ "$_mode" = "unknown" ] || warp_fallback_env_set SEARCH_MODE "$_mode"
            [ -n "$(warp_fallback_env_get SEARCH_ENGINE)" ] || [ "$_engine" = "unknown" ] || warp_fallback_env_set SEARCH_ENGINE "$_engine"
            ;;
        *)
            return 1
            ;;
    esac

    return 0
}

warp_fallback_require_vars() {
    _capability="$1"
    shift

    [ "$#" -gt 0 ] || return 0

    warp_fallback_autopopulate_mode_engine "$_capability" >/dev/null 2>&1 || true

    for _key in "$@"; do
        _value=$(warp_fallback_env_get "$_key")
        [ -n "$_value" ] || return 10
    done

    return 0
}

warp_fallback_bootstrap_if_needed() {
    _capability="$1"

    case "$_capability" in
        db)
            if command -v mysql_external_bootstrap_if_needed >/dev/null 2>&1; then
                mysql_external_bootstrap_if_needed
                return $?
            fi
            return 0
            ;;
        cache|search)
            # Stage A: no interactive bootstrap for cache/search yet.
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

warp_fallback_require_running_or_external() {
    _capability="$1"

    if command -v warp_service_context_load >/dev/null 2>&1; then
        warp_service_context_load "$_capability" >/dev/null 2>&1 || return 12
        if [ "$WARP_CTX_MODE" = "external" ]; then
            return 0
        fi
        if [ "$WARP_CTX_MODE" = "local" ]; then
            [ "$(warp_check_is_running)" = "true" ] && return 0
            return 14
        fi
        return 12
    fi

    # Conservative fallback if service context is not loaded.
    [ "$(warp_check_is_running)" = "true" ] && return 0
    return 14
}

warp_runtime_mode_env_raw() {
    _mode=$(warp_fallback_env_get WARP_RUNTIME_MODE | tr '[:upper:]' '[:lower:]')
    case "$_mode" in
        host|docker|auto) echo "$_mode" ;;
        *) echo "" ;;
    esac
}

warp_runtime_command_supports_host() {
    _cmd="$1"
    case "$_cmd" in
        composer|php|magento|ece-tools|ece-patches|telemetry|db|mysql|cache|redis|valkey|search|elasticsearch|opensearch|info)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

warp_runtime_mode_set() {
    _mode="$1"
    case "$_mode" in
        host|docker|auto) ;;
        *) return 1 ;;
    esac
    warp_fallback_env_set WARP_RUNTIME_MODE "$_mode"
}

warp_runtime_mode_prompt_if_needed() {
    _cmd="$1"
    [ -f "$DOCKERCOMPOSEFILE" ] && return 0

    _mode=$(warp_runtime_mode_env_raw)
    [ -n "$_mode" ] && [ "$_mode" != "auto" ] && return 0

    warp_runtime_command_supports_host "$_cmd" || return 0

    [ -t 0 ] || return 0
    [ -t 1 ] || return 0
    [ -n "$CI" ] && return 0

    _answer=$(warp_question_ask_default "docker-compose-warp.yml not found. Does this project run in host mode? $(warp_message_info [Y/n]) " "Y")
    case "$_answer" in
        Y|y)
            warp_runtime_mode_set host >/dev/null 2>&1 || true
            ;;
        N|n)
            warp_runtime_mode_set docker >/dev/null 2>&1 || true
            ;;
        *)
            # Keep auto/default when answer is invalid.
            ;;
    esac
}

warp_runtime_mode_resolve() {
    _cmd="$1"
    warp_runtime_mode_prompt_if_needed "$_cmd"

    _mode=$(warp_runtime_mode_env_raw)
    case "$_mode" in
        host|docker)
            echo "$_mode"
            return 0
            ;;
    esac

    if [ -f "$DOCKERCOMPOSEFILE" ]; then
        echo "docker"
        return 0
    fi

    if warp_runtime_command_supports_host "$_cmd"; then
        echo "host"
    else
        echo "docker"
    fi
}

warp_fallback_confirm_explicit_yes() {
    _prompt="$1"
    _ans=$(warp_question_ask "$_prompt")
    [ "$_ans" = "y" ] || [ "$_ans" = "Y" ]
}
