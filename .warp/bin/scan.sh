#!/bin/bash

. "$PROJECTPATH/.warp/bin/scan_help.sh"

scan_command()
{
    case "$1" in
        -h|--help|"")
            scan_help_usage
            return 0
            ;;
        scraping|scrapping)
            shift
            scan_scraping_not_implemented "$@"
            return $?
            ;;
        *)
            warp_message_error "unknown scan: $1"
            scan_help_usage
            return 1
            ;;
    esac
}

scan_scraping_not_implemented()
{
    if [ "$#" -gt 0 ] && { [ "$1" = "-h" ] || [ "$1" = "--help" ]; }; then
        scan_scraping_help_usage
        return 0
    fi

    warp_message_error "scan scraping is not implemented yet"
    warp_message "RFC: features/warp-scan-scrapping.md"
    return 1
}

function scan_main()
{
    scan_command "$@"
}
