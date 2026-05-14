#!/bin/bash

function restart_help_usage()
{
    warp_message ""
    warp_message_info "Usage:"
    warp_message      " warp restart [options]"
    warp_message      " warp restart service <compose-service>"
    warp_message      " warp restart -s <compose-service>"
    warp_message ""

    warp_message ""
    warp_message_info "Options:"
    warp_message_info   " -h, --help         $(warp_message 'display this help message')"
    warp_message_info   " service            $(warp_message 'restart a single docker-compose service')"
    warp_message_info   " -s                 $(warp_message 'alias of service')"
    warp_message ""

    warp_message ""
    warp_message_info "Help:"
    warp_message " this command is used to restart the services"
    warp_message " without arguments it restarts the full stack"
    warp_message " service / -s restart only one service from docker-compose-warp.yml"
    warp_message " compose-service must match the service name defined in docker-compose-warp.yml"
    warp_message ""
    warp_message_info "Example:"
    warp_message " warp restart"
    warp_message " warp restart service php"
    warp_message " warp restart -s mysql"
    warp_message ""

}

function restart_help()
{
    warp_message_info   " restart            $(warp_message 'restart the server')"
}
