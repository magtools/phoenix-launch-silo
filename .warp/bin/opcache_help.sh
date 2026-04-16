#!/bin/bash

function opcache_help_usage()
{
    warp_message ""
    warp_message_info "Usage:"
    warp_message " warp opcache [enable|disable|status] [options]"
    warp_message ""

    warp_message ""
    warp_message_info "Options:"
    warp_message_info " -h, --help       $(warp_message 'display this help message')"
    warp_message_info " --force          $(warp_message 'overwrite a custom managed OPcache ini file')"
    warp_message_info " --dry-run        $(warp_message 'show planned changes without writing')"
    warp_message ""

    warp_message_info "Examples:"
    warp_message " warp opcache status"
    warp_message " warp opcache enable"
    warp_message " warp opcache disable --dry-run"
    warp_message ""
}

function opcache_help()
{
    warp_message_info " opcache           $(warp_message 'enable/disable managed OPcache profile')"
}
