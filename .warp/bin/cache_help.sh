#!/bin/bash

function cache_help_usage()
{
    redis_help_usage
}

function cache_help()
{
    warp_message_info   " cache              $(warp_message 'utility for cache service operations (redis/valkey)')"
    warp_message_info   " redis              $(warp_message 'alias of cache (legacy compatibility)')"
    warp_message_info   " valkey             $(warp_message 'alias of cache (engine compatibility)')"
}
