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
    warp_message " Connect to redis service by ssh "
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
