#!/bin/bash

function elasticsearch_help_usage() {
    warp_message ""
    warp_message_info "Usage:"
    warp_message      " warp search [options]"
    warp_message ""

    warp_message ""
    warp_message_info "Options:"
    warp_message_info   " -h, --help         $(warp_message 'display this help message')"
    warp_message ""

    warp_message_info "Available commands:"

    warp_message_info   " info               $(warp_message 'display info available')"
    warp_message_info   " ssh                $(warp_message 'connect to search container by ssh')"
    warp_message_info   " flush              $(warp_message 'unlock and delete search indexes')"
    warp_message_info   " switch             $(warp_message 'switch between search engine versions')"

    warp_message ""
    warp_message_info "Help:"
    warp_message " search service uses ports 9200 and 9300 inside the containers"
    warp_message " the underlying engine can be OpenSearch or Elasticsearch depending on project configuration"
    warp_message " to use this service you must modify localhost:9200 by elasticsearch:9200 in the project"
    warp_message ""
}

function elasticsearch_help()
{
    warp_message_info   " search             $(warp_message 'service of search (elasticsearch/opensearch)')"
    warp_message_info   " elasticsearch      $(warp_message 'alias of search (legacy compatibility)')"
    warp_message_info   " opensearch         $(warp_message 'alias of search (engine compatibility)')"
}

elasticsearch_ssh_help() {
    warp_message ""
    warp_message_info "Usage:"
    warp_message      " warp search ssh [options]"
    warp_message ""

    warp_message ""
    warp_message_info "Options:"
    warp_message_info   " -h, --help         $(warp_message 'display this help message')"
    warp_message_info   " --search           $(warp_message 'inside container search as elasticsearch user (canonical)')"
    warp_message_info   " --elasticsearch    $(warp_message 'inside container elasticsearch as elasticsearch user')"
    warp_message_info   " --root             $(warp_message 'inside container elasticsearch as root user')"
    warp_message ""

    warp_message ""
    warp_message_info "Help:"
    warp_message " Connect to search container by ssh "
    warp_message ""

    warp_message_info "Example:"
    warp_message " warp search ssh"
    warp_message " warp search ssh --root"
    warp_message " warp search ssh -h"
    warp_message " warp search ssh --help"
    warp_message ""
}

elasticsearch_flush_help() {
    warp_message ""
    warp_message_info "Usage:"
    warp_message      " warp search flush"
    warp_message ""

    warp_message ""
    warp_message_info "Help:"
    warp_message " For delete search index data purposes. Use it to fix a cluster_block_exception "
    warp_message " also called as FORBIDDEN/12/index read-only / allow delete (api)]"
    warp_message ""

    warp_message_info "Example:"
    warp_message " warp search flush"
    warp_message " warp search flush -h"
    warp_message ""
}

elasticsearch_switch_help () {
    warp_message ""
    warp_message_info "Usage:"
    warp_message      " warp search switch [options]"
    warp_message ""

    warp_message ""
    warp_message_info "Options:"
    warp_message_info   " -h, --help         $(warp_message 'display this help message')"
    warp_message ""

    warp_message ""
    warp_message_info "Help:"
    warp_message " this command allows to change the search engine version"
    warp_message " you can check OpenSearch versions here: $(warp_message_info '[ https://hub.docker.com/r/opensearchproject/opensearch/tags/ ]')"
    warp_message " Elasticsearch compatibility tags depend on project support and may use docker.elastic.co"
    warp_message ""

    warp_message_info "Example:"
    warp_message " warp search switch 7.6.2"
    warp_message " warp search switch 5.6.8"
    warp_message " warp search switch 6.4.2"
    warp_message ""    
}
