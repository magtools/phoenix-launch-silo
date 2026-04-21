#!/bin/bash

function ps_help_usage()
{
    warp_message ""
    warp_message_info "Usage:"
    warp_message      " warp ps [options]"
    warp_message ""

    warp_message ""
    warp_message_info "Options:"
    warp_message_info   " -h, --help         $(warp_message 'display this help message')"
    warp_message_info   " --raw             $(warp_message 'show native docker-compose ps output')"
    warp_message_info   " -q, --quiet       $(warp_message 'show container ids')"
    warp_message_info   " --services        $(warp_message 'show compose service names')"
    warp_message_info   " --format <format> $(warp_message 'output format: table, json, names')"
    warp_message ""

    warp_message ""
    warp_message_info "Help:"
    warp_message " display status of containers "
    warp_message " if any container has been Exited 1 you can see the logs associated with the command: warp logs"
    warp_message ""

    warp_message_info "Example:"
    warp_message " warp ps"
    warp_message " warp ps --raw"
    warp_message " warp ps --format json"
    warp_message " warp ps --services"
    warp_message " warp ps -q"
    warp_message ""    
}

function ps_help()
{
    warp_message_info   " ps                 $(warp_message 'display status of containers')"
}
