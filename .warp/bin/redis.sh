#!/bin/bash

    # IMPORT HELP

    . "$PROJECTPATH/.warp/bin/redis_help.sh"

function redis_info()
{

    if ! warp_check_env_file ; then
        warp_message_error "file not found $(basename $ENVIRONMENTVARIABLESFILE)"
        exit
    fi; 

    REDIS_CACHE_VERSION=$(warp_env_read_var REDIS_CACHE_VERSION)
    REDIS_CACHE_CONF=$(warp_env_read_var REDIS_CACHE_CONF)

    REDIS_SESSION_VERSION=$(warp_env_read_var REDIS_SESSION_VERSION)
    REDIS_SESSION_CONF=$(warp_env_read_var REDIS_SESSION_CONF)

    REDIS_FPC_VERSION=$(warp_env_read_var REDIS_FPC_VERSION)
    REDIS_FPC_CONF=$(warp_env_read_var REDIS_FPC_CONF)

    if [ ! -z "$REDIS_CACHE_VERSION" ]
    then
        warp_message ""
        warp_message_info "* Redis Cache"
        warp_message "Redis Version:              $(warp_message_info $REDIS_CACHE_VERSION)"
        warp_message "Host:                       $(warp_message_info 'redis-cache')"
#       warp_message "Configuration file:         $(warp_message_info $REDIS_CACHE_CONF)"
#       warp_message "REDIS_DATA:                 $(warp_message_info $PROJECTPATH/.warp/docker/volumes/redis-cache)"
        warp_message "Port (container):           $(warp_message_info '6379')"
        warp_message ""
    fi

    if [ ! -z "$REDIS_SESSION_VERSION" ]
    then
        warp_message ""
        warp_message_info "* Redis Session"
        warp_message "Redis version:              $(warp_message_info $REDIS_SESSION_VERSION)"
        warp_message "Host:                       $(warp_message_info 'redis-session')"
#       warp_message "REDIS_SESSION_CONF:         $(warp_message_info $REDIS_SESSION_CONF)"
#       warp_message "REDIS_DATA:                 $(warp_message_info $PROJECTPATH/.warp/docker/volumes/redis-session)"
        warp_message "Port (container):           $(warp_message_info '6379')"
        warp_message ""
    fi

    if [ ! -z "$REDIS_FPC_VERSION" ]
    then
        warp_message ""
        warp_message_info "* Redis Fpc"
        warp_message "Redis version:              $(warp_message_info $REDIS_FPC_VERSION)"
        warp_message "Host:                       $(warp_message_info 'redis-fpc')"
#       warp_message "REDIS_FPC_CONF:             $(warp_message_info $REDIS_FPC_CONF)"
#       warp_message "REDIS_DATA:                 $(warp_message_info $PROJECTPATH/.warp/docker/volumes/redis-fpc)"
        warp_message "Port (container):           $(warp_message_info '6379')"
        warp_message ""
    fi

}

function redis_cli() 
{

    if [ "$1" = "-h" ] || [ "$1" = "--help" ]
    then
        redis_cli_help_usage 
        exit 1
    fi;

    if [ "$(warp_check_is_running)" = false ]; then
        warp_message_error "The containers are not running"
        warp_message_error "please, first run warp start"

        exit 1;
    fi

    case "$1" in 
        "fpc")
            docker-compose -f "$DOCKERCOMPOSEFILE" exec -uroot redis-fpc redis-cli
            ;;

        "session")
            docker-compose -f "$DOCKERCOMPOSEFILE" exec -uroot redis-session redis-cli
            ;;

        "cache")
            docker-compose -f "$DOCKERCOMPOSEFILE" exec -uroot redis-cache redis-cli
            ;;

        *)            
            warp_message_error "Please, choose a valid option:"
            warp_message_error "fpc, session, cache"
            warp_message_error "for more information please run: warp cache cli --help"
        ;;
    esac

}

function redis_monitor() 
{

    if [ "$1" = "-h" ] || [ "$1" = "--help" ]
    then
        redis_monitor_help_usage 
        exit 1
    fi;

    if [ "$(warp_check_is_running)" = false ]; then
        warp_message_error "The containers are not running"
        warp_message_error "please, first run warp start"

        exit 1;
    fi

    case "$1" in 
        "fpc")
            docker-compose -f "$DOCKERCOMPOSEFILE" exec -uroot redis-fpc redis-cli -c "monitor"
            ;;

        "session")
            docker-compose -f "$DOCKERCOMPOSEFILE" exec -uroot redis-session redis-cli -c "monitor"
            ;;

        "cache")
            docker-compose -f "$DOCKERCOMPOSEFILE" exec -uroot redis-cache redis-cli -c "monitor"
            ;;

        *)            
            warp_message_error "Please, choose a valid option:"
            warp_message_error "fpc, session, cache"
            warp_message_error "for more information please run: warp cache monitor --help"
        ;;
    esac

}

function redis_main()
{
    case "$1" in
        cli)
            shift 1
            redis_cli "$@"
        ;;

        monitor)
            shift 1
            redis_monitor "$@"
        ;;

        info)
            redis_info
        ;;

        ssh)
            shift
            redis_simil_ssh "$@"
        ;;

        flush)
            shift
            redis_flush "$@"
        ;;

        -h | --help)
            redis_help_usage
        ;;

        *)            
            redis_help_usage
        ;;
    esac
}

redis_ssh_wrong_input() {
    warp_message_error "Wrong input."
    redis_ssh_help
    exit 1
}

redis_flush_wrong_input() {
    warp_message_error "Wrong input."
    redis_flush_help
    exit 1
}

redis_check_warp_running() {
    if [ "$(warp_check_is_running)" = false ]; then
        warp_message_error "The containers are not running"
        warp_message_error "please, first run warp start"
        exit 1
    fi
}

redis_simil_ssh() {
    : '
    This function provides a bash pipe as root or redis user.
    It is called as SSH in order to make it better for developers ack
    but it does not use Secure Shell anywhere.
    '

    # Check for wrong input:
    if [[ $# -gt 2 ]]; then
        redis_ssh_wrong_input
        exit 1
    else
        case "$1" in
        cache)
            if [[ $2 == "-h" || $2 == "--help" ]]; then
                redis_ssh_help
                exit 0
            fi
            redis_service_check $1
            redis_check_warp_running
            shift ; redis_simil_ssh_link redis-cache "$@"
            exit 0
        ;;
        session)
            if [[ $2 == "-h" || $2 == "--help" ]]; then
                redis_ssh_help
                exit 0
            fi
            redis_service_check $1
            redis_check_warp_running
            shift ; redis_simil_ssh_link redis-session "$@"
            exit 0
        ;;
        fpc)
            if [[ $2 == "-h" || $2 == "--help" ]]; then
                redis_ssh_help
                exit 0
            fi
            redis_service_check $1
            redis_check_warp_running
            shift ; redis_simil_ssh_link redis-fpc "$@"
            exit 0
        ;;
        *)
            redis_ssh_help
            exit 1
        ;;
        esac
    fi
}

redis_simil_ssh_link() {
    : '
    This function does the simil ssh pipe.
    '

    if [[ $2 == "--root" ]]; then
        docker-compose -f "$DOCKERCOMPOSEFILE" exec -u root "$1" bash
    elif [[ -z $2 || $2 == "--redis" || $2 == "--cache" ]]; then
        docker-compose -f "$DOCKERCOMPOSEFILE" exec -u redis "$1" bash
    elif [[ $1 == "-h" || $1 == "--help" ]]; then
        redis_ssh_help
        exit 0
    else
        redis_ssh_wrong_input
        exit 1
    fi
}

redis_service_check() {
    : '
    This function checks if redis service was init.
    '

    case "$1" in
    cache)
        grep -q "REDIS_CACHE_VERSION" $ENVIRONMENTVARIABLESFILE || { warp_message_error "Redis $1 service not found." ; exit 1; }
    ;;
    session)
        grep -q "REDIS_SESSION_VERSION" $ENVIRONMENTVARIABLESFILE || { warp_message_error "Redis $1 service not found." ; exit 1; }
    ;;
    fpc)
        grep -q "REDIS_FPC_VERSION" $ENVIRONMENTVARIABLESFILE || { warp_message_error "Redis $1 service not found." ; exit 1; }
    ;;
    *)
        printf "\tWRONG INPUT ON redis_service_check FUNCTION.\n\tPLEASE REPORT THIS TO WARP DEV TEAM."
        exit 1
    ;;
    esac
}

redis_flush() {
    : '
    This function runs flush call on selected (or all) redis service.
    '

    # Check for wrong input:
    if [[ $# -gt 1 ]]; then
        redis_flush_wrong_input
        exit 1
    fi

    case "$1" in
    cache)
        docker-compose -f $DOCKERCOMPOSEFILE exec redis-cache redis-cli FLUSHALL
        exit 0
    ;;
    session)
        docker-compose -f $DOCKERCOMPOSEFILE exec redis-session redis-cli FLUSHALL
        exit 0
    ;;
    fpc)
        docker-compose -f $DOCKERCOMPOSEFILE exec redis-fpc redis-cli FLUSHALL
        exit 0
    ;;
    --all)
        warp_message "redis-cache FLUSHALL:     $(docker-compose -f $DOCKERCOMPOSEFILE exec redis-cache redis-cli FLUSHALL)"
        warp_message "redis-session FLUSHALL:   $(docker-compose -f $DOCKERCOMPOSEFILE exec redis-session redis-cli FLUSHALL)"
        warp_message "redis-fpc FLUSHALL:       $(docker-compose -f $DOCKERCOMPOSEFILE exec redis-fpc redis-cli FLUSHALL)"
        exit 0
    ;;
    -h | --help)
        redis_flush_help
        exit 0
    ;;
    *)
        redis_flush_wrong_input
        exit 1
    ;;
    esac

}
