#!/bin/bash

function phpini_help_usage()
{
    warp_message ""
    warp_message_info "Usage:"
    warp_message " warp phpini profile [status|legacy|managed] [options]"
    warp_message ""

    warp_message ""
    warp_message_info "Options:"
    warp_message_info " -h, --help       $(warp_message 'display this help message')"
    warp_message_info " --dry-run        $(warp_message 'show planned changes without writing')"
    warp_message_info " --force          $(warp_message 'allow unknown compatibility and overwrite managed ini files')"
    warp_message_info " --prod           $(warp_message 'initialize managed OPcache with production profile')"
    warp_message_info " --dev            $(warp_message 'initialize managed OPcache with development profile')"
    warp_message ""

    warp_message_info "Examples:"
    warp_message " warp phpini profile status"
    warp_message " warp phpini profile legacy --dry-run"
    warp_message " warp phpini profile managed --dry-run"
    warp_message ""
}

function phpini_help()
{
    warp_message_info " phpini            $(warp_message 'manage PHP ini profile for Xdebug and OPcache')"
}
