#!/bin/bash

warp_cache_engine_resolve() {
    local _engine="${1:-}"

    if [ -z "$_engine" ] && [ -n "${CACHE_ENGINE_SELECTED:-}" ]; then
        _engine="$CACHE_ENGINE_SELECTED"
    fi

    if [ -z "$_engine" ] && [ -n "${CACHE_ENGINE:-}" ]; then
        _engine="$CACHE_ENGINE"
    fi

    if [ -z "$_engine" ] && command -v warp_fallback_env_get >/dev/null 2>&1; then
        _engine=$(warp_fallback_env_get CACHE_ENGINE)
    fi

    case "$_engine" in
        valkey)
            printf '%s\n' "valkey"
            ;;
        *)
            printf '%s\n' "redis"
            ;;
    esac
}

warp_cache_engine_server_bin() {
    case "$(warp_cache_engine_resolve "$1")" in
        valkey) printf '%s\n' "valkey-server" ;;
        *) printf '%s\n' "redis-server" ;;
    esac
}

warp_cache_engine_cli_bin() {
    case "$(warp_cache_engine_resolve "$1")" in
        valkey) printf '%s\n' "valkey-cli" ;;
        *) printf '%s\n' "redis-cli" ;;
    esac
}

warp_cache_engine_container_user() {
    case "$(warp_cache_engine_resolve "$1")" in
        valkey) printf '%s\n' "valkey" ;;
        *) printf '%s\n' "redis" ;;
    esac
}

warp_cache_engine_container_config_path() {
    case "$(warp_cache_engine_resolve "$1")" in
        valkey) printf '%s\n' "/usr/local/etc/valkey/valkey.conf" ;;
        *) printf '%s\n' "/usr/local/etc/redis/redis.conf" ;;
    esac
}

warp_cache_engine_default_host_config() {
    case "$(warp_cache_engine_resolve "$1")" in
        valkey) printf '%s\n' "./.warp/docker/config/redis/valkey.conf" ;;
        *) printf '%s\n' "./.warp/docker/config/redis/redis.conf" ;;
    esac
}

warp_cache_engine_recommended_from_context() {
    if command -v warp_app_context_detect >/dev/null 2>&1; then
        warp_app_context_detect >/dev/null 2>&1 || true
        if command -v warp_app_context_cache_supports_valkey >/dev/null 2>&1 && warp_app_context_cache_supports_valkey; then
            printf '%s\n' "valkey"
            return 0
        fi
    fi

    printf '%s\n' "redis"
}
