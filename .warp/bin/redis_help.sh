#!/bin/bash

function redis_help_usage()
{

    warp_message ""
    warp_message_info "Usage:"
    warp_message      " warp cache command [options] [arguments]"
    warp_message ""

    warp_message ""
    warp_message_info "Options:"
    warp_message_info   " -h, --help         $(warp_message 'display this help message')"
    warp_message ""

    warp_message_info "Available commands:"

    warp_message_info   " cli                $(warp_message 'run the redis-cli command inside the redis container')"
    warp_message_info   " monitor            $(warp_message 'run the monitor command inside the redis container')"
    warp_message_info   " ssh                $(warp_message 'connect to redis services by ssh')"
    warp_message_info   " flush              $(warp_message 'flush redis services data')"

    warp_message ""
    warp_message_info "Help:"
    warp_message " redis service used in ports 6379 inside containers"
    warp_message " if cache runs in external mode (CACHE_MODE=external), Warp resolves cache/fpc/session separately"
    warp_message " from .env using CACHE_CACHE_* / CACHE_FPC_* / CACHE_SESSION_* (host, port, db, user, password)."
    warp_message " legacy CACHE_HOST / CACHE_PORT / CACHE_USER / CACHE_PASSWORD still act as compatibility fallback"
    warp_message " for the cache scope."
    warp_message " in external mode: info / cli / monitor run against the remote endpoint; ssh is not available;"
    warp_message " flush is allowed only with explicit y confirmation."
    warp_message " for more information about redis you can access the following link: https://redis.io/"

    warp_message ""

    warp_message_info "Example:"
    warp_message " warp cache cli --help"
    warp_message " warp cache monitor --help"
    warp_message " warp cache ssh --help"
    warp_message " warp cache ssh cache"
    warp_message " warp cache cli session"
    warp_message " warp cache monitor cache"
    warp_message " warp cache flush cache"
    warp_message ""    

}

function redis_monitor_help_usage()
{
    warp_message ""
    warp_message_info "Usage:"
    warp_message      " warp cache monitor [options]"
    warp_message ""

    warp_message ""
    warp_message_info "Options:"
    warp_message_info   " -h, --help         $(warp_message 'display this help message')"
    warp_message ""

    warp_message ""
    warp_message_info "Help:"
    warp_message " monitor is a debugging command that streams back every command processed by the Redis server."
    warp_message " It can help in understanding what is happening to the database."
    warp_message " in external mode it runs monitor against the selected cache scope endpoint from .env."
    warp_message " redis-cli/valkey-cli must exist on the host for external mode."
    warp_message " for more information about redis you can access the following link: https://redis.io/commands/monitor"

    warp_message ""

    warp_message_info "Example:"
    warp_message " warp cache monitor fpc"
    warp_message " warp cache monitor session"
    warp_message " warp cache monitor cache"
    warp_message ""    

}


function redis_cli_help_usage()
{

    warp_message ""
    warp_message_info "Usage:"
    warp_message      " warp cache cli [options]"
    warp_message ""

    warp_message ""
    warp_message_info "Options:"
    warp_message_info   " -h, --help         $(warp_message 'display this help message')"
    warp_message ""

    warp_message ""
    warp_message_info "Help:"
    warp_message " redis-cli is the Redis command line interface, a simple program that allows to send commands to Redis,"
    warp_message " and read the replies sent by the server, directly from the terminal."
    warp_message " in external mode it connects to the selected cache scope endpoint from .env using optional"
    warp_message " CACHE_<SCOPE>_USER / CACHE_<SCOPE>_PASSWORD (or the legacy CACHE_USER / CACHE_PASSWORD fallback)."
    warp_message " redis-cli/valkey-cli must exist on the host for external mode."
    warp_message " for more information about redis you can access the following link: https://redis.io/topics/rediscli"

    warp_message ""

    warp_message_info "Example:"
    warp_message " warp cache cli fpc"
    warp_message " warp cache cli session"
    warp_message " warp cache cli cache"
    warp_message ""    

}

function redis_help()
{
    warp_message_info   " cache              $(warp_message 'service of cache (redis/valkey)')"
    warp_message_info   " redis              $(warp_message 'alias of cache (legacy compatibility)')"
    warp_message_info   " valkey             $(warp_message 'alias of cache (engine compatibility)')"
}

redis_info_help() {
    warp_message ""
    warp_message_info "Usage:"
    warp_message      " warp cache info"
    warp_message ""

    warp_message ""
    warp_message_info "Help:"
    warp_message " show current cache connectivity information."
    warp_message " in external mode it checks cache, fpc and session endpoints from .env using redis-cli/valkey-cli and"
    warp_message " reports host, port, database, ping health and detected server version."
    warp_message ""
}

redis_ssh_help() {
    warp_message ""
    warp_message_info "Usage:"
    warp_message      " warp cache ssh [service] [options]"
    warp_message ""

    warp_message ""
    warp_message_info "Service:"
    warp_message_info   " cache              $(warp_message 'inside container redis-cache')"
    warp_message_info   " session            $(warp_message 'inside container redis-session')"
    warp_message_info   " fpc                $(warp_message 'inside container redis-fpc')"
    warp_message ""

    warp_message ""
    warp_message_info "Options:"
    warp_message_info   " --cache            $(warp_message 'inside container redis as cache user')"
    warp_message_info   " --redis            $(warp_message 'inside container redis as redis user (legacy alias)')"
    warp_message_info   " --root             $(warp_message 'inside container redis as root user')"
    warp_message ""

    warp_message ""
    warp_message_info "Help:"
    warp_message " Connect to redis service by ssh"
    warp_message " ssh is only available for local container mode; in external mode Warp blocks this command."
    warp_message ""

    warp_message_info "Example:"
    warp_message " warp cache ssh cache"
    warp_message " warp cache ssh cache --root"
    warp_message " warp cache ssh cache --cache"
    warp_message " warp cache ssh cache --redis"
    warp_message " warp cache ssh session"
    warp_message " warp cache ssh session --root"
    warp_message " warp cache ssh fpc"
    warp_message " warp cache ssh fpc --root"
    warp_message " warp cache ssh -h"
    warp_message ""
}

redis_flush_help() {
    warp_message ""
    warp_message_info "Usage:"
    warp_message      " warp cache flush [options]"
    warp_message ""

    warp_message ""
    warp_message_info "Options:"
    warp_message_info   " -h, --help         $(warp_message 'display this help message')"
    warp_message_info   " cache              $(warp_message 'flush data on redis cache service')"
    warp_message_info   " session            $(warp_message 'flush data on redis session service')"
    warp_message_info   " fpc                $(warp_message 'flush data on redis fpc service')"
    warp_message_info   " --all              $(warp_message 'flush data on all redis services')"
    warp_message ""

    warp_message ""
    warp_message_info "Help:"
    warp_message " redis-cli is the Redis command line interface, a simple program that allows to send commands to Redis,"
    warp_message " and read the replies sent by the server, directly from the terminal."
    warp_message " in external mode flush runs against the selected cache scope database using FLUSHDB and requires"
    warp_message " explicit y confirmation."
    warp_message " for more information about redis you can access the following link: https://redis.io/topics/rediscli"

    warp_message ""

    warp_message_info "Example:"
    warp_message " warp cache flush fpc"
    warp_message " warp cache flush session"
    warp_message " warp cache flush cache"
    warp_message " warp cache flush --all"
    warp_message " warp cache flush --help"
    warp_message ""    
}
