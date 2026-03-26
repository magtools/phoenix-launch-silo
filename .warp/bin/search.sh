#!/bin/bash

. "$PROJECTPATH/.warp/bin/search_help.sh"

search_load_context() {
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

search_info_external() {
    _health="unknown"
    _cluster="n/a"

    search_external_request_capture "GET" "/" ""
    if search_http_ok "$SEARCH_HTTP_CODE"; then
        _health="reachable"
    else
        _health="unreachable"
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
    [ -z "$WARP_CTX_HOST" ] && warp_message_error "SEARCH_HOST is empty in .env" && return 1
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
        return 1
    fi
    if search_response_has_error "$SEARCH_HTTP_BODY"; then
        _reason=$(search_http_error_reason "$SEARCH_HTTP_BODY")
        warp_message_error "Unlock process returned API error."
        [ -n "$_reason" ] && warp_message_error "$_reason"
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
        return 1
    fi
    if search_response_has_error "$SEARCH_HTTP_BODY"; then
        _reason=$(search_http_error_reason "$SEARCH_HTTP_BODY")
        warp_message_error "Delete process returned API error."
        [ -n "$_reason" ] && warp_message_error "$_reason"
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
