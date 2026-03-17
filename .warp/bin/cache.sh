#!/bin/bash

. "$PROJECTPATH/.warp/bin/cache_help.sh"

function cache_main()
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
            cache_help_usage
        ;;

        *)
            cache_help_usage
        ;;
    esac
}
