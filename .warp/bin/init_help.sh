#!/bin/bash

function init_help_usage()
{
    warp_message ""
    warp_message_info "Usage:"
    warp_message      " warp init [options]"
    warp_message ""

    warp_message ""
    warp_message_info "Options:"
    warp_message_info   " -h, --help         $(warp_message 'display this help message')"
    warp_message_info   " --host             $(warp_message 'bootstrap Warp for host mode without Docker wizard')"
    warp_message_info   " -n                 $(warp_message 'init without wizard on mode developer')"
    warp_message_info   " --no-interaction   $(warp_message 'init without wizard on mode developer')"
    warp_message_info   " --mode-gandalf     $(warp_message 'init warp in Gandalf Mode')"
    warp_message ""

    warp_message ""
    warp_message_info "Help:"
    warp_message " This is the main WARP command: Use it to configure project the whole project."
    warp_message " At the top it will install the WARP framework and then will trigger a wizard"
    warp_message " if you don't set --no-interaction or --mode-gandalf flag."
    warp_message " Use --host when you only need the local Warp framework plus a minimal .env in host mode."
    warp_message " In --host mode Warp sets WARP_RUNTIME_MODE=host and skips generating docker-compose-warp.yml."
    warp_message " The following services can be configured with the wizard:"
    warp_message " 1) Web Server with Nginx"
    warp_message " 2) PHP Service"
    warp_message " 3) DB Service (MariaDB/MySQL)"
    warp_message " 4) PostgreSQL Database"
    warp_message " 5) Search Service (OpenSearch/Elasticsearch compatibility)"
    warp_message " 6) Cache Service (Redis/Valkey compatibility)"
    warp_message " 7) RabbitMQ Service"
    warp_message " 8) Mailhog SMTP Service"
    warp_message " 9) Varnish HTTP Acelerator"
    warp_message ""
    warp_message " If the program detects a previous configuration, it shows a shorter menu of options,"
    warp_message " to reconfigure services that have already been chosen."
    warp_message " The wizard can also expose compatibility engines depending on the detected app context."

    warp_message " Please run ./warp init at first time."
}

function init_help()
{
    warp_message_info   " init               $(warp_message 'run main command to prepare project')"

}
