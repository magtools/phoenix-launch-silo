#!/bin/bash

. "$PROJECTPATH/.warp/bin/db_help.sh"

function db_main()
{
    case "$1" in
        devdump)
            shift 1
            mysql_devdump_main "$@"
        ;;

        devdump:*)
            mysql_devdump_main "$@"
        ;;

        dump)
            shift 1
            mysql_dump "$@"
        ;;

        info)
            mysql_info
        ;;

        health)
            shift 1
            mysql_health "$@"
        ;;

        import)
            shift 1
            mysql_import "$@"
        ;;

        connect)
            shift 1
            mysql_connect "$@"
        ;;

        ssh)
            shift 1
            mysql_connect_ssh "$@"
        ;;

        switch)
            shift 1
            mysql_switch "$@"
        ;;

        tuner)
            shift 1
            mysql_tuner "$@"
        ;;

        --update)
            mysql_update_db
        ;;

        -h | --help)
            db_help_usage
        ;;

        *)
            db_help_usage
        ;;
    esac
}
