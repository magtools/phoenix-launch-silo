#!/bin/bash

# IMPORT HELP
. "$PROJECTPATH/.warp/bin/webserver_help.sh"

function webserver_info()
{

    NGINX_CONFIG_FILE=$(warp_env_read_var NGINX_CONFIG_FILE)
    HTTP_BINDED_PORT=$(warp_env_read_var HTTP_BINDED_PORT)
    HTTPS_BINDED_PORT=$(warp_env_read_var HTTPS_BINDED_PORT)
    HTTP_HOST_IP=$(warp_env_read_var HTTP_HOST_IP)
    VIRTUAL_HOST=$(warp_env_read_var VIRTUAL_HOST)
    NGINX_CONFIG_FILE=$(warp_env_read_var NGINX_CONFIG_FILE)

    if [ ! -z "$NGINX_CONFIG_FILE" ]
    then
        warp_message ""
        warp_message_info "* Nginx"
        warp_message "Virtual host:               $(warp_message_info $VIRTUAL_HOST)"
    

        ETC_HOSTS_IP='127.0.0.1'
        if [ "$HTTP_HOST_IP" = "0.0.0.0" ] ; then
            warp_message "Server IP:                  $(warp_message_info '127.0.0.1')"
            warp_message "HTTP binded port (host):    $(warp_message_info $HTTP_BINDED_PORT)"
            warp_message "HTTPS binded port (host):   $(warp_message_info $HTTPS_BINDED_PORT)"
        else
            warp_message "Server IP:                  $(warp_message_info $HTTP_HOST_IP)"
            ETC_HOSTS_IP=$HTTP_HOST_IP
        fi;
        warp_message "Logs:                       $(warp_message_info $PROJECTPATH/.warp/docker/volumes/nginx/logs)" 
        warp_message "Nginx configuration file:   $(warp_message_info $NGINX_CONFIG_FILE)" 
        warp_message ""
        warp_message_warn " - Configure your hosts file (/etc/hosts) with: $(warp_message_bold $ETC_HOSTS_IP'  '$VIRTUAL_HOST)"
        warp_message ""
    fi
}

function webserver_main() {
    case "$1" in
 
        info)
            webserver_info
        ;;

        -t | --test | test)
            shift
            webserver_test "$@"
        ;;

        -r | --reload | reload)
            shift
            webserver_reload "$@"
        ;;

        ssh)
            shift
            webserver_simil_ssh "$@"
        ;;

        -h | --help)
            webserver_help_usage
        ;;

        *)
            if [ -n "$1" ]; then
                warp_message_error "Unknown nginx command: $1"
            fi
            webserver_help_usage
            exit 1
        ;;
    esac    
}

webserver_ensure_running() {
    if [ "$(warp_check_is_running)" = false ]; then
        warp_message_error "The containers are not running"
        warp_message_error "please, first run warp start"
        exit 1
    fi
}

webserver_test() {
    if [[ $# -eq 1 && ( $1 == "-h" || $1 == "--help" ) ]]; then
        webserver_test_help
        exit 0
    fi

    if [[ $# -gt 0 ]]; then
        webserver_test_help
        exit 1
    fi

    webserver_ensure_running
    webserver_run_command docker-compose -f "$DOCKERCOMPOSEFILE" exec -u root web nginx -t
}

webserver_host_config_path() {
    local _config_file=""

    _config_file=$(warp_env_read_var NGINX_CONFIG_FILE)
    [ -n "$_config_file" ] || return 1

    case "$_config_file" in
        /*)
            printf '%s\n' "$_config_file"
        ;;
        ./*)
            printf '%s/%s\n' "$PROJECTPATH" "${_config_file#./}"
        ;;
        *)
            printf '%s/%s\n' "$PROJECTPATH" "$_config_file"
        ;;
    esac
}

webserver_file_signature() {
    local _file="$1"
    local _signature=""

    [ -f "$_file" ] || return 1
    _signature=$(cksum "$_file" 2>/dev/null) || return 1
    set -- $_signature
    printf '%s:%s\n' "$1" "$2"
}

webserver_container_config_signature() {
    local _file="$1"
    local _signature=""

    [ -n "$_file" ] || return 1
    _signature=$(docker-compose -f "$DOCKERCOMPOSEFILE" exec -T -u root web cksum "$_file" </dev/null 2>/dev/null) || return 1
    set -- $_signature
    printf '%s:%s\n' "$1" "$2"
}

webserver_known_config_mounts() {
    local _host_config=""
    local _relative_config=""
    local _container_config=""

    _host_config=$(webserver_host_config_path) && printf '%s|%s\n' "$_host_config" "/etc/nginx/sites-enabled/default.conf"

    for _relative_config in \
        ".warp/docker/config/nginx/nginx.conf|/etc/nginx/nginx.conf" \
        ".warp/docker/config/nginx/m2-cors.conf|/etc/nginx/m2-cors.conf" \
        ".warp/docker/config/nginx/bad-bot-blocker/globalblacklist.conf|/etc/nginx/conf.d/globalblacklist.conf"
    do
        _host_config="$PROJECTPATH/${_relative_config%%|*}"
        _container_config="${_relative_config#*|}"
        [ -f "$_host_config" ] && printf '%s|%s\n' "$_host_config" "$_container_config"
    done
}

# Set by webserver_config_is_stale when a stale single-file bind mount is found.
WEBSERVER_STALE_CONFIG_PATH=""

webserver_config_is_stale() {
    local _host_config=""
    local _container_config=""
    local _host_signature=""
    local _container_signature=""

    WEBSERVER_STALE_CONFIG_PATH=""

    while IFS='|' read -r _host_config _container_config; do
        [ -n "$_host_config" ] || continue
        _host_signature=$(webserver_file_signature "$_host_config") || return 2
        _container_signature=$(webserver_container_config_signature "$_container_config") || return 2

        if [ "$_host_signature" != "$_container_signature" ]; then
            WEBSERVER_STALE_CONFIG_PATH="$_host_config"
            return 0
        fi
    done < <(webserver_known_config_mounts)

    return 1
}

webserver_copy_host_config_to_container() {
    local _host_config="$1"
    local _container_config="$2"

    [ -f "$_host_config" ] || return 1
    [ -n "$_container_config" ] || return 1

    docker-compose -f "$DOCKERCOMPOSEFILE" exec -T -u root web sh -c 'cat > "$1"' sh "$_container_config" < "$_host_config"
}

webserver_validate_host_config_in_container() {
    local _host_config=""
    local _nginx_config=""
    local _globalblacklist_config=""
    local _m2_cors_config=""
    local _status=0

    _host_config=$(webserver_host_config_path) || return 1
    _nginx_config="$PROJECTPATH/.warp/docker/config/nginx/nginx.conf"
    _globalblacklist_config="$PROJECTPATH/.warp/docker/config/nginx/bad-bot-blocker/globalblacklist.conf"
    _m2_cors_config="$PROJECTPATH/.warp/docker/config/nginx/m2-cors.conf"

    webserver_copy_host_config_to_container "$_host_config" "/etc/nginx/sites-enabled/warp-vhost-test.conf" || return 1

    if [ -f "$_nginx_config" ]; then
        webserver_copy_host_config_to_container "$_nginx_config" "/etc/nginx/warp-nginx-test.conf" || return 1
    else
        docker-compose -f "$DOCKERCOMPOSEFILE" exec -T -u root web cp /etc/nginx/nginx.conf /etc/nginx/warp-nginx-test.conf || return 1
    fi

    if [ -f "$_globalblacklist_config" ]; then
        webserver_copy_host_config_to_container "$_globalblacklist_config" "/etc/nginx/conf.d/warp-globalblacklist-test.conf" || return 1
    fi

    if [ -f "$_m2_cors_config" ]; then
        webserver_copy_host_config_to_container "$_m2_cors_config" "/etc/nginx/warp-m2-cors-test.conf" || return 1
    fi

    docker-compose -f "$DOCKERCOMPOSEFILE" exec -T -u root web sh -c '
sed -i "s#include[[:space:]]*/etc/nginx/sites-enabled/\*;#include /etc/nginx/sites-enabled/warp-vhost-test.conf;#" /etc/nginx/warp-nginx-test.conf || exit 1
[ ! -f /etc/nginx/conf.d/warp-globalblacklist-test.conf ] || sed -i "s#/etc/nginx/conf.d/globalblacklist.conf#/etc/nginx/conf.d/warp-globalblacklist-test.conf#g" /etc/nginx/warp-nginx-test.conf || exit 1
[ ! -f /etc/nginx/warp-m2-cors-test.conf ] || sed -i "s#/etc/nginx/m2-cors.conf#/etc/nginx/warp-m2-cors-test.conf#g" /etc/nginx/sites-enabled/warp-vhost-test.conf || exit 1
grep -q "/etc/nginx/sites-enabled/warp-vhost-test.conf" /etc/nginx/warp-nginx-test.conf || exit 1
nginx -t -c /etc/nginx/warp-nginx-test.conf
'
    _status=$?
    docker-compose -f "$DOCKERCOMPOSEFILE" exec -T -u root web rm -f \
        /etc/nginx/sites-enabled/warp-vhost-test.conf \
        /etc/nginx/warp-nginx-test.conf \
        /etc/nginx/conf.d/warp-globalblacklist-test.conf \
        /etc/nginx/warp-m2-cors-test.conf >/dev/null 2>&1
    return "$_status"
}

webserver_restart_web() {
    docker-compose -f "$DOCKERCOMPOSEFILE" restart web
}

webserver_reload_status_message() {
    local _color="$1"
    local _message="$2"

    case "$_color" in
        success)
            warp_message_ok "============================================================"
            warp_message_ok "$_message"
            warp_message_ok "============================================================"
        ;;
        warn)
            warp_message_warn "============================================================"
            warp_message_warn "$_message"
            warp_message_warn "============================================================"
        ;;
        error)
            warp_message_error "============================================================"
            warp_message_error "$_message"
            warp_message_error "============================================================"
        ;;
        *)
            warp_message "============================================================"
            warp_message "$_message"
            warp_message "============================================================"
        ;;
    esac
}

webserver_print_command_output() {
    local _output="$1"
    local _line=""
    local _status_value=""

    [ -n "$_output" ] || return 0

    while IFS= read -r _line || [ -n "$_line" ]; do
        case "$_line" in
            "exit status "*)
                _status_value="${_line#exit status }"
                if [[ "$_status_value" =~ ^[0-9]+$ ]] && [ "$_status_value" -ne 0 ]; then
                    warp_message_error "$_line"
                else
                    warp_message "$_line"
                fi
            ;;
            *)
                warp_message "$_line"
            ;;
        esac
    done <<< "$_output"
}

webserver_run_command() {
    local _output=""
    local _status=0

    _output=$("$@" 2>&1)
    _status=$?
    webserver_print_command_output "$_output"
    return "$_status"
}

webserver_reload() {
    local _config_file=""
    local _test_status=0
    local _stale_status=0
    local _reload_status=0
    local _restart_status=0
    local _host_test_status=0

    if [[ $# -eq 1 && ( $1 == "-h" || $1 == "--help" ) ]]; then
        webserver_reload_help
        exit 0
    fi

    if [[ $# -gt 0 ]]; then
        webserver_reload_help
        exit 1
    fi

    webserver_ensure_running
    webserver_run_command docker-compose -f "$DOCKERCOMPOSEFILE" exec -u root web nginx -t
    _test_status=$?
    [ "$_test_status" -eq 0 ] || exit "$_test_status"

    webserver_config_is_stale
    _stale_status=$?
    if [ "$_stale_status" -eq 0 ]; then
        _config_file=$(warp_env_read_var NGINX_CONFIG_FILE)
        [ -n "$WEBSERVER_STALE_CONFIG_PATH" ] && _config_file="$WEBSERVER_STALE_CONFIG_PATH"
        webserver_reload_status_message "warn" "Nginx config bind mount is stale: ${_config_file}"
        warp_message_warn "Restarting web container to apply the current host file."
        warp_message "Testing current host vhost before restarting web."
        webserver_validate_host_config_in_container
        _host_test_status=$?
        if [ "$_host_test_status" -ne 0 ]; then
            webserver_reload_status_message "error" "Current host nginx configuration did not pass validation; web was not restarted."
            exit "$_host_test_status"
        fi
        webserver_restart_web || exit $?
        webserver_config_is_stale
        _stale_status=$?
        if [ "$_stale_status" -eq 0 ]; then
            webserver_reload_status_message "error" "Nginx vhost is still stale after restarting web."
            warp_message_error "Recreate the web service so Docker remounts ${_config_file}."
            exit 1
        fi
        exit 0
    elif [ "$_stale_status" -eq 2 ]; then
        warp_message_warn "Could not verify host/container vhost signatures; continuing with nginx reload."
    fi

    webserver_run_command docker-compose -f "$DOCKERCOMPOSEFILE" exec -u root web nginx -s reload
    _reload_status=$?
    if [ "$_reload_status" -eq 0 ]; then
        webserver_reload_status_message "success" "Nginx was reloaded."
        exit 0
    fi

    webserver_reload_status_message "warn" "Nginx reload failed; restarting web container as fallback."
    webserver_restart_web
    _restart_status=$?
    exit "$_restart_status"
}

webserver_simil_ssh() {
    : '
    This function provides a bash pipe as root or nginx user.
    It is called as SSH in order to make it better for developers ack
    but it does not use Secure Shell anywhere.
    '

    # Check for wrong input:
    if [[ $# -gt 1 ]]; then
        webserver_ssh_wrong_input
        exit 1
    else
        if [[ $1 == "--root" ]]; then
            webserver_ensure_running
            docker-compose -f "$DOCKERCOMPOSEFILE" exec -u root web bash
        elif [[ -z $1 || $1 == "--nginx" ]]; then
            webserver_ensure_running
            # It is better if defines nginx user as default ######################
            docker-compose -f "$DOCKERCOMPOSEFILE" exec -u nginx web bash
        elif [[ $1 == "-h" || $1 == "--help" ]]; then
            webserver_ssh_help
            exit 0
        else
            webserver_ssh_wrong_input
            exit 1
        fi
    fi
}

webserver_ssh_wrong_input() {
    warp_message_error "Wrong input."
    webserver_ssh_help
    exit 1
}
