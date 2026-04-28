#!/bin/bash

. "$PROJECTPATH/.warp/bin/cache_help.sh"

cache_envphp_trim() {
    printf '%s' "$1" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

cache_read_envphp_path() {
    local _file="$1"
    local _path="$2"

    awk -v want_path="$_path" '
        function trim(s) {
            sub(/^[[:space:]]+/, "", s)
            sub(/[[:space:]]+$/, "", s)
            return s
        }
        function line_delta(text,    opens, closes, tmp) {
            tmp = text
            opens = gsub(/\[/, "[", tmp)
            tmp = text
            closes = gsub(/\]/, "]", tmp)
            return opens - closes
        }
        function build_parent_path(    i, parts) {
            parts = ""
            for (i = 1; i <= depth; i++) {
                if (stack[i] == "") {
                    continue
                }
                if (parts != "") {
                    parts = parts "."
                }
                parts = parts stack[i]
            }
            return parts
        }
        {
            delta = line_delta($0)

            if (match($0, /'\''[^'\'']+'\''[[:space:]]*=>[[:space:]]*\[/)) {
                key = substr($0, RSTART + 1, RLENGTH)
                sub(/'\''[[:space:]]*=>[[:space:]]*\[$/, "", key)
                key = trim(key)
                stack[depth + 1] = key
            } else if (match($0, /'\''[^'\'']+'\''[[:space:]]*=>[[:space:]]*'\''[^'\'']*'\''/)) {
                entry = substr($0, RSTART, RLENGTH)
                key = entry
                sub(/'\''[[:space:]]*=>.*/, "", key)
                gsub(/^'\''|'\''$/, "", key)
                value = entry
                sub(/^.*=>[[:space:]]*'\''/, "", value)
                sub(/'\''$/, "", value)
                current = build_parent_path()
                candidate = (current != "" ? current "." key : key)
                if (candidate == want_path) {
                    print value
                    exit
                }
            } else if (match($0, /'\''[^'\'']+'\''[[:space:]]*=>[[:space:]]*[0-9]+/)) {
                entry = substr($0, RSTART, RLENGTH)
                key = entry
                sub(/'\''[[:space:]]*=>.*/, "", key)
                gsub(/^'\''|'\''$/, "", key)
                value = entry
                sub(/^.*=>[[:space:]]*/, "", value)
                current = build_parent_path()
                candidate = (current != "" ? current "." key : key)
                if (candidate == want_path) {
                    print value
                    exit
                }
            }

            depth += delta
            if (depth < 0) {
                depth = 0
            }
            for (i = depth + 1; i < 64; i++) {
                delete stack[i]
            }
        }
    ' "$_file" 2>/dev/null
}

cache_endpoint_parse() {
    local _raw="$1"
    local _endpoint=""
    local _host=""
    local _port=""

    _raw=$(cache_envphp_trim "$_raw")
    [ -z "$_raw" ] && return 1

    _endpoint="${_raw%%,*}"
    _endpoint=$(cache_envphp_trim "$_endpoint")
    _endpoint="${_endpoint#*://}"
    _endpoint="${_endpoint##*@}"

    if [[ "$_endpoint" == *:* ]]; then
        _port="${_endpoint##*:}"
        _host="${_endpoint%:*}"
        if ! [[ "$_port" =~ ^[0-9]+$ ]]; then
            _host="$_endpoint"
            _port=""
        fi
    else
        _host="$_endpoint"
    fi

    echo "host=$_host"
    echo "port=$_port"
}

cache_kv_value() {
    local _data="$1"
    local _key="$2"

    printf '%s\n' "$_data" | awk -F= -v want="$_key" '$1 == want { print substr($0, length(want) + 2); exit }'
}

cache_scope_default_db() {
    case "$1" in
        cache) echo "0" ;;
        fpc) echo "1" ;;
        session) echo "2" ;;
        *) echo "" ;;
    esac
}

cache_scope_env_prefix() {
    case "$1" in
        cache) echo "CACHE_CACHE" ;;
        fpc) echo "CACHE_FPC" ;;
        session) echo "CACHE_SESSION" ;;
        *) echo "" ;;
    esac
}

cache_scope_resolve_arg() {
    case "$1" in
        ""|cache) echo "cache" ;;
        session) echo "session" ;;
        fpc) echo "fpc" ;;
        --all) echo "--all" ;;
        *) echo "" ;;
    esac
}

cache_prompt_required() {
    local _label="$1"
    local _default="$2"
    local _value=""

    while :; do
        _value=$(warp_question_ask_default "$_label " "$_default")
        _value=$(cache_envphp_trim "$_value")
        [ -n "$_value" ] && { echo "$_value"; return 0; }
        warp_message_warn "Value required."
    done
}

cache_external_primary_host() {
    local _data="$1"
    local _host=""

    _host=$(cache_kv_value "$_data" "cache_host")
    [ -z "$_host" ] && _host=$(cache_kv_value "$_data" "fpc_host")
    [ -z "$_host" ] && _host=$(cache_kv_value "$_data" "session_host")
    echo "$_host"
}

cache_external_collect_from_envphp() {
    local _envphp="$PROJECTPATH/app/etc/env.php"
    local _cache_server=""
    local _cache_parsed=""
    local _cache_host=""
    local _cache_port=""
    local _cache_db=""
    local _cache_user=""
    local _cache_password=""
    local _fpc_server=""
    local _fpc_parsed=""
    local _fpc_host=""
    local _fpc_port=""
    local _fpc_db=""
    local _fpc_user=""
    local _fpc_password=""
    local _session_host_raw=""
    local _session_parsed=""
    local _session_host=""
    local _session_port=""
    local _session_db=""
    local _session_user=""
    local _session_password=""

    [ -f "$_envphp" ] || return 1

    _cache_server=$(cache_read_envphp_path "$_envphp" "cache.frontend.default.backend_options.server")
    if [ -n "$_cache_server" ]; then
        _cache_parsed=$(cache_endpoint_parse "$_cache_server")
        _cache_host=$(cache_kv_value "$_cache_parsed" "host")
        _cache_port=$(cache_kv_value "$_cache_parsed" "port")
    fi
    [ -z "$_cache_port" ] && _cache_port=$(cache_read_envphp_path "$_envphp" "cache.frontend.default.backend_options.port")
    _cache_db=$(cache_read_envphp_path "$_envphp" "cache.frontend.default.backend_options.database")
    _cache_user=$(cache_read_envphp_path "$_envphp" "cache.frontend.default.backend_options.username")
    _cache_password=$(cache_read_envphp_path "$_envphp" "cache.frontend.default.backend_options.password")

    _fpc_server=$(cache_read_envphp_path "$_envphp" "cache.frontend.page_cache.backend_options.server")
    if [ -n "$_fpc_server" ]; then
        _fpc_parsed=$(cache_endpoint_parse "$_fpc_server")
        _fpc_host=$(cache_kv_value "$_fpc_parsed" "host")
        _fpc_port=$(cache_kv_value "$_fpc_parsed" "port")
    fi
    [ -z "$_fpc_port" ] && _fpc_port=$(cache_read_envphp_path "$_envphp" "cache.frontend.page_cache.backend_options.port")
    _fpc_db=$(cache_read_envphp_path "$_envphp" "cache.frontend.page_cache.backend_options.database")
    _fpc_user=$(cache_read_envphp_path "$_envphp" "cache.frontend.page_cache.backend_options.username")
    _fpc_password=$(cache_read_envphp_path "$_envphp" "cache.frontend.page_cache.backend_options.password")

    _session_host_raw=$(cache_read_envphp_path "$_envphp" "session.redis.host")
    if [ -n "$_session_host_raw" ]; then
        _session_parsed=$(cache_endpoint_parse "$_session_host_raw")
        _session_host=$(cache_kv_value "$_session_parsed" "host")
        _session_port=$(cache_kv_value "$_session_parsed" "port")
    fi
    [ -z "$_session_port" ] && _session_port=$(cache_read_envphp_path "$_envphp" "session.redis.port")
    _session_db=$(cache_read_envphp_path "$_envphp" "session.redis.database")
    _session_user=$(cache_read_envphp_path "$_envphp" "session.redis.username")
    _session_password=$(cache_read_envphp_path "$_envphp" "session.redis.password")

    [ -z "$_cache_host" ] && _cache_host="$_fpc_host"
    [ -z "$_cache_host" ] && _cache_host="$_session_host"
    [ -z "$_cache_port" ] && _cache_port="$_fpc_port"
    [ -z "$_cache_port" ] && _cache_port="$_session_port"
    [ -z "$_cache_user" ] && _cache_user="$_fpc_user"
    [ -z "$_cache_user" ] && _cache_user="$_session_user"
    [ -z "$_cache_password" ] && _cache_password="$_fpc_password"
    [ -z "$_cache_password" ] && _cache_password="$_session_password"

    [ -z "$_fpc_host" ] && _fpc_host="$_cache_host"
    [ -z "$_fpc_port" ] && _fpc_port="$_cache_port"
    [ -z "$_fpc_user" ] && _fpc_user="$_cache_user"
    [ -z "$_fpc_password" ] && _fpc_password="$_cache_password"

    [ -z "$_session_host" ] && _session_host="$_cache_host"
    [ -z "$_session_port" ] && _session_port="$_cache_port"
    [ -z "$_session_user" ] && _session_user="$_cache_user"
    [ -z "$_session_password" ] && _session_password="$_cache_password"

    [ -z "$_cache_db" ] && _cache_db="$(cache_scope_default_db cache)"
    [ -z "$_fpc_db" ] && _fpc_db="$(cache_scope_default_db fpc)"
    [ -z "$_session_db" ] && _session_db="$(cache_scope_default_db session)"
    [ -z "$_cache_port" ] && _cache_port="6379"
    [ -z "$_fpc_port" ] && _fpc_port="6379"
    [ -z "$_session_port" ] && _session_port="6379"

    if [ -n "$_cache_host" ] || [ -n "$_fpc_host" ] || [ -n "$_session_host" ]; then
        echo "cache_host=$_cache_host"
        echo "cache_port=$_cache_port"
        echo "cache_db=$_cache_db"
        echo "cache_user=$_cache_user"
        echo "cache_password=$_cache_password"
        echo "fpc_host=$_fpc_host"
        echo "fpc_port=$_fpc_port"
        echo "fpc_db=$_fpc_db"
        echo "fpc_user=$_fpc_user"
        echo "fpc_password=$_fpc_password"
        echo "session_host=$_session_host"
        echo "session_port=$_session_port"
        echo "session_db=$_session_db"
        echo "session_user=$_session_user"
        echo "session_password=$_session_password"
        return 0
    fi

    return 1
}

cache_external_bootstrap_if_needed() {
    local _mode=""
    local _has_cache=""
    local _has_session=""
    local _has_fpc=""
    local _answer=""
    local _data=""
    local _engine=""
    local _primary_host=""
    local _scope=""
    local _prefix=""
    local _host=""
    local _port=""
    local _db=""
    local _user=""
    local _password=""
    local _seed_host=""
    local _seed_port=""
    local _seed_user=""
    local _seed_password=""

    _mode=$(warp_fallback_env_get CACHE_MODE)
    [ "$_mode" = "external" ] && return 0

    _has_cache=$(warp_fallback_compose_has_service redis-cache)
    _has_session=$(warp_fallback_compose_has_service redis-session)
    _has_fpc=$(warp_fallback_compose_has_service redis-fpc)
    if [ "$_has_cache" = "true" ] || [ "$_has_session" = "true" ] || [ "$_has_fpc" = "true" ]; then
        return 0
    fi

    if [ -n "$(warp_fallback_env_get CACHE_HOST)" ] || [ -n "$(warp_fallback_env_get CACHE_CACHE_HOST)" ] || [ -n "$(warp_fallback_env_get CACHE_FPC_HOST)" ] || [ -n "$(warp_fallback_env_get CACHE_SESSION_HOST)" ]; then
        return 0
    fi

    _answer=$(warp_question_ask_default "Cache service not found in docker-compose. Is cache external? $(warp_message_info [Y/n]) " "Y")
    if [ "$_answer" != "Y" ] && [ "$_answer" != "y" ]; then
        warp_message_error "Cache service is not configured and external mode was not confirmed."
        return 1
    fi

    warp_message_info "Trying to detect external cache settings from app/etc/env.php"
    _engine=$(warp_fallback_detect_cache_engine)
    if _data=$(cache_external_collect_from_envphp); then
        _primary_host=$(cache_external_primary_host "$_data")
        [ -n "$_primary_host" ] && warp_message_ok "Detected cache endpoints in app/etc/env.php"
    else
        warp_message_warn "No cache settings detected in app/etc/env.php. Please complete at least the cache endpoint below."
    fi

    for _scope in cache fpc session; do
        _prefix=$(cache_scope_env_prefix "$_scope")
        _host=$(cache_kv_value "$_data" "${_scope}_host")
        _port=$(cache_kv_value "$_data" "${_scope}_port")
        _db=$(cache_kv_value "$_data" "${_scope}_db")
        _user=$(cache_kv_value "$_data" "${_scope}_user")
        _password=$(cache_kv_value "$_data" "${_scope}_password")

        if [ "$_scope" = "cache" ]; then
            [ -z "$_host" ] && _host=$(cache_prompt_required "CACHE_CACHE_HOST:" "")
            [ -z "$_port" ] && _port="6379"
            [ -z "$_db" ] && _db=$(cache_scope_default_db "$_scope")
            _seed_host="$_host"
            _seed_port="$_port"
            _seed_user="$_user"
            _seed_password="$_password"
        else
            [ -z "$_host" ] && _host="$_seed_host"
            [ -z "$_port" ] && _port="$_seed_port"
            [ -z "$_user" ] && _user="$_seed_user"
            [ -z "$_password" ] && _password="$_seed_password"
        fi

        [ -z "$_port" ] && _port="6379"
        [ -z "$_db" ] && _db=$(cache_scope_default_db "$_scope")

        warp_fallback_env_set "${_prefix}_HOST" "$_host"
        warp_fallback_env_set "${_prefix}_PORT" "$_port"
        warp_fallback_env_set "${_prefix}_DB" "$_db"
        warp_fallback_env_set "${_prefix}_USER" "$_user"
        warp_fallback_env_set "${_prefix}_PASSWORD" "$_password"
    done

    warp_fallback_env_set "CACHE_MODE" "external"
    warp_fallback_env_set "CACHE_ENGINE" "$_engine"
    warp_fallback_env_set "CACHE_SCOPE" "cache"
    warp_fallback_env_set "CACHE_HOST" "$(warp_fallback_env_get CACHE_CACHE_HOST)"
    warp_fallback_env_set "CACHE_PORT" "$(warp_fallback_env_get CACHE_CACHE_PORT)"
    warp_fallback_env_set "CACHE_USER" "$(warp_fallback_env_get CACHE_CACHE_USER)"
    warp_fallback_env_set "CACHE_PASSWORD" "$(warp_fallback_env_get CACHE_CACHE_PASSWORD)"

    warp_message_ok "External cache settings updated in $(basename "$ENVIRONMENTVARIABLESFILE")"
    return 0
}

cache_load_context() {
    local _scope="$1"

    WARP_CACHE_SCOPE_OVERRIDE=""
    [ -n "$_scope" ] && WARP_CACHE_SCOPE_OVERRIDE="$_scope"
    cache_external_bootstrap_if_needed || true
    warp_fallback_bootstrap_if_needed cache >/dev/null 2>&1 || true
    warp_service_context_load cache >/dev/null 2>&1 || true
    WARP_CACHE_SCOPE_OVERRIDE=""
}

cache_pick_external_cli_bin() {
    local _engine=""

    _engine=$(warp_cache_engine_resolve "${CACHE_ENGINE:-$(warp_fallback_env_get CACHE_ENGINE)}")
    if [ "$_engine" = "valkey" ]; then
        if command -v valkey-cli >/dev/null 2>&1; then
            echo "valkey-cli"
            return 0
        fi
        if command -v redis-cli >/dev/null 2>&1; then
            echo "redis-cli"
            return 0
        fi
    else
        if command -v redis-cli >/dev/null 2>&1; then
            echo "redis-cli"
            return 0
        fi
        if command -v valkey-cli >/dev/null 2>&1; then
            echo "valkey-cli"
            return 0
        fi
    fi
    echo ""
}

cache_external_cli_required() {
    CACHE_EXTERNAL_CLI_BIN=$(cache_pick_external_cli_bin)
    if [ -z "$CACHE_EXTERNAL_CLI_BIN" ]; then
        warp_message_error "redis-cli/valkey-cli not found on host."
        warp_message_warn "Install redis-tools or valkey tools and retry."
        return 1
    fi
    return 0
}

cache_print_external_connection_details() {
    local _reason="$1"

    warp_message ""
    warp_message_warn "External cache connection failed."
    [ -n "$_reason" ] && warp_message_warn "Reason: $_reason"
    warp_message "Scope:                      $(warp_message_info ${WARP_CTX_SCOPE:-cache})"
    warp_message "Host:                       $(warp_message_info ${WARP_CTX_HOST:-[not set]})"
    warp_message "Port:                       $(warp_message_info ${WARP_CTX_PORT:-6379})"
    warp_message "Database:                   $(warp_message_info ${WARP_CTX_DB_INDEX:-[not set]})"
    [ -n "$WARP_CTX_USER" ] && warp_message "User:                       $(warp_message_info ${WARP_CTX_USER})" || warp_message "User:                       $(warp_message_warn [not set])"
    [ -n "$WARP_CTX_PASSWORD" ] && warp_message "Password:                   $(warp_message_info ********)" || warp_message "Password:                   $(warp_message_warn [not set])"
    warp_message_warn "Review the cache connection settings in $(basename "$ENVIRONMENTVARIABLESFILE")."
    warp_message ""
}

cache_external_cli_exec() {
    local _cmd="$1"
    local _bin="$CACHE_EXTERNAL_CLI_BIN"
    local _host="$WARP_CTX_HOST"
    local _port="$WARP_CTX_PORT"
    local _user="$WARP_CTX_USER"
    local _pass="$WARP_CTX_PASSWORD"
    local _db="$WARP_CTX_DB_INDEX"

    [ -z "$_host" ] && warp_message_error "CACHE host is empty in .env" && return 1
    [ -z "$_port" ] && _port="6379"

    if [ -n "$_user" ] && [ -n "$_pass" ]; then
        if [ -n "$_db" ]; then
            "$_bin" -h "$_host" -p "$_port" -n "$_db" --user "$_user" -a "$_pass" $_cmd
        else
            "$_bin" -h "$_host" -p "$_port" --user "$_user" -a "$_pass" $_cmd
        fi
        return $?
    fi

    if [ -n "$_pass" ]; then
        if [ -n "$_db" ]; then
            "$_bin" -h "$_host" -p "$_port" -n "$_db" -a "$_pass" $_cmd
        else
            "$_bin" -h "$_host" -p "$_port" -a "$_pass" $_cmd
        fi
        return $?
    fi

    if [ -n "$_db" ]; then
        "$_bin" -h "$_host" -p "$_port" -n "$_db" $_cmd
    else
        "$_bin" -h "$_host" -p "$_port" $_cmd
    fi
}

cache_info_external_scope() {
    local _scope="$1"
    local _health="unknown"
    local _version="n/a"
    local _ping=""
    local _rc=0

    cache_load_context "$_scope"

    if [ -z "$WARP_CTX_HOST" ]; then
        warp_message ""
        warp_message_info "* Cache (external: ${_scope})"
        warp_message "Host:                       $(warp_message_warn [not set])"
        warp_message "Port:                       $(warp_message_warn [not set])"
        warp_message "Database:                   $(warp_message_warn [not set])"
        warp_message ""
        return 0
    fi

    if cache_external_cli_required >/dev/null 2>&1; then
        _ping="$(cache_external_cli_exec "PING" 2>/dev/null | tr -d '\r' | head -n1)"
        _rc=$?
        if [ "$_rc" -eq 0 ] && [ "$_ping" = "PONG" ]; then
            _health="reachable"
        else
            _health="unreachable"
        fi

        if [ "$_health" = "reachable" ]; then
            _version="$(cache_external_cli_exec "INFO server" 2>/dev/null | awk -F: '/^redis_version:/{gsub(/\r/,"",$2); print $2; exit}')"
            [ -z "$_version" ] && _version="$(cache_external_cli_exec "INFO server" 2>/dev/null | awk -F: '/^valkey_version:/{gsub(/\r/,"",$2); print $2; exit}')"
            [ -z "$_version" ] && _version="n/a"
        else
            cache_print_external_connection_details "redis-cli/valkey-cli could not reach the endpoint."
        fi
    else
        _health="cli-missing"
    fi

    warp_message ""
    warp_message_info "* Cache (external: ${_scope})"
    warp_message "Mode:                       $(warp_message_info ${WARP_CTX_MODE:-external})"
    warp_message "Engine:                     $(warp_message_info ${WARP_CTX_ENGINE:-redis})"
    warp_message "Scope:                      $(warp_message_info ${WARP_CTX_SCOPE:-cache})"
    warp_message "Host:                       $(warp_message_info ${WARP_CTX_HOST})"
    warp_message "Port:                       $(warp_message_info ${WARP_CTX_PORT:-6379})"
    warp_message "Database:                   $(warp_message_info ${WARP_CTX_DB_INDEX:-0})"
    [ -n "$WARP_CTX_USER" ] && warp_message "User:                       $(warp_message_info ${WARP_CTX_USER})" || warp_message "User:                       $(warp_message_warn [not set])"
    [ -n "$WARP_CTX_PASSWORD" ] && warp_message "Password:                   $(warp_message_info ********)" || warp_message "Password:                   $(warp_message_warn [not set])"
    warp_message "Health:                     $(warp_message_info ${_health})"
    warp_message "Server version:             $(warp_message_info ${_version})"
    [ "$_health" = "cli-missing" ] && warp_message_warn "Install redis-cli/valkey-cli for runtime health checks."
    warp_message ""
}

cache_info_external() {
    cache_info_external_scope "cache"
    cache_info_external_scope "fpc"
    cache_info_external_scope "session"
}

cache_cli_main() {
    local _scope=""
    local _rc=0

    if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
        redis_cli_help_usage
        return 1
    fi

    cache_load_context
    if [ "$WARP_CTX_MODE" = "external" ]; then
        _scope=$(cache_scope_resolve_arg "$1")
        [ -z "$_scope" ] && warp_message_error "Please choose a valid cache scope: cache, session or fpc." && return 1
        cache_load_context "$_scope"
        cache_external_cli_required || return 1
        cache_external_cli_exec ""
        _rc=$?
        if [ "$_rc" -ne 0 ]; then
            cache_print_external_connection_details "redis-cli/valkey-cli returned exit code ${_rc}."
        fi
        return "$_rc"
    fi

    redis_cli "$@"
}

cache_monitor_main() {
    local _scope=""
    local _rc=0

    if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
        redis_monitor_help_usage
        return 1
    fi

    cache_load_context
    if [ "$WARP_CTX_MODE" = "external" ]; then
        _scope=$(cache_scope_resolve_arg "$1")
        [ -z "$_scope" ] && warp_message_error "Please choose a valid cache scope: cache, session or fpc." && return 1
        cache_load_context "$_scope"
        cache_external_cli_required || return 1
        cache_external_cli_exec "monitor"
        _rc=$?
        if [ "$_rc" -ne 0 ]; then
            cache_print_external_connection_details "redis-cli/valkey-cli returned exit code ${_rc}."
        fi
        return "$_rc"
    fi

    redis_monitor "$@"
}

cache_ssh_main() {
    if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
        redis_ssh_help
        return 0
    fi

    cache_load_context
    if [ "$WARP_CTX_MODE" = "external" ]; then
        warp_message_warn "cache ssh is not available for external mode."
        warp_message_info "Use: warp cache cli [cache|session|fpc]"
        return 1
    fi

    redis_simil_ssh "$@"
}

cache_flush_external_scope() {
    local _scope="$1"
    local _rc=0

    cache_load_context "$_scope"
    cache_external_cli_required || return 1
    cache_external_cli_exec "FLUSHDB"
    _rc=$?
    if [ "$_rc" -ne 0 ]; then
        cache_print_external_connection_details "redis-cli/valkey-cli returned exit code ${_rc}."
        return "$_rc"
    fi
    warp_message "* ${_scope} FLUSHDB:            $(warp_message_ok [ok])"
    return 0
}

cache_flush_main() {
    local _scope=""
    local _rc=0

    if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
        redis_flush_help
        return 0
    fi

    for _arg in "$@"; do
        if [ "$_arg" = "--force" ]; then
            warp_message_error "--force is not supported for cache flush."
            return 1
        fi
    done

    cache_load_context
    if [ "$WARP_CTX_MODE" = "external" ]; then
        _scope=$(cache_scope_resolve_arg "$1")
        [ -z "$_scope" ] && warp_message_error "Please choose a valid cache scope: cache, session, fpc or --all." && return 1
        warp_message_warn "External cache flush is destructive."
        if ! warp_fallback_confirm_explicit_yes "Type y to continue with external cache flush: "; then
            warp_message_warn "Aborted."
            return 1
        fi
        if [ "$_scope" = "--all" ]; then
            cache_flush_external_scope "cache" || _rc=$?
            if [ "$_rc" -eq 0 ]; then
                cache_flush_external_scope "session" || _rc=$?
            fi
            if [ "$_rc" -eq 0 ]; then
                cache_flush_external_scope "fpc" || _rc=$?
            fi
            return "$_rc"
        fi
        cache_flush_external_scope "$_scope"
        return $?
    fi

    redis_flush "$@"
}

function cache_main()
{
    case "$1" in
        cli)
            shift 1
            cache_cli_main "$@"
        ;;

        monitor)
            shift 1
            cache_monitor_main "$@"
        ;;

        info)
            if [ "$2" = "-h" ] || [ "$2" = "--help" ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
                redis_info_help
                return 0
            fi
            cache_load_context
            if [ "$WARP_CTX_MODE" = "external" ]; then
                cache_info_external
            else
                redis_info
            fi
        ;;

        ssh)
            shift
            cache_ssh_main "$@"
        ;;

        flush)
            shift
            cache_flush_main "$@"
        ;;

        -h | --help)
            cache_help_usage
        ;;

        *)
            cache_help_usage
        ;;
    esac
}
