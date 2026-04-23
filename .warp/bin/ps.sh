#!/bin/bash

    # IMPORT HELP

    . "$PROJECTPATH/.warp/bin/ps_help.sh"

ps_json_escape() {
    local _value="$1"

    _value=${_value//\\/\\\\}
    _value=${_value//\"/\\\"}
    _value=${_value//$'\n'/\\n}
    _value=${_value//$'\r'/}
    printf '%s' "$_value"
}

ps_container_ids() {
    local _ids=""

    _ids=$(docker-compose -f "$DOCKERCOMPOSEFILE" ps -a -q 2>/dev/null)
    if [ -z "$_ids" ]; then
        _ids=$(docker-compose -f "$DOCKERCOMPOSEFILE" ps -q 2>/dev/null)
    fi

    printf '%s\n' "$_ids"
}

ps_container_name() {
    local _container_id="$1"
    local _name=""

    _name=$(docker inspect --format '{{.Name}}' "$_container_id" 2>/dev/null)
    _name="${_name#/}"
    printf '%s\n' "$_name"
}

ps_container_service() {
    local _container_id="$1"
    local _service=""

    _service=$(docker inspect --format '{{index .Config.Labels "com.docker.compose.service"}}' "$_container_id" 2>/dev/null)
    printf '%s\n' "${_service:-unknown}"
}

ps_container_image() {
    local _container_id="$1"
    local _image=""

    _image=$(docker inspect --format '{{.Config.Image}}' "$_container_id" 2>/dev/null)
    printf '%s\n' "${_image:-unknown}"
}

ps_image_short() {
    local _image="$1"

    case "$_image" in
        ""|unknown)
            printf '%s\n' "${_image:-unknown}"
            ;;
        */*)
            printf '%s\n' "${_image##*/}"
            ;;
        *)
            printf '%s\n' "$_image"
            ;;
    esac
}

ps_container_status() {
    local _container_id="$1"
    local _status=""

    _status=$(docker inspect --format '{{.State.Status}}' "$_container_id" 2>/dev/null)
    printf '%s\n' "${_status:-unknown}"
}

ps_container_ports() {
    local _container_id="$1"
    local _ports=""

    _ports=$(docker port "$_container_id" 2>/dev/null | tr '\n' ',' | sed 's/,$//; s/,/, /g')
    printf '%s\n' "${_ports:--}"
}

ps_print_table() {
    local _container_id=""
    local _image=""
    local _name=""
    local _status=""
    local _ports=""

    printf '%-24s %-32s %-12s %s\n' "IMAGE" "CONTAINER" "STATUS" "PORTS"
    printf '%-24s %-32s %-12s %s\n' "-----" "---------" "------" "-----"

    while IFS= read -r _container_id; do
        [ -n "$_container_id" ] || continue
        _image=$(ps_image_short "$(ps_container_image "$_container_id")")
        _name=$(ps_container_name "$_container_id")
        _status=$(ps_container_status "$_container_id")
        _ports=$(ps_container_ports "$_container_id")
        printf '%-24s %-32s %-12s %s\n' "$_image" "$_name" "$_status" "$_ports"
    done
}

ps_print_names() {
    local _container_id=""

    while IFS= read -r _container_id; do
        [ -n "$_container_id" ] || continue
        ps_container_name "$_container_id"
    done
}

ps_print_services() {
    local _container_id=""

    docker-compose -f "$DOCKERCOMPOSEFILE" ps --services 2>/dev/null && return 0

    ps_container_ids | while IFS= read -r _container_id; do
        [ -n "$_container_id" ] || continue
        ps_container_service "$_container_id"
    done
}

ps_print_json() {
    local _container_id=""
    local _service=""
    local _name=""
    local _image=""
    local _status=""
    local _ports=""
    local _comma=""

    printf '[\n'
    while IFS= read -r _container_id; do
        [ -n "$_container_id" ] || continue
        _service=$(ps_container_service "$_container_id")
        _name=$(ps_container_name "$_container_id")
        _image=$(ps_container_image "$_container_id")
        _status=$(ps_container_status "$_container_id")
        _ports=$(ps_container_ports "$_container_id")
        printf '%s  {"service":"%s","container":"%s","image":"%s","status":"%s","ports":"%s"}' \
            "$_comma" \
            "$(ps_json_escape "$_service")" \
            "$(ps_json_escape "$_name")" \
            "$(ps_json_escape "$_image")" \
            "$(ps_json_escape "$_status")" \
            "$(ps_json_escape "$_ports")"
        _comma=","$'\n'
    done
    printf '\n]\n'
}

ps_command() 
{
    local _format="table"
    local _ids=""

    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help)
                ps_help_usage
                exit 0
                ;;
            --raw)
                _format="raw"
                ;;
            -q|--quiet)
                _format="quiet"
                ;;
            --services)
                _format="services"
                ;;
            --format)
                if [ $# -lt 2 ]; then
                    warp_message_error "--format requires a value: table, json, names"
                    exit 1
                fi
                shift 1
                _format="${1:-}"
                ;;
            --format=*)
                _format="${1#--format=}"
                ;;
            *)
                warp_message_error "unknown ps option: $1"
                ps_help_usage
                exit 1
                ;;
        esac
        shift 1
    done

    case "$_format" in
        raw|quiet|q|services|table|names|json|"")
            ;;
        *)
            warp_message_error "unknown ps format: $_format"
            warp_message_warn "supported formats: table, json, names"
            exit 1
            ;;
    esac

    if [ ! -f "$DOCKERCOMPOSEFILE" ]; then
        warp_message_error "$DOCKERCOMPOSEFILE not found"
        exit 1
    fi

    if [ "$(warp_check_is_running)" = false ]; then
        warp_message_error "The containers are not running"
        warp_message_error "please, first run warp start"

        exit 1
    fi

    case "$_format" in
        raw)
            docker-compose -f "$DOCKERCOMPOSEFILE" ps
            ;;
        quiet|q)
            docker-compose -f "$DOCKERCOMPOSEFILE" ps -q
            warp_message ""
            ;;
        services)
            ps_print_services
            warp_message ""
            ;;
        table|"")
            _ids=$(ps_container_ids)
            printf '%s\n' "$_ids" | ps_print_table
            warp_message ""
            ;;
        names)
            _ids=$(ps_container_ids)
            printf '%s\n' "$_ids" | ps_print_names
            warp_message ""
            ;;
        json)
            _ids=$(ps_container_ids)
            printf '%s\n' "$_ids" | ps_print_json
            warp_message ""
            ;;
    esac
}

function ps_main()
{
    case "$1" in
        ps)
            shift 1
            ps_command "$@"
        ;;

        -h | --help)
            ps_help_usage
        ;;

        *)            
            ps_help_usage
        ;;
    esac
}
