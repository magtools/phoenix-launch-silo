#!/bin/bash

function mailhog_help_usage()
{

    warp_message ""
    warp_message_info "Usage:"
    warp_message      " warp mailhog command [options]"
    warp_message ""

    warp_message ""
    warp_message_info "Options:"
    warp_message_info   " -h, --help         $(warp_message 'display this help message')"
    warp_message ""

    warp_message_info "Available commands:"

    warp_message_info   " info               $(warp_message 'display info available')"
    warp_message_info   " ssh                $(warp_message 'connect to the mail container shell')"


    warp_message ""
    warp_message_info "Help:"
    warp_message " Mail is the local email testing capability exposed by the legacy command warp mailhog"
    warp_message " the SMTP server starts on port 1025"
    warp_message " Web interface to view the messages, default http://127.0.0.1:8025"
    warp_message " Current backend engine: Mailpit"
    warp_message " In PHP you could add this line to php.ini"
    warp_message " sendmail_path = \"/usr/local/bin/mhsendmail --smtp-addr=mailhog:1025\""
    warp_message " for more information about Mailpit you can access the following link: https://mailpit.axllent.org/docs/"

    warp_message ""

    warp_message_info "Example:"
    warp_message " warp mailhog --help"
    warp_message ""    

}

function mailhog_help()
{
    warp_message_info   " mailhog            $(warp_message 'Mail service (legacy command, Mailpit backend)')"
}

mailhog_ssh_help() {

    warp_message ""
    warp_message_info "Usage:"
    warp_message      " warp mailhog ssh [options]"
    warp_message ""

    warp_message ""
    warp_message_info "Options:"
    warp_message_info   " -h, --help         $(warp_message 'display this help message')"
    warp_message_info   " --mailhog          $(warp_message 'inside container mailhog as root user')"
    warp_message_info   " --root             $(warp_message 'inside container mailhog as root user')"
    warp_message ""

    warp_message ""
    warp_message_info "Help:"
    warp_message " Connect to the mail container shell "
    warp_message ""

    warp_message_info "Example:"
    warp_message " warp mailhog ssh"
    warp_message " warp mailhog ssh --root"
    warp_message " warp mailhog ssh -h"
    warp_message " warp mailhog ssh --help"
    warp_message ""
}
