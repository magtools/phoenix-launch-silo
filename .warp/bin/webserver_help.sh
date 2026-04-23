#!/bin/bash

webserver_help_usage() {
    warp_message ""
    warp_message_info "Usage:"
    warp_message      " warp nginx [options]"
    warp_message ""

    warp_message ""
    warp_message_info "Options:"
    warp_message_info   " -h, --help         $(warp_message 'display this help message')"
    warp_message ""

    warp_message_info "Available commands:"

    warp_message_info   " info               $(warp_message 'display info available')"
    warp_message_info   " version            $(warp_message 'print the effective nginx runtime version')"
    warp_message_info   " check              $(warp_message 'compare the local nginx runtime against Docker Hub releases')"
    warp_message_info   " -t, --test, test   $(warp_message 'validate nginx configuration as root')"
    warp_message_info   " -r, --reload, reload $(warp_message 'validate and reload nginx as root, restarting web if the vhost mount is stale')"
    warp_message_info   " ssh                $(warp_message 'connect to nginx by ssh')"
}

webserver_version_help() {
    warp_message ""
    warp_message_info "Usage:"
    warp_message      " warp nginx version"
    warp_message      " warp nginx --version"
    warp_message ""

    warp_message_info "Help:"
    warp_message " Print only the nginx version line."
    warp_message " If the web container is running, inspect that runtime."
    warp_message " If it is not running, run a temporary container from the configured web image."
    warp_message " If the detected version is older than 1.25.1, Warp prints a red update warning."
    warp_message ""
}

webserver_check_help() {
    warp_message ""
    warp_message_info "Usage:"
    warp_message      " warp nginx check"
    warp_message ""

    warp_message_info "Help:"
    warp_message " Compare the detected nginx runtime version against released versions on Docker Hub."
    warp_message " If the version is up to date, Warp prints a green status."
    warp_message " If it is behind by 10 releases or less, Warp prints a green 'still a valid version' status."
    warp_message " If it is behind by more than 10 releases, Warp prints a yellow outdated warning."
    warp_message " If the detected version is older than 1.25.1, Warp prints a red update warning."
    warp_message " Suggested remediation: docker pull nginx:latest"
    warp_message ""
}

webserver_help() {
    warp_message_info   " nginx              $(warp_message 'NGinx web service')"
}

webserver_ssh_help() {

    warp_message ""
    warp_message_info "Usage:"
    warp_message      " warp nginx ssh [options]"
    warp_message ""

    warp_message ""
    warp_message_info "Options:"
    warp_message_info   " -h, --help         $(warp_message 'display this help message')"
    warp_message_info   " --nginx            $(warp_message 'inside web server container as nginx user')"
    warp_message_info   " --root             $(warp_message 'inside web server as root user')"
    warp_message ""

    warp_message ""
    warp_message_info "Help:"
    warp_message " Connect to web server by ssh "
    warp_message ""

    warp_message_info "Example:"
    warp_message " warp nginx ssh"
    warp_message " warp nginx ssh --root"
    warp_message " warp nginx ssh -h"
    warp_message " warp nginx ssh --help"
    warp_message ""
}

webserver_test_help() {
    warp_message ""
    warp_message_info "Usage:"
    warp_message      " warp nginx -t"
    warp_message      " warp nginx --test"
    warp_message      " warp nginx test"
    warp_message ""

    warp_message_info "Help:"
    warp_message " Validate nginx configuration inside the web container as root."
    warp_message ""
}

webserver_reload_help() {
    warp_message ""
    warp_message_info "Usage:"
    warp_message      " warp nginx --reload"
    warp_message      " warp nginx reload"
    warp_message ""

    warp_message_info "Help:"
    warp_message " Validate nginx configuration and reload nginx inside the web container as root."
    warp_message " If Docker still exposes an older vhost bind mount, restart only the web container."
    warp_message ""
}
