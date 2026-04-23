#!/bin/bash

agents_help_usage() {
    warp_message ""
    warp_message_info "Usage:"
    warp_message      " warp agents <command>"
    warp_message ""

    warp_message_info "Commands:"
    warp_message_info " install           $(warp_message 'clone configured private agents repo and run install.sh')"
    warp_message_info " update            $(warp_message 'run .agents-md/update.sh')"
    warp_message ""

    warp_message_info "Config:"
    warp_message " ./.warp/docker/config/agents/config.ini"
    warp_message " AGENTS_REPO must be an SSH Git URL, for example:"
    warp_message " git@host:org/repo.git"
    warp_message " ssh://git@host/org/repo.git"
    warp_message ""
}

agents_help() {
    warp_message_info " agents            $(warp_message 'manage private project agents lifecycle')"
}
