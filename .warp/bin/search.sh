#!/bin/bash

. "$PROJECTPATH/.warp/bin/search_help.sh"

search_envphp_trim() {
    printf '%s' "$1" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

search_read_envphp_path() {
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

search_endpoint_parse() {
    local _raw="$1"
    local _scheme=""
    local _endpoint=""
    local _host=""
    local _port=""

    _raw=$(search_envphp_trim "$_raw")
    [ -z "$_raw" ] && return 1

    _endpoint="${_raw%%,*}"
    _endpoint=$(search_envphp_trim "$_endpoint")

    if [[ "$_endpoint" == *"://"* ]]; then
        _scheme="${_endpoint%%://*}"
        _endpoint="${_endpoint#*://}"
    fi

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

    echo "scheme=$_scheme"
    echo "host=$_host"
    echo "port=$_port"
}

search_kv_value() {
    local _data="$1"
    local _key="$2"

    printf '%s\n' "$_data" | awk -F= -v want="$_key" '$1 == want { print substr($0, length(want) + 2); exit }'
}

search_prompt_required() {
    local _label="$1"
    local _default="$2"
    local _value=""

    while :; do
        _value=$(warp_question_ask_default "$_label " "$_default")
        _value=$(search_envphp_trim "$_value")
        [ -n "$_value" ] && { echo "$_value"; return 0; }
        warp_message_warn "Value required."
    done
}

search_external_collect_from_envphp() {
    local _envphp="$PROJECTPATH/app/etc/env.php"
    local _servers=""
    local _scheme=""
    local _host=""
    local _port=""
    local _user=""
    local _password=""
    local _enable_auth=""
    local _enable_https=""
    local _engine=""
    local _catalog_engine=""
    local _parsed=""

    [ -f "$_envphp" ] || return 1

    _catalog_engine=$(search_read_envphp_path "$_envphp" "system.default.catalog.search.engine")

    _servers=$(search_read_envphp_path "$_envphp" "system.default.smile_elasticsuite_core_base_settings.es_client.servers")
    if [ -n "$_servers" ]; then
        _parsed=$(search_endpoint_parse "$_servers")
        _scheme=$(echo "$_parsed" | awk -F= '/^scheme=/{print substr($0,8)}')
        _host=$(echo "$_parsed" | awk -F= '/^host=/{print substr($0,6)}')
        _port=$(echo "$_parsed" | awk -F= '/^port=/{print substr($0,6)}')
        _enable_auth=$(search_read_envphp_path "$_envphp" "system.default.smile_elasticsuite_core_base_settings.es_client.enable_http_auth")
        _user=$(search_read_envphp_path "$_envphp" "system.default.smile_elasticsuite_core_base_settings.es_client.http_auth_user")
        _password=$(search_read_envphp_path "$_envphp" "system.default.smile_elasticsuite_core_base_settings.es_client.http_auth_pwd")
        _enable_https=$(search_read_envphp_path "$_envphp" "system.default.smile_elasticsuite_core_base_settings.es_client.enable_https_mode")

        if [ -z "$_scheme" ]; then
            if [ "$_enable_https" = "1" ]; then
                _scheme="https"
            else
                _scheme=$(search_read_envphp_path "$_envphp" "system.default.smile_elasticsuite_core_base_settings.es_client.scheme")
            fi
        fi

        [ "$_enable_auth" = "0" ] && { _user=""; _password=""; }

        if [ -n "$_host" ]; then
            [ -z "$_port" ] && _port="9200"
            [ -z "$_scheme" ] && _scheme="http"
            if [[ "$_catalog_engine" =~ opensearch ]]; then
                _engine="opensearch"
            elif [[ "$_catalog_engine" =~ elasticsearch ]]; then
                _engine="elasticsearch"
            fi
            [ -z "$_engine" ] && _engine="$(warp_fallback_detect_search_engine)"
            echo "engine=$_engine"
            echo "scheme=$_scheme"
            echo "host=$_host"
            echo "port=$_port"
            echo "user=$_user"
            echo "password=$_password"
            return 0
        fi
    fi

    _host=$(search_read_envphp_path "$_envphp" "system.default.catalog.search.opensearch_server_hostname")
    if [ -n "$_host" ]; then
        _parsed=$(search_endpoint_parse "$_host")
        _scheme=$(search_kv_value "$_parsed" "scheme")
        _host=$(search_kv_value "$_parsed" "host")
        _port=$(search_kv_value "$_parsed" "port")
        [ -z "$_host" ] && _host=$(search_read_envphp_path "$_envphp" "system.default.catalog.search.opensearch_server_hostname")
        [ -z "$_port" ] && _port=$(search_read_envphp_path "$_envphp" "system.default.catalog.search.opensearch_server_port")
        _enable_auth=$(search_read_envphp_path "$_envphp" "system.default.catalog.search.opensearch_enable_auth")
        _user=$(search_read_envphp_path "$_envphp" "system.default.catalog.search.opensearch_username")
        _password=$(search_read_envphp_path "$_envphp" "system.default.catalog.search.opensearch_password")
        [ "$_enable_auth" = "0" ] && { _user=""; _password=""; }
        [ -z "$_port" ] && _port="9200"
        echo "engine=opensearch"
        echo "scheme=${_scheme:-http}"
        echo "host=$_host"
        echo "port=$_port"
        echo "user=$_user"
        echo "password=$_password"
        return 0
    fi

    _host=$(search_read_envphp_path "$_envphp" "system.default.catalog.search.elasticsearch7_server_hostname")
    if [ -n "$_host" ]; then
        _parsed=$(search_endpoint_parse "$_host")
        _scheme=$(search_kv_value "$_parsed" "scheme")
        _host=$(search_kv_value "$_parsed" "host")
        _port=$(search_kv_value "$_parsed" "port")
        [ -z "$_host" ] && _host=$(search_read_envphp_path "$_envphp" "system.default.catalog.search.elasticsearch7_server_hostname")
        [ -z "$_port" ] && _port=$(search_read_envphp_path "$_envphp" "system.default.catalog.search.elasticsearch7_server_port")
        _enable_auth=$(search_read_envphp_path "$_envphp" "system.default.catalog.search.elasticsearch7_enable_auth")
        _user=$(search_read_envphp_path "$_envphp" "system.default.catalog.search.elasticsearch7_username")
        _password=$(search_read_envphp_path "$_envphp" "system.default.catalog.search.elasticsearch7_password")
        [ "$_enable_auth" = "0" ] && { _user=""; _password=""; }
        [ -z "$_port" ] && _port="9200"
        echo "engine=elasticsearch"
        echo "scheme=${_scheme:-http}"
        echo "host=$_host"
        echo "port=$_port"
        echo "user=$_user"
        echo "password=$_password"
        return 0
    fi

    return 1
}

search_external_bootstrap_if_needed() {
    local _mode=""
    local _has_es=""
    local _has_os=""
    local _answer=""
    local _data=""
    local _engine=""
    local _scheme=""
    local _host=""
    local _port=""
    local _user=""
    local _password=""

    _mode=$(warp_fallback_env_get SEARCH_MODE)
    [ "$_mode" = "external" ] && return 0

    _has_es=$(warp_fallback_compose_has_service elasticsearch)
    _has_os=$(warp_fallback_compose_has_service opensearch)
    if [ "$_has_es" = "true" ] || [ "$_has_os" = "true" ]; then
        return 0
    fi

    [ -n "$(warp_fallback_env_get SEARCH_HOST)" ] && return 0

    _answer=$(warp_question_ask_default "Search service not found in docker-compose. Is search external? $(warp_message_info [Y/n]) " "Y")
    if [ "$_answer" != "Y" ] && [ "$_answer" != "y" ]; then
        warp_message_error "Search service is not configured and external mode was not confirmed."
        return 1
    fi

    warp_message_info "Trying to detect external search settings from app/etc/env.php"
    if _data=$(search_external_collect_from_envphp); then
        _engine=$(search_kv_value "$_data" "engine")
        _scheme=$(search_kv_value "$_data" "scheme")
        _host=$(search_kv_value "$_data" "host")
        _port=$(search_kv_value "$_data" "port")
        _user=$(search_kv_value "$_data" "user")
        _password=$(search_kv_value "$_data" "password")
        if [ -n "$_host" ]; then
            warp_message_ok "Detected search endpoint ${_scheme:-http}://${_host}:${_port:-9200}"
        fi
    else
        warp_message_warn "No search settings detected in app/etc/env.php. Please complete the values below."
    fi

    [ -z "$_engine" ] && _engine=$(warp_fallback_detect_search_engine)
    [ -z "$_scheme" ] && _scheme=$(search_prompt_required "SEARCH_SCHEME [http|https]:" "http")
    [ -z "$_host" ] && _host=$(search_prompt_required "SEARCH_HOST:" "")
    [ -z "$_port" ] && _port=$(search_prompt_required "SEARCH_PORT:" "9200")

    warp_fallback_env_set "SEARCH_MODE" "external"
    warp_fallback_env_set "SEARCH_ENGINE" "$_engine"
    warp_fallback_env_set "SEARCH_SCHEME" "$_scheme"
    warp_fallback_env_set "SEARCH_HOST" "$_host"
    warp_fallback_env_set "SEARCH_PORT" "$_port"
    warp_fallback_env_set "SEARCH_USER" "$_user"
    warp_fallback_env_set "SEARCH_PASSWORD" "$_password"

    warp_message_ok "External search settings updated in $(basename "$ENVIRONMENTVARIABLESFILE")"
    return 0
}

search_load_context() {
    search_external_bootstrap_if_needed || true
    warp_fallback_bootstrap_if_needed search >/dev/null 2>&1 || true
    warp_service_context_load search >/dev/null 2>&1 || true
}

search_external_require_http_client() {
    if ! command -v curl >/dev/null 2>&1; then
        warp_message_error "curl is required for external search operations."
        warp_message_warn "Install curl and retry."
        return 1
    fi
    return 0
}

search_print_external_connection_details() {
    local _reason="$1"

    warp_message ""
    warp_message_warn "External search connection failed."
    [ -n "$_reason" ] && warp_message_warn "Reason: $_reason"
    warp_message "Scheme:                     $(warp_message_info ${WARP_CTX_SCHEME:-http})"
    warp_message "Host:                       $(warp_message_info ${WARP_CTX_HOST:-[not set]})"
    warp_message "Port:                       $(warp_message_info ${WARP_CTX_PORT:-9200})"
    [ -n "$WARP_CTX_USER" ] && warp_message "User:                       $(warp_message_info ${WARP_CTX_USER})" || warp_message "User:                       $(warp_message_warn [not set])"
    [ -n "$WARP_CTX_PASSWORD" ] && warp_message "Password:                   $(warp_message_info ********)" || warp_message "Password:                   $(warp_message_warn [not set])"
    warp_message_warn "Review the search connection settings in $(basename "$ENVIRONMENTVARIABLESFILE")."
    warp_message ""
}

search_info_external() {
    _health="unknown"
    _cluster="n/a"

    search_external_request_capture "GET" "/" ""
    if search_http_ok "$SEARCH_HTTP_CODE"; then
        _health="reachable"
    else
        _health="unreachable"
        search_print_external_connection_details "GET / returned HTTP ${SEARCH_HTTP_CODE}."
    fi

    search_external_request_capture "GET" "/_cluster/health" ""
    if search_http_ok "$SEARCH_HTTP_CODE"; then
        _cluster_status="$(echo "$SEARCH_HTTP_BODY" | sed -n 's/.*"status":"\([^"]*\)".*/\1/p' | head -n1)"
        [ -n "$_cluster_status" ] && _cluster="$_cluster_status"
    fi

    warp_message ""
    warp_message_info "* Search (external)"
    warp_message "Mode:                       $(warp_message_info ${WARP_CTX_MODE:-external})"
    warp_message "Engine:                     $(warp_message_info ${WARP_CTX_ENGINE:-elasticsearch})"
    warp_message "Scheme:                     $(warp_message_info ${WARP_CTX_SCHEME:-http})"
    warp_message "Host:                       $(warp_message_info ${WARP_CTX_HOST})"
    warp_message "Port:                       $(warp_message_info ${WARP_CTX_PORT:-9200})"
    [ -n "$WARP_CTX_USER" ] && warp_message "User:                       $(warp_message_info ${WARP_CTX_USER})" || warp_message "User:                       $(warp_message_warn [not set])"
    [ -n "$WARP_CTX_PASSWORD" ] && warp_message "Password:                   $(warp_message_info ********)" || warp_message "Password:                   $(warp_message_warn [not set])"
    warp_message "Health:                     $(warp_message_info ${_health})"
    warp_message "Cluster status:             $(warp_message_info ${_cluster})"
    warp_message ""
}

search_external_base_url() {
    _scheme="${WARP_CTX_SCHEME:-http}"
    _host="${WARP_CTX_HOST}"
    _port="${WARP_CTX_PORT:-9200}"
    echo "${_scheme}://${_host}:${_port}"
}

search_external_request_capture() {
    _method="$1"
    _path="$2"
    _data="$3"
    _url="$(search_external_base_url)${_path}"
    _resp=""
    _rc=0

    if [ -n "$WARP_CTX_USER" ]; then
        if [ -n "$_data" ]; then
            _resp=$(curl --silent -u "$WARP_CTX_USER:$WARP_CTX_PASSWORD" -X "$_method" -H "Content-Type: application/json" "$_url" -d "$_data" -w "\n%{http_code}")
            _rc=$?
        else
            _resp=$(curl --silent -u "$WARP_CTX_USER:$WARP_CTX_PASSWORD" -X "$_method" "$_url" -w "\n%{http_code}")
            _rc=$?
        fi
    else
        if [ -n "$_data" ]; then
            _resp=$(curl --silent -X "$_method" -H "Content-Type: application/json" "$_url" -d "$_data" -w "\n%{http_code}")
            _rc=$?
        else
            _resp=$(curl --silent -X "$_method" "$_url" -w "\n%{http_code}")
            _rc=$?
        fi
    fi

    if [ "$_rc" -ne 0 ]; then
        SEARCH_HTTP_BODY=""
        SEARCH_HTTP_CODE="000"
        return 1
    fi

    SEARCH_HTTP_CODE=$(printf '%s\n' "$_resp" | tail -n1 | tr -d '\r')
    SEARCH_HTTP_BODY=$(printf '%s\n' "$_resp" | sed '$d')

    if ! [[ "$SEARCH_HTTP_CODE" =~ ^[0-9]{3}$ ]]; then
        SEARCH_HTTP_BODY="$_resp"
        SEARCH_HTTP_CODE="000"
        return 1
    fi

    return 0
}

search_http_ok() {
    [[ "$1" =~ ^2[0-9][0-9]$ ]]
}

search_http_error_reason() {
    _body="$1"
    _reason=$(echo "$_body" | sed -n 's/.*"reason":"\([^"]*\)".*/\1/p' | head -n1)
    [ -z "$_reason" ] && _reason=$(echo "$_body" | tr -d '\n' | cut -c1-160)
    echo "$_reason"
}

search_response_has_error() {
    _body="$1"
    echo "$_body" | grep -q '"error"'
}

search_flush_external() {
    if [ -z "$WARP_CTX_HOST" ]; then
        warp_message_error "SEARCH_HOST is empty in .env"
        search_print_external_connection_details "SEARCH_HOST is empty."
        return 1
    fi
    search_external_require_http_client || return 1

    warp_message_warn "External search flush is destructive."
    if ! warp_fallback_confirm_explicit_yes "Type y to continue with external search flush: "; then
        warp_message_warn "Aborted."
        return 1
    fi

    search_external_request_capture "GET" "/_cat/indices?format=json&h=index" ""
    if ! search_http_ok "$SEARCH_HTTP_CODE"; then
        _reason=$(search_http_error_reason "$SEARCH_HTTP_BODY")
        warp_message_error "Unable to list indices on external search (HTTP $SEARCH_HTTP_CODE)."
        [ -n "$_reason" ] && warp_message_error "$_reason"
        search_print_external_connection_details "Unable to list indices on external search."
        return 1
    fi

    _indices_compact=$(echo "$SEARCH_HTTP_BODY" | tr -d '[:space:]')
    if [ -z "$_indices_compact" ] || [ "$_indices_compact" = "[]" ]; then
        warp_message_warn "Search index list is empty. Nothing to do."
        return 0
    fi

    search_external_request_capture "PUT" "/_all/_settings" '{"index.blocks.read_only_allow_delete": null}'
    if ! search_http_ok "$SEARCH_HTTP_CODE"; then
        _reason=$(search_http_error_reason "$SEARCH_HTTP_BODY")
        warp_message_error "Unlock process failed on external search (HTTP $SEARCH_HTTP_CODE)."
        [ -n "$_reason" ] && warp_message_error "$_reason"
        search_print_external_connection_details "Unlock process failed on external search."
        return 1
    fi
    if search_response_has_error "$SEARCH_HTTP_BODY"; then
        _reason=$(search_http_error_reason "$SEARCH_HTTP_BODY")
        warp_message_error "Unlock process returned API error."
        [ -n "$_reason" ] && warp_message_error "$_reason"
        search_print_external_connection_details "Unlock process returned API error."
        return 1
    fi
    warp_message "* Unlocking indexes... $(warp_message_ok [ok])"

    search_external_request_capture "DELETE" "/_all" ""
    if ! search_http_ok "$SEARCH_HTTP_CODE"; then
        if [ "$SEARCH_HTTP_CODE" = "404" ] && echo "$SEARCH_HTTP_BODY" | grep -q "index_not_found_exception"; then
            warp_message_warn "No indices found to delete."
            return 0
        fi
        _reason=$(search_http_error_reason "$SEARCH_HTTP_BODY")
        warp_message_error "Delete process failed on external search (HTTP $SEARCH_HTTP_CODE)."
        [ -n "$_reason" ] && warp_message_error "$_reason"
        search_print_external_connection_details "Delete process failed on external search."
        return 1
    fi
    if search_response_has_error "$SEARCH_HTTP_BODY"; then
        _reason=$(search_http_error_reason "$SEARCH_HTTP_BODY")
        warp_message_error "Delete process returned API error."
        [ -n "$_reason" ] && warp_message_error "$_reason"
        search_print_external_connection_details "Delete process returned API error."
        return 1
    fi
    warp_message "* Deleting indexes...  $(warp_message_ok [ok])"
    return 0
}

function search_main()
{
    case "$1" in
        flush)
            shift
            for _arg in "$@"; do
                if [ "$_arg" = "--force" ]; then
                    warp_message_error "--force is not supported for search flush."
                    return 1
                fi
            done
            if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
                elasticsearch_flush_help
                return 0
            fi
            search_load_context
            if [ "$WARP_CTX_MODE" = "external" ]; then
                search_flush_external
            else
                elasticsearch_flush "$@"
            fi
        ;;

        info)
            shift
            if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
                elasticsearch_info_help
                return 0
            fi
            search_load_context
            if [ "$WARP_CTX_MODE" = "external" ]; then
                search_external_require_http_client || return 1
                search_info_external
            else
                elasticsearch_info
            fi
        ;;

        ssh)
            shift
            if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
                elasticsearch_ssh_help
                return 0
            fi
            search_load_context
            if [ "$WARP_CTX_MODE" = "external" ]; then
                warp_message_warn "search ssh is not available for external mode."
                warp_message_info "Use HTTP API against SEARCH_HOST/SEARCH_PORT."
                return 1
            fi
            elasticsearch_simil_ssh "$@"
        ;;

        switch)
            shift
            search_load_context
            if [ "$WARP_CTX_MODE" = "external" ]; then
                warp_message_warn "search switch is not available for external mode."
                return 1
            fi
            elasticsearch_switch "$@"
        ;;

        -h | --help)
            search_help_usage
        ;;

        *)
            search_help_usage
        ;;
    esac
}
