#!/bin/bash

function scan_help_usage()
{
    warp_message ""
    warp_message_info "Usage:"
    warp_message      " warp scan [scanner] [options]"
    warp_message ""

    warp_message ""
    warp_message_info "Options:"
    warp_message_info   " -h, --help         $(warp_message 'display this help message')"
    warp_message ""

    warp_message_info "Available scanners:"
    warp_message_info   " scraping           $(warp_message 'detect suspicious scraping patterns in nginx access logs')"
    warp_message_info   " scrapping          $(warp_message 'alias of scraping')"
    warp_message ""

    warp_message_info "Help:"
    warp_message " Operational diagnostics and log scanners."
    warp_message " Code quality checks live under warp audit."
    warp_message ""

    warp_message_info "Examples:"
    warp_message " warp scan scraping"
    warp_message " warp scan scraping --help"
    warp_message ""
}

function scan_scraping_help_usage()
{
    warp_message ""
    warp_message_info "Usage:"
    warp_message      " warp scan scraping [options] [log_file_or_glob ...]"
    warp_message      " warp scan scrapping [options] [log_file_or_glob ...]"
    warp_message ""

    warp_message_info "Options:"
    warp_message_info   " -h, --help              $(warp_message 'display this help message')"
    warp_message_info   " -n, --top N             $(warp_message 'max rows per section, default 25')"
    warp_message_info   " -s, --min-score N       $(warp_message 'minimum client score, default 4')"
    warp_message_info   " --log <path|glob>       $(warp_message 'add a log file or glob, repeatable')"
    warp_message_info   " --path <path|glob>      $(warp_message 'alias of --log for external log paths')"
    warp_message_info   " --since <time>          $(warp_message 'only analyze lines newer than a relative or absolute time')"
    warp_message_info   " --window <duration>     $(warp_message 'score clients per time window, e.g. 5m or 1h')"
    warp_message_info   " --page-gap N            $(warp_message 'max gap between p values for a pagination run, default 4')"
    warp_message_info   " --format <format>       $(warp_message 'auto, combined, or warp; default auto')"
    warp_message_info   " --request-time-field N  $(warp_message 'field number for request_time when auto cannot detect it')"
    warp_message_info   " --json                  $(warp_message 'print JSON output')"
    warp_message_info   " --save                  $(warp_message 'write timestamped report under var/log by default')"
    warp_message_info   " --output-dir <dir>      $(warp_message 'directory for --save, default var/log')"
    warp_message_info   " --output <file>         $(warp_message 'write report to file')"
    warp_message_info   " --no-progress           $(warp_message 'disable interactive analysis spinner')"
    warp_message ""

    warp_message_info "Help:"
    warp_message " Reads Warp nginx/php-fpm access logs by default, or external logs passed as arguments."
    warp_message " Supports plain and .gz access logs."
    warp_message " --top limits rows shown per section; it does not change the analysis."
    warp_message " --since accepts values like 15m, 1h, 24h, 7d, or an absolute date parseable by date -d."
    warp_message " --window groups suspicious clients by time bucket so a full log does not merge days into one score."
    warp_message " --page-gap controls pagination tolerance: p=10,11,12 works with any gap >= 1; p=88,89,93 needs gap >= 4."
    warp_message " Query strings are normalized before unique_q counting, so parameter order does not create fake variants."
    warp_message " Signatures group by path + normalized query + UA family to expose repeated patterns across IPs."
    warp_message " By default the report prints to stdout; use --save or --output to write a file."
    warp_message " Interactive terminals show pv-like progress on stderr: stage, ingested bytes, lines, and parsed lines."
    warp_message " Use --no-progress to disable it."
    warp_message " Scores are heuristics for investigation and do not block traffic."
    warp_message ""

    warp_message_info "Examples:"
    warp_message " warp scan scraping"
    warp_message " warp scan scraping --top 50"
    warp_message " warp scan scraping --since 24h --window 5m"
    warp_message " warp scan scraping --page-gap 2 /var/log/nginx/access.log"
    warp_message " warp scan scraping --save"
    warp_message " warp scan scraping /var/log/nginx/access.log"
    warp_message " warp scan scraping --path '/var/log/nginx/access.log*'"
    warp_message " warp scan scraping '/var/log/nginx/access.log*'"
    warp_message " warp scan scraping --json --output var/warp-scan/scraping.json"
    warp_message ""
}

function scan_help()
{
    warp_message_info   " scan              $(warp_message 'operational diagnostics and log scanners')"
}
