#!/bin/bash

. "$PROJECTPATH/.warp/bin/search_help.sh"

function search_main()
{
    case "$1" in
        flush)
            shift
            elasticsearch_flush "$@"
        ;;

        info)
            shift
            elasticsearch_info
        ;;

        ssh)
            shift
            elasticsearch_simil_ssh "$@"
        ;;

        switch)
            shift
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
