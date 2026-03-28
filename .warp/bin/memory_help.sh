#!/bin/bash

# Kept as memory_help.sh for compatibility with the current help-loader pattern.
# Public CLI command is `warp telemetry`.
memory_help_usage() {
    warp_message ""
    warp_message_info "Usage:"
    warp_message " warp telemetry [scan|config] [options]"
    warp_message ""

    warp_message ""
    warp_message_info "Options:"
    warp_message_info " -h, --help         $(warp_message 'display this help message')"
    warp_message_info " --json             $(warp_message 'output report as JSON')"
    warp_message_info " --no-suggest       $(warp_message 'show usage and current config only')"
    warp_message ""

    warp_message_info "Help:"
    warp_message " telemetry scan shows host topology and sizing context first:"
    warp_message " RAM, sockets, physical cores, logical threads, threads per core,"
    warp_message " WARP_HOST_THREADS_RESERVE and deploy THREADS suggested."
    warp_message " WARP_HOST_THREADS_RESERVE is read from .env (default: 1) and"
    warp_message " affects deploy/static worker heuristics."
    warp_message ""

    warp_message_info "Examples:"
    warp_message " warp telemetry"
    warp_message " warp telemetry scan"
    warp_message " warp telemetry scan --json"
    warp_message " warp telemetry scan --no-suggest"
    warp_message " warp telemetry config"
    warp_message ""
}

memory_help() {
    warp_message_info " telemetry          $(warp_message 'scan memory telemetry, suggestions and configuration guide')"
}
