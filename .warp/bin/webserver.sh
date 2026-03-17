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

        ssh)
            shift
            webserver_simil_ssh "$@"
        ;;

        -h | --help)
            webserver_help_usage
        ;;

        *)            
            webserver_help_usage
        ;;
    esac    
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
            # Check if warp is running:    
            if [ "$(warp_check_is_running)" = false ]; then
                warp_message_error "The containers are not running"
                warp_message_error "please, first run warp start"
                exit 1
            fi
            docker-compose -f "$DOCKERCOMPOSEFILE" exec -u root web bash
        elif [[ -z $1 || $1 == "--nginx" ]]; then
            # Check if warp is running:    
            if [ "$(warp_check_is_running)" = false ]; then
                warp_message_error "The containers are not running"
                warp_message_error "please, first run warp start"
                exit 1
            fi
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
