#!/bin/bash

function scan_help_usage()
{
    warp_message ""
    warp_message_info "Usage:"
    warp_message      " warp scan [scanner] [options]"
    warp_message ""

    warp_message ""
    warp_message_info "Options:"
    warp_message_info   " -h, --help         $(warp_message 'display this help message')"
    warp_message ""

    warp_message_info "Available scanners:"
    warp_message_info   " scraping           $(warp_message 'detect suspicious scraping patterns in nginx access logs')"
    warp_message_info   " scrapping          $(warp_message 'alias of scraping')"
    warp_message ""

    warp_message_info "Help:"
    warp_message " Operational diagnostics and log scanners."
    warp_message " Code quality checks live under warp audit."
    warp_message ""

    warp_message_info "Examples:"
    warp_message " warp scan scraping"
    warp_message " warp scan scraping --help"
    warp_message ""
}

function scan_scraping_help_usage()
{
    warp_message ""
    warp_message_info "Usage:"
    warp_message      " warp scan scraping [options] [log_file_or_glob ...]"
    warp_message      " warp scan scrapping [options] [log_file_or_glob ...]"
    warp_message ""

    warp_message_info "Status:"
    warp_message " Not implemented yet. See features/warp-scan-scrapping.md."
    warp_message ""
}

function scan_help()
{
    warp_message_info   " scan              $(warp_message 'operational diagnostics and log scanners')"
}
