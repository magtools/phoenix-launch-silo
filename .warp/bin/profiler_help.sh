#!/bin/bash

function profiler_help_usage()
{
    warp_message ""
    warp_message_info "Usage:"
    warp_message " warp profiler status"
    warp_message " warp profiler php --enable [html|csv]"
    warp_message " warp profiler php --disable"
    warp_message " warp profiler db --enable [controlled|full] [--force]"
    warp_message " warp profiler db --disable [--force]"
    warp_message " warp profiler logs --truncate [db|profiler|all] [--force]"
    warp_message " warp profiler --disable --all [--force]"
    warp_message ""

    warp_message_info "Options:"
    warp_message_info " -h, --help          $(warp_message 'display this help message')"
    warp_message_info " --no-cache-clean    $(warp_message 'do not run Magento cache:clean config after env.php changes')"
    warp_message_info " --force             $(warp_message 'allow production env.php writes and non-interactive log truncation')"
    warp_message ""

    warp_message_info "Examples:"
    warp_message " warp profiler status"
    warp_message " warp profiler php --enable html"
    warp_message " warp profiler php --enable csv"
    warp_message " warp profiler db --enable controlled"
    warp_message " warp profiler db --disable"
    warp_message " warp profiler --disable --all"
    warp_message ""
}

function profiler_help()
{
    warp_message_info " profiler          $(warp_message 'toggle Magento PHP and DB profiling safely')"
}
