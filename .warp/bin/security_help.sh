#!/bin/bash

security_help_usage() {
    warp_message ""
    warp_message_info "Usage:"
    warp_message      " warp security [command] [options]"
    warp_message ""

    warp_message ""
    warp_message_info "Options:"
    warp_message_info   " -h, --help         $(warp_message 'display this help message')"
    warp_message ""

    warp_message_info "Available commands:"
    warp_message_info   " scan               $(warp_message 'run a fast heuristic scan without writing a detailed log')"
    warp_message_info   " check              $(warp_message 'run read-only security checks and write var/log/warp-security.log plus a rotated copy')"
    warp_message_info   " toolkit            $(warp_message 'print manual analysis/cleanup commands by family or surface')"
    warp_message ""

    warp_message_info "Help:"
    warp_message " security is a Magento/PHP-focused intrusion triage entrypoint."
    warp_message " scan is the quick pass: broad git/code heuristics, a fast PHP-in-pub check excluding pub/errors and files listed in .known-files, plus a drift check for those known files."
    warp_message " scan and check both report a derived score/severity plus an operational status line."
    warp_message " check runs non-destructive scans over pub/, JS skimmer signals, IOC signatures, access logs and basic host persistence indicators."
    warp_message " check prints a short summary on screen, writes var/log/warp-security.log and also keeps a timestamped copy."
    warp_message " toolkit is available now and prints operator-run commands only."
    warp_message " cleanup commands shown by toolkit are informative/manual: Warp does not execute them."
    warp_message " scan/check create .known-paths, .known-files and .known-findings if they do not exist."
    warp_message " known untracked paths can be documented in .known-paths, one relative path per line."
    warp_message " known project files can be documented in .known-files, one relative file per line."
    warp_message " known findings can be documented in .known-findings as path|indicator|class."
    warp_message ""

    warp_message_info "Examples:"
    warp_message " warp security"
    warp_message " warp security scan"
    warp_message " warp security toolkit"
    warp_message " warp security toolkit --family polyshell"
    warp_message " warp security toolkit --family webshell --with-cleanup"
    warp_message " warp security toolkit --surface fs"
    warp_message " warp security toolkit --from-log var/log/warp-security.log"
    warp_message " warp security check"
    warp_message ""
}

security_help() {
    warp_message_info   " security          $(warp_message 'security triage helper and manual toolkit')"
}
