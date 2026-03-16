#!/bin/bash

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
