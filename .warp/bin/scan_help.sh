#!/bin/bash

function scan_help_usage()
{
    warp_message ""
    warp_message_info "Usage:"
    warp_message      " warp audit [options]"
    warp_message ""

    warp_message ""
    warp_message_info "Options:"
    warp_message_info   " -h, --help         $(warp_message 'display this help message')"
    warp_message_info   " pr, --pr           $(warp_message 'run PR checks (pr opens scope menu, --pr keeps default non-interactive flow)')"
    warp_message_info   " -i, integrity      $(warp_message 'run setup:di:compile, then PR checks + risky primitives + phpstan level 1 on app/code')"
    warp_message_info   " phpcs              $(warp_message 'run PHPCS audit')"
    warp_message_info   " phpcbf             $(warp_message 'run PHPCBF auto-fix audit')"
    warp_message_info   " phpmd              $(warp_message 'run PHPMD audit')"
    warp_message_info   " phpcompat          $(warp_message 'run PHPCompatibility audit')"
    warp_message_info   " risky              $(warp_message 'search risky primitives on a path')"
    warp_message_info   " phpstan            $(warp_message 'run PHPStan audit')"
    warp_message_info   " --path <path>      $(warp_message 'open audit options for a custom project path')"
    warp_message ""

    warp_message ""
    warp_message_info "Help:"
    warp_message " Magento-first command."
    warp_message " Stores rules in .warp/docker/config/lint/TestPR.xml (copied from app/devops/TestPR.xml if present)."
    warp_message " Stores phpstan.neon.dist in project root only if it does not exist."
    warp_message " Use WARP_SCAN_PHP_CONTAINER=<container_name> to force execution in a specific PHP container."
    warp_message " pr opens a scope menu (custom path, default, or vendor-level paths)."
    warp_message " --pr and integrity/-i run without interactive menu."
    warp_message " integrity runs setup:di:compile, PR checks, risky primitive audit on app/code and phpstan level 1 on app/code."
    warp_message " Risky audit inline ignore accepts audit:ignore anywhere inside an inline // comment."
    warp_message " Canonical command: warp audit"
    warp_message ""

    warp_message_info "Examples:"
    warp_message " warp audit"
    warp_message " warp audit pr"
    warp_message " warp audit -i/integrity"
    warp_message " warp audit phpcs --path app/code/Vendor/Module"
    warp_message " warp audit phpcbf --path app/code/Vendor/Module"
    warp_message " warp audit phpmd --path app/code/Vendor/Module"
    warp_message " warp audit phpcompat --path app/code/Vendor/Module"
    warp_message " warp audit risky --path app/code/Vendor/Module"
    warp_message " warp audit phpstan"
    warp_message " warp audit phpstan --level 5"
    warp_message " warp audit phpstan --path app/code/Vendor/Module"
    warp_message " warp audit phpstan --level 5 --path app/code/Vendor/Module"
    warp_message " warp audit --path app/code/Vendor/Module"
    warp_message ""
}

function scan_help()
{
    warp_message_info   " audit             $(warp_message 'code quality audit helper (Magento-first)')"
}
