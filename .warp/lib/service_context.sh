#!/bin/bash

# Build a capability-first runtime context from canonical + legacy vars.
# Requires .warp/lib/fallback.sh to be loaded first.

warp_service_context_reset() {
    WARP_CTX_CAPABILITY=""
    WARP_CTX_MODE="unknown"
    WARP_CTX_ENGINE="unknown"
    WARP_CTX_LOCAL_SERVICE_PRESENT="false"
    WARP_CTX_SCOPE="none"
    WARP_CTX_HOST=""
    WARP_CTX_PORT=""
    WARP_CTX_USER=""
    WARP_CTX_PASSWORD=""
    WARP_CTX_DBNAME=""
    WARP_CTX_SCHEME=""
}

warp_service_context_load_db() {
    _mode=$(warp_fallback_env_get DB_MODE)
    [ -z "$_mode" ] && _mode=$(warp_fallback_detect_db_mode)

    _engine=$(warp_fallback_env_get DB_ENGINE)
    [ -z "$_engine" ] && _engine=$(warp_fallback_detect_db_engine)

    _has_mysql=$(warp_fallback_compose_has_service mysql)

    _host=$(warp_fallback_env_get DB_HOST)
    [ -z "$_host" ] && _host=$(warp_fallback_env_get DATABASE_HOST)
    [ -z "$_host" ] && [ "$_mode" = "local" ] && _host="mysql"

    _port=$(warp_fallback_env_get DB_PORT)
    [ -z "$_port" ] && _port=$(warp_fallback_env_get DATABASE_BINDED_PORT)
    [ -z "$_port" ] && _port="3306"

    _dbname=$(warp_fallback_env_get DB_NAME)
    [ -z "$_dbname" ] && _dbname=$(warp_fallback_env_get DATABASE_NAME)

    _user=$(warp_fallback_env_get DB_USER)
    [ -z "$_user" ] && _user=$(warp_fallback_env_get DATABASE_USER)

    _password=$(warp_fallback_env_get DB_PASSWORD)
    [ -z "$_password" ] && _password=$(warp_fallback_env_get DATABASE_PASSWORD)

    WARP_CTX_CAPABILITY="db"
    WARP_CTX_MODE="${_mode:-unknown}"
    WARP_CTX_ENGINE="${_engine:-unknown}"
    WARP_CTX_LOCAL_SERVICE_PRESENT="$_has_mysql"
    WARP_CTX_SCOPE="none"
    WARP_CTX_HOST="$_host"
    WARP_CTX_PORT="$_port"
    WARP_CTX_USER="$_user"
    WARP_CTX_PASSWORD="$_password"
    WARP_CTX_DBNAME="$_dbname"
    WARP_CTX_SCHEME=""
}

warp_service_context_load_cache() {
    _mode=$(warp_fallback_env_get CACHE_MODE)
    [ -z "$_mode" ] && _mode=$(warp_fallback_detect_cache_mode)

    _engine=$(warp_fallback_env_get CACHE_ENGINE)
    [ -z "$_engine" ] && _engine=$(warp_fallback_detect_cache_engine)

    _scope=$(warp_fallback_env_get CACHE_SCOPE)
    if [ -z "$_scope" ]; then
        if [ "$_mode" = "external" ]; then
            _scope="remote"
        else
            _scope="cache"
        fi
    fi

    _has_cache=$(warp_fallback_compose_has_service redis-cache)
    _has_session=$(warp_fallback_compose_has_service redis-session)
    _has_fpc=$(warp_fallback_compose_has_service redis-fpc)
    _local_present="false"
    if [ "$_has_cache" = "true" ] || [ "$_has_session" = "true" ] || [ "$_has_fpc" = "true" ]; then
        _local_present="true"
    fi

    _host=$(warp_fallback_env_get CACHE_HOST)
    _port=$(warp_fallback_env_get CACHE_PORT)
    _user=$(warp_fallback_env_get CACHE_USER)
    _password=$(warp_fallback_env_get CACHE_PASSWORD)

    if [ "$_mode" = "local" ]; then
        case "$_scope" in
            session)
                [ -z "$_host" ] && _host="redis-session"
                [ -z "$_port" ] && _port=$(warp_fallback_env_get REDIS_SESSION_BINDED_PORT)
                ;;
            fpc)
                [ -z "$_host" ] && _host="redis-fpc"
                [ -z "$_port" ] && _port=$(warp_fallback_env_get REDIS_FPC_BINDED_PORT)
                ;;
            cache|*)
                [ -z "$_host" ] && _host="redis-cache"
                [ -z "$_port" ] && _port=$(warp_fallback_env_get REDIS_CACHE_BINDED_PORT)
                ;;
        esac
    fi

    [ -z "$_port" ] && _port="6379"

    WARP_CTX_CAPABILITY="cache"
    WARP_CTX_MODE="${_mode:-unknown}"
    WARP_CTX_ENGINE="${_engine:-unknown}"
    WARP_CTX_LOCAL_SERVICE_PRESENT="$_local_present"
    WARP_CTX_SCOPE="$_scope"
    WARP_CTX_HOST="$_host"
    WARP_CTX_PORT="$_port"
    WARP_CTX_USER="$_user"
    WARP_CTX_PASSWORD="$_password"
    WARP_CTX_DBNAME=""
    WARP_CTX_SCHEME=""
}

warp_service_context_load_search() {
    _mode=$(warp_fallback_env_get SEARCH_MODE)
    [ -z "$_mode" ] && _mode=$(warp_fallback_detect_search_mode)

    _engine=$(warp_fallback_env_get SEARCH_ENGINE)
    [ -z "$_engine" ] && _engine=$(warp_fallback_detect_search_engine)

    _has_es=$(warp_fallback_compose_has_service elasticsearch)
    _has_os=$(warp_fallback_compose_has_service opensearch)
    _local_present="false"
    if [ "$_has_es" = "true" ] || [ "$_has_os" = "true" ]; then
        _local_present="true"
    fi

    _scheme=$(warp_fallback_env_get SEARCH_SCHEME)
    [ -z "$_scheme" ] && _scheme="http"

    _host=$(warp_fallback_env_get SEARCH_HOST)
    [ -z "$_host" ] && [ "$_mode" = "local" ] && _host="elasticsearch"

    _port=$(warp_fallback_env_get SEARCH_PORT)
    [ -z "$_port" ] && _port="9200"

    _user=$(warp_fallback_env_get SEARCH_USER)
    _password=$(warp_fallback_env_get SEARCH_PASSWORD)

    WARP_CTX_CAPABILITY="search"
    WARP_CTX_MODE="${_mode:-unknown}"
    WARP_CTX_ENGINE="${_engine:-unknown}"
    WARP_CTX_LOCAL_SERVICE_PRESENT="$_local_present"
    WARP_CTX_SCOPE="none"
    WARP_CTX_HOST="$_host"
    WARP_CTX_PORT="$_port"
    WARP_CTX_USER="$_user"
    WARP_CTX_PASSWORD="$_password"
    WARP_CTX_DBNAME=""
    WARP_CTX_SCHEME="$_scheme"
}

warp_service_context_load() {
    _capability="$1"

    warp_service_context_reset

    case "$_capability" in
        db)
            warp_fallback_autopopulate_mode_engine db >/dev/null 2>&1 || true
            warp_service_context_load_db
            ;;
        cache)
            warp_fallback_autopopulate_mode_engine cache >/dev/null 2>&1 || true
            warp_service_context_load_cache
            ;;
        search)
            warp_fallback_autopopulate_mode_engine search >/dev/null 2>&1 || true
            warp_service_context_load_search
            ;;
        *)
            return 1
            ;;
    esac

    export WARP_CTX_CAPABILITY
    export WARP_CTX_MODE
    export WARP_CTX_ENGINE
    export WARP_CTX_LOCAL_SERVICE_PRESENT
    export WARP_CTX_SCOPE
    export WARP_CTX_HOST
    export WARP_CTX_PORT
    export WARP_CTX_USER
    export WARP_CTX_PASSWORD
    export WARP_CTX_DBNAME
    export WARP_CTX_SCHEME

    if [ "$WARP_CTX_MODE" = "unknown" ] && [ "$WARP_CTX_LOCAL_SERVICE_PRESENT" = "false" ]; then
        return 2
    fi

    return 0
}
