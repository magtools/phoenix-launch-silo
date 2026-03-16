#!/bin/bash

deploy_help_usage() {
    warp_message ""
    warp_message_info "Usage:"
    warp_message " warp deploy [command] [options]"
    warp_message ""

    warp_message ""
    warp_message_info "Options:"
    warp_message_info " -h, --help         $(warp_message 'display this help message')"
    warp_message_info " --dry-run          $(warp_message 'show steps without executing commands')"
    warp_message_info " --yes              $(warp_message 'skip production confirmation prompt')"
    warp_message ""

    warp_message_info "Available commands:"
    warp_message_info " set                $(warp_message 'create/update .deploy configuration')"
    warp_message_info " run                $(warp_message 'run deploy using .deploy')"
    warp_message_info " static             $(warp_message 'run static/frontend deploy steps only')"
    warp_message_info " show               $(warp_message 'show current .deploy values')"
    warp_message_info " doctor             $(warp_message 'validate prerequisites and configuration')"
    warp_message ""

    warp_message_info "Examples:"
    warp_message " warp deploy"
    warp_message " warp deploy run --dry-run"
    warp_message " warp deploy static --dry-run"
    warp_message " warp deploy set"
    warp_message " warp deploy show"
    warp_message " warp deploy doctor"
    warp_message ""
}

deploy_help() {
    warp_message_info " deploy             $(warp_message 'deployment orchestrator for local/prod')"
}
