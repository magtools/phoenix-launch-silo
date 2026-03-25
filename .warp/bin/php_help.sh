#!/bin/bash

function php_help_usage()
{
    warp_message ""
    warp_message_info "Usage:"
    warp_message      " warp php command [options]"
    warp_message ""

    warp_message ""
    warp_message_info "Options:"
    warp_message_info   " -h, --help         $(warp_message 'display this help message')"
    warp_message ""

    warp_message_info "Available commands:"

    warp_message_info   " ssh                $(warp_message 'connect to php by ssh')"
    warp_message_info   " version            $(warp_message 'print runtime PHP version')"
    warp_message_info   " switch             $(warp_message 'allows to change the PHP version')"

    warp_message ""
    warp_message_info "Help:"
    warp_message " Connect to php by ssh "
    warp_message " Print runtime version with: warp php --version "
    warp_message " default user to connect is www-data "
    warp_message " You can also see logs of php service with the command: warp logs php "
    warp_message " If you want to change php version, check command warp php switch --help "

    warp_message ""
    warp_message_info "Example:"
    warp_message " warp php ssh"
    warp_message " warp php ssh --root"
    warp_message " warp php ssh --help"
    warp_message " warp php --version"

    warp_message ""

}

function php_ssh_help()
{
    warp_message ""
    warp_message_info "Usage:"
    warp_message      " warp php ssh [options]"
    warp_message ""

    warp_message ""
    warp_message_info "Options:"
    warp_message_info   " -h, --help         $(warp_message 'display this help message')"
    warp_message_info   " --root             $(warp_message 'inside container php as root')"
    warp_message_info   " --www-data         $(warp_message 'inside container php as www-data')"
    warp_message ""

    warp_message ""
    warp_message_info "Help:"
    warp_message " Connect to php by ssh "
    warp_message " default user to connect is www-data "
    warp_message ""

    warp_message_info "Example:"
    warp_message " warp php ssh"
    warp_message " warp php ssh --root"
    warp_message " warp php ssh --www-data"
    warp_message ""    
}

function php_switch_help()
{
    warp_message ""
    warp_message_info "Usage:"
    warp_message      " warp php switch [options]"
    warp_message ""

    warp_message ""
    warp_message_info "Options:"
    warp_message_info   " -h, --help         $(warp_message 'display this help message')"
    warp_message ""

    warp_message ""
    warp_message_info "Help:"
    warp_message " this command allows to change the PHP version"
    warp_message " the available versions are 5.6-fpm, 7.0-fpm, 7.1-fpm, 7.2-fpm, 7.3-fpm, 7.4-fpm, 7.1.17-fpm, 7.1.26-fpm, 7.2.24-fpm, 8.1.3-fpm, 8.2.3-fpm, 8.3-fpm, 8.4-fpm"
    warp_message ""

    warp_message_info "Example:"
    warp_message " warp php switch 7.2-fpm"
    warp_message ""    
}

function php_help()
{
    warp_message_info   " php                $(warp_message 'service of php')"
}
