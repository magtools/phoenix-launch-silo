#!/bin/bash

warp_search_engine_container_user() {
    case "$1" in
        elasticsearch)
            printf '%s\n' "elasticsearch"
            ;;
        opensearch|*)
            printf '%s\n' "opensearch"
            ;;
    esac
}

warp_search_engine_container_config_path() {
    case "$1" in
        elasticsearch)
            printf '%s\n' "/usr/share/elasticsearch/config/elasticsearch.yml"
            ;;
        opensearch|*)
            printf '%s\n' "/usr/share/opensearch/config/opensearch.yml"
            ;;
    esac
}

warp_search_engine_data_path() {
    case "$1" in
        elasticsearch)
            printf '%s\n' "/usr/share/elasticsearch/data"
            ;;
        opensearch|*)
            printf '%s\n' "/usr/share/opensearch/data"
            ;;
    esac
}

warp_search_engine_server_bin() {
    case "$1" in
        elasticsearch)
            printf '%s\n' "/usr/share/elasticsearch/bin/elasticsearch"
            ;;
        opensearch|*)
            printf '%s\n' "/usr/share/opensearch/bin/opensearch"
            ;;
    esac
}

warp_search_engine_plugin_bin() {
    case "$1" in
        elasticsearch)
            printf '%s\n' "/usr/share/elasticsearch/bin/elasticsearch-plugin"
            ;;
        opensearch|*)
            printf '%s\n' "/usr/share/opensearch/bin/opensearch-plugin"
            ;;
    esac
}

warp_search_engine_default_host_config_file() {
    case "$1" in
        elasticsearch)
            printf '%s\n' "./.warp/docker/config/elasticsearch/elasticsearch.yml"
            ;;
        opensearch|*)
            printf '%s\n' "./.warp/docker/config/opensearch/opensearch.yml"
            ;;
    esac
}

warp_search_engine_install_phonetic_default() {
    case "$1" in
        elasticsearch|opensearch)
            printf '%s\n' "1"
            ;;
        *)
            printf '%s\n' "0"
            ;;
    esac
}

warp_search_engine_ensure_runtime_config() {
    local _engine="$1"
    local _source_dir=""
    local _target_dir=""
    local _source_file=""
    local _target_file=""

    case "$_engine" in
        opensearch)
            _source_dir="$PROJECTPATH/.warp/setup/elasticsearch/config/opensearch"
            _target_dir="$PROJECTPATH/.warp/docker/config/opensearch"
            _source_file="opensearch.yml"
            _target_file="opensearch.yml"
            ;;
        *)
            return 0
            ;;
    esac

    [ -d "$_source_dir" ] || return 1

    mkdir -p "$_target_dir" || return 1

    if [ ! -f "$_target_dir/$_target_file" ]; then
        cp "$_source_dir/$_source_file" "$_target_dir/$_target_file" || return 1
    fi

    return 0
}
