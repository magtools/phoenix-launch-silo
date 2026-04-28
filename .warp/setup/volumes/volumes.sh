warp_message ""
warp_message "* Configuring volumes in containers $(warp_message_ok [ok])"
sleep 1

    if [ ! -z "$docker_private_registry" ]
    then
        warp_compose_sample_append_dev "$PROJECTPATH/.warp/setup/volumes/tpl/volumes.yml" || exit 1
    fi    
