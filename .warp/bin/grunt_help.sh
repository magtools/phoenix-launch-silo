#!/bin/bash

function grunt_help_usage()
{
    warp_message ""
    warp_message_info "Usage:"
    warp_message      " warp grunt [options] [arguments]"
    warp_message ""

    warp_message ""
    warp_message_info "Options:"
    warp_message_info   " -h, --help         $(warp_message 'display this help message')"
    warp_message ""

    warp_message_info "Available commands:"
    warp_message_info   " setup              $(warp_message 'install npm deps and prepare grunt in php container')"
    warp_message ""

    warp_message ""
    warp_message_info "Help:"
    warp_message " Allow run grunt inside the container "
    warp_message " Optional override container: WARP_GRUNT_PHP_CONTAINER=<container_name>"
    warp_message ""

    warp_message_info "Example:"
    warp_message " warp grunt setup"
    warp_message " WARP_GRUNT_PHP_CONTAINER=m2cortassa-php-1 warp grunt setup"
    warp_message " warp grunt exec"
    warp_message " warp grunt less"
    warp_message ""    
}

grunt_setup_help_usage() {
    warp_message ""
    warp_message_info "Usage:"
    warp_message " warp grunt setup [options]"
    warp_message ""

    warp_message ""
    warp_message_info "Options:"
    warp_message_info " -h, --help         $(warp_message 'display this help message')"
    warp_message ""

    warp_message_info "Help:"
    warp_message " Setup grunt tooling in php container:"
    warp_message " 1) copies package/grunt sample files if missing"
    warp_message " 2) runs npm install as root"
    warp_message " 3) ensures local grunt-cli"
    warp_message " 4) fixes ownership to www-data"
    warp_message ""
}

function grunt_help()
{
    warp_message_info   " grunt              $(warp_message 'execute grunt inside the container')"
}
