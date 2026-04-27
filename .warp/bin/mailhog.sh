#!/bin/bash

    # IMPORT HELP

    . "$PROJECTPATH/.warp/bin/mailhog_help.sh"

function mailhog_info()
{

    if ! warp_check_env_file ; then
        warp_message_error "file not found $(basename $ENVIRONMENTVARIABLESFILE)"
        exit
    fi; 

    MAILHOG_BINDED_PORT=$(warp_env_read_mail_binded_port)
    MAIL_ENGINE=$(warp_env_read_var MAIL_ENGINE)

    if [ ! -z "$MAILHOG_BINDED_PORT" ]
    then
        warp_message ""
        warp_message_info "* Mail Service "
        [ -z "$MAIL_ENGINE" ] && MAIL_ENGINE="mailpit"
        warp_message "Host SMTP:                  $(warp_message_info 'mailhog')"
        warp_message "Mail engine:                $(warp_message_info "$MAIL_ENGINE")"
        warp_message "Port (container):           $(warp_message_info '1025')"
        warp_message "Access browser:             $(warp_message_info 'http://127.0.0.1:'$MAILHOG_BINDED_PORT)"
        warp_message ""
    fi

}

function mailhog_main()
{
    case "$1" in
        info)
            mailhog_info
        ;;

        ssh)
            shift
            mailhog_simil_ssh "$@"
        ;;

        -h | --help)
            mailhog_help_usage
        ;;

        *)            
            mailhog_help_usage
        ;;
    esac
}

mailhog_simil_ssh() {
    : '
    This function provides a shell as root inside the mail container.
    It is called as SSH in order to make it better for developers ack
    but it does not use Secure Shell anywhere.
    '

    # Check for wrong input:
    if [[ $# -gt 1 ]]; then
        mailhog_ssh_wrong_input
        exit 1
    else
        if [[ $1 == "--root" ]]; then
            # Check if warp is running:    
            if [ "$(warp_check_is_running)" = false ]; then
                warp_message_error "The containers are not running"
                warp_message_error "please, first run warp start"
                exit 1
            fi
            # Mailhog latest image does not include bash shell. We could add it but it will
            #   include a new (not very usefull) layer.
            docker-compose -f "$DOCKERCOMPOSEFILE" exec -u root mailhog sh
        elif [[ -z $1 || $1 == "--mailhog" ]]; then
            # Check if warp is running:    
            if [ "$(warp_check_is_running)" = false ]; then
                warp_message_error "The containers are not running"
                warp_message_error "please, first run warp start"
                exit 1
            fi
            docker-compose -f "$DOCKERCOMPOSEFILE" exec -u root mailhog sh
        elif [[ $1 == "-h" || $1 == "--help" ]]; then
            mailhog_ssh_help
            exit 0
        else
            mailhog_ssh_wrong_input
            exit 1
        fi
    fi
}

mailhog_ssh_wrong_input() {
    warp_message_error "Wrong input."
    mailhog_ssh_help
    exit 1
}
