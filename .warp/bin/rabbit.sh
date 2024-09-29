#!/bin/bash

    # IMPORT HELP

    . "$PROJECTPATH/.warp/bin/rabbit_help.sh"

function rabbit_info()
{

    if ! warp_check_env_file ; then
        warp_message_error "file not found $(basename $ENVIRONMENTVARIABLESFILE)"
        exit
    fi; 

    RABBIT_VERSION=$(warp_env_read_var RABBIT_VERSION)
    RABBIT_BINDED_PORT=$(warp_env_read_var RABBIT_BINDED_PORT)
    RABBITMQ_DEFAULT_USER=$(warp_env_read_var RABBITMQ_DEFAULT_USER)
    RABBITMQ_DEFAULT_PASS=$(warp_env_read_var RABBITMQ_DEFAULT_PASS)

    if [ ! -z "$RABBIT_VERSION" ]
    then
        warp_message ""
        warp_message_info "* Rabbit "
        warp_message "Rabbit Version:             $(warp_message_info $RABBIT_VERSION)"
        warp_message "Host:                       $(warp_message_info 'rabbitmq')"
        warp_message "RABBIT_DATA:                $(warp_message_info $PROJECTPATH/.warp/docker/volumes/rabbit)"
#       warp_message "RABBIT_CONFIG:              $(warp_message_info $PROJECTPATH/.warp/docker/config/rabbitmq)"
        warp_message "Port (container):           $(warp_message_info '5672')"
        warp_message "Access browser:             $(warp_message_info 'http://127.0.0.1:'$RABBIT_BINDED_PORT)"
        warp_message "Access User:                $(warp_message_info $RABBITMQ_DEFAULT_USER)"
        warp_message "Access Password:            $(warp_message_info $RABBITMQ_DEFAULT_PASS)"
        warp_message ""
    fi

}

function rabbit_main()
{
    case "$1" in
        info)
            rabbit_info
        ;;

        ssh)
            shift
            rabbitmq_simil_ssh "$@"
        ;;

        -h | --help)
            rabbit_help_usage
        ;;

        *)            
            rabbit_help_usage
        ;;
    esac
}

rabbitmq_simil_ssh() {
    : '
    This function provides a bash pipe as root or rabbitmq user.
    It is called as SSH in order to make it better for developers ack
    but it does not use Secure Shell anywhere.
    '

    # Check for wrong input:
    if [[ $# -gt 1 ]]; then
        rabbitmq_ssh_wrong_input
        exit 1
    else
        if [[ $1 == "--root" ]]; then
            # Check if warp is running:    
            if [ "$(warp_check_is_running)" = false ]; then
                warp_message_error "The containers are not running"
                warp_message_error "please, first run warp start"
                exit 1
            fi
            docker-compose -f "$DOCKERCOMPOSEFILE" exec -u root rabbitmq bash
        elif [[ -z $1 || $1 == "--rabbitmq" ]]; then
            # Check if warp is running:    
            if [ "$(warp_check_is_running)" = false ]; then
                warp_message_error "The containers are not running"
                warp_message_error "please, first run warp start"
                exit 1
            fi
            # It is better if defines rabbitmq user as default ######################
            docker-compose -f "$DOCKERCOMPOSEFILE" exec -u rabbitmq rabbitmq bash
        elif [[ $1 == "-h" || $1 == "--help" ]]; then
            rabbitmq_ssh_help
            exit 0
        else
            rabbitmq_ssh_wrong_input
            exit 1
        fi
    fi
}

rabbitmq_ssh_wrong_input() {
    warp_message_error "Wrong input."
    rabbitmq_ssh_help
    exit 1
}
