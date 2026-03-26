#!/bin/bash

    # IMPORT HELP

    . "$PROJECTPATH/.warp/bin/elasticsearch_help.sh"

function elasticsearch_info()
{

    if ! warp_check_env_file ; then
        warp_message_error "file not found $(basename $ENVIRONMENTVARIABLESFILE)"
        exit
    fi; 

    ES_HOST="elasticsearch"
    ES_VERSION=$(warp_env_read_var ES_VERSION)
    ES_MEMORY=$(warp_env_read_var ES_MEMORY)
    if [ "$(warp_check_is_running)" = true ] && [[ -n $ES_VERSION ]]; then
        ES_HOST2CONTAINER_PORT=$(docker inspect --format='{{(index (index .NetworkSettings.Ports "9200/tcp") 0).HostPort}}' "$(warp docker ps -q elasticsearch)")
    fi

    MODE_SANDBOX=$(warp_env_read_var MODE_SANDBOX)

    if [ "$MODE_SANDBOX" = "Y" ] || [ "$MODE_SANDBOX" = "y" ] ; then
        ES_HOST=$ES_SBHOST
        ES_VERSION=$ES_SBVER
        ES_MEMORY=$ES_SBMEM
    fi

    if [ ! -z "$ES_VERSION" ]
    then
        warp_message ""
        warp_message_info "* Elasticsearch"
        warp_message "Version:                    $(warp_message_info $ES_VERSION)"
        warp_message "Host:                       $(warp_message_info $ES_HOST)"
        [[ -n $ES_HOST2CONTAINER_PORT ]] && warp_message "Ports (container):          $(warp_message_info "$ES_HOST2CONTAINER_PORT --> 9200")"
        warp_message "Data:                       $(warp_message_info $PROJECTPATH/.warp/docker/volumes/elasticsearch)"
        warp_message "Memory:                     $(warp_message_info $ES_MEMORY)"

        warp_message ""
    fi

}

function elasticsearch_command()
{

    if [ "$1" = "-h" ] || [ "$1" = "--help" ]
    then
        elasticsearch_help_usage 
        exit 1
    fi;

}

elasticsearch_simil_ssh() {
    : '
    This function provides a bash pipe as root or elasticsearch user.
    It is called as SSH in order to make it better for developers ack
    but it does not use Secure Shell anywhere.
    '

    # Check for wrong input:
    if [[ $# -gt 1 ]]; then
        elasticsearch_ssh_wrong_input
        exit 1
    else
        if [[ $1 == "--root" ]]; then
            # Check if warp is running:    
            if [ "$(warp_check_is_running)" = false ]; then
                warp_message_error "The containers are not running"
                warp_message_error "please, first run warp start"
                exit 1
            fi
            docker-compose -f "$DOCKERCOMPOSEFILE" exec -u root elasticsearch bash
        elif [[ -z $1 || $1 == "--elasticsearch" || $1 == "--search" ]]; then
            # Check if warp is running:    
            if [ "$(warp_check_is_running)" = false ]; then
                warp_message_error "The containers are not running"
                warp_message_error "please, first run warp start"
                exit 1
            fi
            # It is better if defines elasticsearch user as default ######################
            docker-compose -f "$DOCKERCOMPOSEFILE" exec -u elasticsearch elasticsearch bash
        elif [[ $1 == "-h" || $1 == "--help" ]]; then
            elasticsearch_ssh_help
            exit 0
        else
            elasticsearch_ssh_wrong_input
        fi
    fi
}

elasticsearch_flush() {
    : '
    This function unlocks and delete all indexes.
    '

    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        elasticsearch_flush_help
        exit 0
    elif [[ $# -eq 0 ]]; then
        # Check if warp is running:    
        if [ "$(warp_check_is_running)" = false ]; then
            warp_message_error "The containers are not running"
            warp_message_error "please, first run warp start"
            exit 1
        fi
        # Parsing ES dynamic binded port:
        ES_HOST2CONTAINER_PORT=$(docker inspect --format='{{(index (index .NetworkSettings.Ports "9200/tcp") 0).HostPort}}' $(warp docker ps -q elasticsearch))
        if [[ -n $(curl --silent -X GET http://localhost:$ES_HOST2CONTAINER_PORT/_cat/indices) ]]; then
            # Unlocking indexes:
            ACK=$(curl --silent -X PUT -H "Content-Type: application/json" http://localhost:$ES_HOST2CONTAINER_PORT/_all/_settings -d '{"index.blocks.read_only_allow_delete": null}')
            if [[ $(echo "$ACK" | grep '{"acknowledged":true}') ]]; then
                warp_message "* Unlocking indexes... $(warp_message_ok [ok])"
                # Deleting indexes:
                ACK=$(curl --silent -X DELETE "localhost:$ES_HOST2CONTAINER_PORT/_all")
                if [[ $(echo "$ACK" | grep '{"acknowledged":true}') ]]; then
                    warp_message "* Deleting indexes...  $(warp_message_ok [ok])"
                else
                    warp_message_error "Delete process fail"
                    exit 1
                fi
            else
                warp_message_error "Unlock process fail"
                exit 1
            fi
        else
            warp_message_warn "ES database is empty. Nothing to do."
        fi
    else
        elasticsearch_flush_wrong_input
    fi
}

elasticsearch_switch() {
    if [ "$1" = "-h" ] || [ "$1" = "--help" ] || [ -z "$1" ]; then
        elasticsearch_switch_help 
        exit 1
    fi;

    # if [ $(warp_check_is_running) = true ]; then
    #     warp_message_error "The containers are running"
    #     warp_message_error "please, first run warp stop --hard"

    #     exit 1;
    # fi

    ELASTICSEARCH_CURRENT_VERSION=$(warp_env_read_var ES_VERSION)

    if [[ -z $ELASTICSEARCH_CURRENT_VERSION ]]; then
        warp_message_error "Elasticsearch not found"
        exit 1
    fi

    for es_version_p in "${ELASTICSEARCH_AVAILABLE_VERSIONS[@]}"; do
        if [[ $es_version_p == $1 ]]; then
            break
        fi
        if [[ $es_version_p == ${ELASTICSEARCH_AVAILABLE_VERSIONS[-1]} ]]; then
            warp_message_error "ES $1 is not available."
            warp_message_info "The available versions are:"
            for i in "${ELASTICSEARCH_AVAILABLE_VERSIONS[@]}"; do
                printf "\t" ; warp_message_info $i
            done
            exit 1
        fi
    done

    if [[ $1 == $ELASTICSEARCH_CURRENT_VERSION ]]; then
        warp_message_warn "You are already running $ELASTICSEARCH_CURRENT_VERSION version"
    else
        warp_message_warn "Swapping ES $ELASTICSEARCH_CURRENT_VERSION to ES $1"
        # elasticsearch_snapshot_f=$(warp_question_ask_default "Do you want to make an snapshot from ES? $(warp_message_info [y/N]) " "N")
        # if [[ $elasticsearch_snapshot_f == 'Y' ]] || [[ $elasticsearch_snapshot_f == 'y' ]]; then
        #     es_snapshot_name=$(warp_question_ask "Snapshot name? $(warp_message_warn "MUST BE LOWERCASE"): ")
        #     elasticsearch_make_snapshot $es_snapshot_name
        # fi
        warp stop --hard
        # Reconf .env:
        cat "$ENVIRONMENTVARIABLESFILE" | sed -e "s/ES_VERSION=$ELASTICSEARCH_CURRENT_VERSION/ES_VERSION=$1/" > "$ENVIRONMENTVARIABLESFILE.warp_tmp"
        mv "$ENVIRONMENTVARIABLESFILE.warp_tmp" "$ENVIRONMENTVARIABLESFILE"
        # Deleting old data:
        sudo rm -rf $PROJECTPATH/.warp/docker/volumes/elasticsearch/* $PROJECTPATH/.warp/docker/volumes/elasticsearch/.* &> /dev/null
        ls_var=($(ls -a $PROJECTPATH/.warp/docker/volumes/elasticsearch/))
        if [[ ${#ls_var[@]} -gt 2 ]]; then
            warp_message_error "Can not remove old data"
            exit 1
        fi
        unset ls_var
        # Relaunch:
        warp start
    fi
}

function elasticsearch_main()
{
    case "$1" in
        elasticsearch)
		    shift 1
            elasticsearch_command "$@"  
        ;;

        flush)
            shift
            elasticsearch_flush "$@"
        ;;

        info)
            shift
            elasticsearch_info
        ;;

        ssh)
            shift
            elasticsearch_simil_ssh "$@"
        ;;

        switch)
            shift
            elasticsearch_switch "$@"
        ;;

        # --snapshot_repo_rebuild)
        #     elasticsearch_rebuild_snapshot_repo
        # ;;

        -h | --help)
            elasticsearch_help_usage
        ;;

        *)
		    elasticsearch_help_usage
        ;;
    esac
}

elasticsearch_ssh_wrong_input() {
    warp_message_error "Wrong input."
    elasticsearch_ssh_help
    exit 1
}

elasticsearch_flush_wrong_input() {
    warp_message_error "Wrong input."
    elasticsearch_flush_help
    exit 1
}


elasticsearch_make_snapshot() {
    : '
    This function builds an snapshot from your ES data.
    Input Args:
        1.- Snapshot Name (es_snapshot if there is no one).
    '
    if [[ -z $1 ]]; then
        es_snapshot_name='es_snapshot'
    fi

    warp_message_info "Snapshot path: $PROJECTPATH/$(warp_message_warn $es_snapshot_name)"

    elasticsearch_snapshot_repo_rebuild

    warp_process_message "Creating a Snapshot..."
    mkdir $PROJECTPATH/.warp/docker/elasticsearch_tmp &> /dev/null || { warp_message_error "Cannot create temp dir to allocate snapshot." ; exit 1; }
    snapshot_build_counter=0
    until [ $snapshot_build_counter -gt 20 ]; do
        curl --silent -X PUT "http://localhost:$ES_HOST2CONTAINER_PORT/_snapshot/backup/$es_snapshot_name?wait_for_completion=true&pretty" &> $PROJECTPATH/.warp/docker/elasticsearch_tmp/snapshot_details
        if  ! sed -n 2p $PROJECTPATH/.warp/docker/elasticsearch_tmp/snapshot_details | grep "error"; then
            printf "\t\t" ; warp_process_OK
            break
        fi
        sleep 1
        snapshot_build_counter=$((snapshot_build_counter + 1))
    done
    [ $snapshot_build_counter -gt 20 ] && { warp_process_FAIL ; exit 1; }
    unset snapshot_build_counter
    
    warp_process_message "Pulling the Snapshot..."
    ES_DOCKER_NAME=($(warp ps | grep "elasticsearch"))
    docker cp $ES_DOCKER_NAME:/usr/share/elasticsearch/snapshots $PROJECTPATH/.warp/docker/elasticsearch_tmp/ &> /dev/null || { warp_process_FAIL ; exit 1; }
    printf "\t\t" ; warp_process_OK

    warp_process_message "Making a tarball..."
    tar -czf $PROJECTPATH/$es_snapshot_name.tar.gz -C $PROJECTPATH/.warp/docker/elasticsearch_tmp/ . &> /dev/null || { warp_process_FAIL ; exit 1; }
    chmod 755 $PROJECTPATH/$es_snapshot_name.tar.gz
    printf "\t\t" ; warp_process_OK

    warp_process_message "Cleaning up..."
    rm -rf $PROJECTPATH/.warp/docker/elasticsearch_tmp &> /dev/null || { warp_process_FAIL ; exit 1; }
    docker-compose -f docker-compose-warp.yml exec elasticsearch bash -c "rm -rf /usr/share/elasticsearch/snapshots/*" &> /dev/null || { warp_process_FAIL ; exit 1; }
    printf "\t\t\t" ; warp_process_OK
}

elasticsearch_snapshot_repo_rebuild() {
    ES_HOST2CONTAINER_PORT=$(docker inspect --format='{{(index (index .NetworkSettings.Ports "9200/tcp") 0).HostPort}}' $(warp docker ps -q elasticsearch))
    curl --silent -X DELETE "localhost:$ES_HOST2CONTAINER_PORT/_snapshot/backup" &> /dev/null
    warp_process_message "Registering a Snapshot Repository..."
    
    ES_HOST2CONTAINER_PORT=$(docker inspect --format='{{(index (index .NetworkSettings.Ports "9200/tcp") 0).HostPort}}' $(warp docker ps -q elasticsearch))
    curl --silent -X PUT "http://localhost:$ES_HOST2CONTAINER_PORT/_snapshot/backup?pretty" -H 'Content-Type: application/json' -d'
    {
        "type": "fs",
        "settings": {
            "location": "/usr/share/elasticsearch/snapshots"
        }
    }
    ' &> /dev/null
    curl -X GET "http://localhost:$ES_HOST2CONTAINER_PORT/_snapshot/backup" 2>&1 | grep "\"backup\"" &> /dev/null || { warp_process_FAIL ; exit 1; }
    warp_process_OK
}
