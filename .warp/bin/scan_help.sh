#!/bin/bash

function scan_help_usage()
{
    warp_message ""
    warp_message_info "Usage:"
    warp_message      " warp scan [options]"
    warp_message ""

    warp_message ""
    warp_message_info "Options:"
    warp_message_info   " -h, --help         $(warp_message 'display this help message')"
    warp_message_info   " --pr               $(warp_message 'run PR checks (PHPCS severity>=7 + PHPMD TestPR)')"
    warp_message_info   " -i, integrity      $(warp_message 'run setup:di:compile then --pr')"
    warp_message_info   " --path <route>     $(warp_message 'open scan options for a custom project route')"
    warp_message ""

    warp_message ""
    warp_message_info "Help:"
    warp_message " Magento-first command."
    warp_message " Stores rules in .warp/docker/config/lint/TestPR.xml (copied from app/devops/TestPR.xml if present)."
    warp_message " Use WARP_SCAN_PHP_CONTAINER=<container_name> to force execution in a specific PHP container."
    warp_message " --pr and integrity/-i run without interactive menu."
    warp_message ""

    warp_message_info "Examples:"
    warp_message " warp scan"
    warp_message " warp scan --pr"
    warp_message " warp scan integrity"
    warp_message " warp scan --path app/code/Vendor/Module"
    warp_message ""
    warp_message " Menu options (scan / scan --path):"
    warp_message " 1) phpcs"
    warp_message " 2) phpcbf"
    warp_message " 3) phpmd"
    warp_message " 4) test PR"
    warp_message " 5) cancel"
    warp_message ""
    warp_message " Path menu:"
    warp_message " 1) custom path"
    warp_message " <last>) cancel"
    warp_message ""
}

function scan_help()
{
    warp_message_info   " scan              $(warp_message 'code quality scan helper (Magento-first)')"
}
