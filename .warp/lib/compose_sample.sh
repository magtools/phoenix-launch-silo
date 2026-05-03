#!/bin/bash

warp_compose_samples_init() {
    local _template="$1"

    [ -f "$_template" ] || return 1

    cat "$_template" > "$DOCKERCOMPOSEFILESAMPLE" || return 1
}

warp_compose_sample_append_dev() {
    local _template="$1"

    [ -f "$_template" ] || return 1
    cat "$_template" >> "$DOCKERCOMPOSEFILESAMPLE" || return 1
}

warp_compose_dev_generate_from_final() {
    local _source="${1:-$DOCKERCOMPOSEFILE}"
    local _target="${2:-$DOCKERCOMPOSEFILEDEV}"

    [ -f "$_source" ] || return 1
    cp "$_source" "$_target" || return 1
}

warp_compose_prod_generate_from_final() {
    local _source="${1:-$DOCKERCOMPOSEFILE}"
    local _target="${2:-$DOCKERCOMPOSEFILEPROD}"
    local _tmp

    [ -f "$_source" ] || return 1

    _tmp="${_target}.tmp"

    awk '
    BEGIN {
        service = ""
        in_ports = 0
        port_index = 0
    }

    /^  [A-Za-z0-9_-]+:$/ {
        service = $0
        sub(/^  /, "", service)
        sub(/:$/, "", service)
        in_ports = 0
        port_index = 0
        print
        next
    }

    in_ports == 1 && /^      - / {
        port_index++

        if (service == "mysql" && port_index == 1) {
            print "      - \"127.0.0.1:${DATABASE_BINDED_PORT}:3306\""
            next
        }

        if (service == "elasticsearch") {
            if (port_index == 1) {
                print "      - \"127.0.0.1:${SEARCH_HTTP_BINDED_PORT:-9200}:9200\""
                next
            }
            if (port_index == 2) {
                print "      - \"127.0.0.1:${SEARCH_TRANSPORT_BINDED_PORT:-9300}:9300\""
                next
            }
        }

        if (service == "redis-cache" && port_index == 1) {
            print "      - \"127.0.0.1:${REDIS_CACHE_BINDED_PORT:-6379}:6379\""
            next
        }

        if (service == "redis-session" && port_index == 1) {
            print "      - \"127.0.0.1:${REDIS_SESSION_BINDED_PORT:-6380}:6379\""
            next
        }

        if (service == "redis-fpc" && port_index == 1) {
            print "      - \"127.0.0.1:${REDIS_FPC_BINDED_PORT:-6381}:6379\""
            next
        }
    }

    /^    ports:$/ {
        in_ports = 1
        port_index = 0
        print
        next
    }

    in_ports == 1 && !/^      - / {
        in_ports = 0
        port_index = 0
    }

    {
        print
    }
    ' "$_source" > "$_tmp" || {
        rm -f "$_tmp"
        return 1
    }

    mv "$_tmp" "$_target" || {
        rm -f "$_tmp"
        return 1
    }
}

warp_compose_profile_from_env() {
    local _env_file="${1:-$ENVIRONMENTVARIABLESFILE}"
    local _http_host_ip=""

    [ -f "$_env_file" ] || {
        echo "dev"
        return 0
    }

    _http_host_ip=$(warp_env_file_read_var "$_env_file" "HTTP_HOST_IP")

    if [ -n "$_http_host_ip" ] && [ "$_http_host_ip" != "0.0.0.0" ]; then
        echo "dev"
        return 0
    fi

    echo "prod"
}

warp_compose_activate_profile() {
    local _profile="$1"
    local _active="${2:-$DOCKERCOMPOSEFILE}"
    local _dev="${3:-$DOCKERCOMPOSEFILEDEV}"
    local _prod="${4:-$DOCKERCOMPOSEFILEPROD}"
    local _source=""

    case "$_profile" in
        prod)
            _source="$_prod"
        ;;
        *)
            _source="$_dev"
        ;;
    esac

    [ -f "$_source" ] || return 1
    cp "$_source" "$_active" || return 1
}
