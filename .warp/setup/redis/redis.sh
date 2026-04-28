#!/bin/bash +x

redis_setup_resolve_engine() {
    local _allowed_csv=""
    local _compat_note=""
    local _selected=""

    if [ -n "$CACHE_ENGINE_SELECTED" ]; then
        return 0
    fi

    CACHE_ENGINE_SELECTED=$(warp_cache_engine_recommended_from_context)
    _allowed_csv=$(warp_app_context_engines_csv cache)
    _compat_note=$(warp_app_context_cache_note 2>/dev/null || true)

    if [ -n "$_compat_note" ]; then
        warp_message_info2 "$_compat_note"
    fi

    if printf '%s' "$_allowed_csv" | grep -q '|'; then
        if [ "$WARP_APP_FRAMEWORK" = "magento" ] && [ "$WARP_APP_COMPAT_PROFILE" != "general" ]; then
            warp_message_info2 "Additional cache engines are shown because Warp detected Magento compatibility profile: $(warp_message_info "$WARP_APP_COMPAT_PROFILE")"
        fi
        warp_app_context_show_engine_options cache
        while : ; do
            _selected=$(warp_question_ask_default "Choose the cache engine: $(warp_message_info [$CACHE_ENGINE_SELECTED]) $(warp_message '[ '"$_allowed_csv"' ]') " "$CACHE_ENGINE_SELECTED")
            case "$_selected" in
                redis|valkey)
                    if warp_app_context_engine_class cache "$_selected" >/dev/null 2>&1; then
                        CACHE_ENGINE_SELECTED="$_selected"
                        break
                    fi
                    ;;
            esac
            warp_message_warn "wrong engine, choose one of: $(warp_message_info "$_allowed_csv")"
        done
    fi

    CACHE_IMAGE_REPO=$(warp_service_version_image_repo cache "$CACHE_ENGINE_SELECTED")
    CACHE_VERSION_DEFAULT=$(warp_service_version_tag_default cache "$CACHE_ENGINE_SELECTED")
    CACHE_TAGS_SUGGESTED=$(warp_service_version_tags_csv cache "$CACHE_ENGINE_SELECTED" suggested)
    CACHE_TAGS_LEGACY=$(warp_service_version_tags_csv cache "$CACHE_ENGINE_SELECTED" legacy)
}

redis_setup_default_config() {
    warp_cache_engine_default_host_config "$CACHE_ENGINE_SELECTED"
}

redis_setup_write_canonical_env() {
    local _cache_version_canonical="$1"

    echo "# Canonical CACHE Configuration" >> "$ENVIRONMENTVARIABLESFILESAMPLE"
    echo "CACHE_MODE=local" >> "$ENVIRONMENTVARIABLESFILESAMPLE"
    echo "CACHE_ENGINE=$CACHE_ENGINE_SELECTED" >> "$ENVIRONMENTVARIABLESFILESAMPLE"
    echo "CACHE_VERSION=$_cache_version_canonical" >> "$ENVIRONMENTVARIABLESFILESAMPLE"
    echo "CACHE_IMAGE_REPO=$CACHE_IMAGE_REPO" >> "$ENVIRONMENTVARIABLESFILESAMPLE"
    echo "CACHE_SERVER_BIN=$(warp_cache_engine_server_bin "$CACHE_ENGINE_SELECTED")" >> "$ENVIRONMENTVARIABLESFILESAMPLE"
    echo "CACHE_CLI_BIN=$(warp_cache_engine_cli_bin "$CACHE_ENGINE_SELECTED")" >> "$ENVIRONMENTVARIABLESFILESAMPLE"
    echo "CACHE_CONTAINER_USER=$(warp_cache_engine_container_user "$CACHE_ENGINE_SELECTED")" >> "$ENVIRONMENTVARIABLESFILESAMPLE"
    echo "CACHE_CONTAINER_CONFIG_PATH=$(warp_cache_engine_container_config_path "$CACHE_ENGINE_SELECTED")" >> "$ENVIRONMENTVARIABLESFILESAMPLE"
    echo "CACHE_SCOPE=${CACHE_CANON_SCOPE:-cache}" >> "$ENVIRONMENTVARIABLESFILESAMPLE"
    echo "CACHE_HOST=${CACHE_CANON_HOST:-redis-cache}" >> "$ENVIRONMENTVARIABLESFILESAMPLE"
    echo "CACHE_PORT=${CACHE_CANON_PORT:-6379}" >> "$ENVIRONMENTVARIABLESFILESAMPLE"
    echo "CACHE_USER=" >> "$ENVIRONMENTVARIABLESFILESAMPLE"
    echo "" >> "$ENVIRONMENTVARIABLESFILESAMPLE"
}

warp_message ""
warp_message_info "Configuring the Redis Service"

PATH_CONFIG_REDIS='./.warp/docker/config/redis'
MSJ_REDIS_VERSION_HUB=1 # True
REDIS_SERVICE_SELECTED=0
CACHE_CANON_SCOPE=""
CACHE_CANON_HOST=""
CACHE_CANON_PORT="6379"
CACHE_ENGINE_SELECTED=""
CACHE_IMAGE_REPO=""
CACHE_VERSION_DEFAULT=""
CACHE_TAGS_SUGGESTED=""
CACHE_TAGS_LEGACY=""
resp_version_cache=""
resp_version_session=""
resp_version_fpc=""

while : ; do
    respuesta_redis_cache=$( warp_question_ask_default "Do you want to add a service for Redis Cache? $(warp_message_info [Y/n]) " "Y" )

    if [ "$respuesta_redis_cache" = "Y" ] || [ "$respuesta_redis_cache" = "y" ] || [ "$respuesta_redis_cache" = "N" ] || [ "$respuesta_redis_cache" = "n" ] ; then
        break
    else
        warp_message_warn "wrong answer, you must select between two options: $(warp_message_info [Y/n]) "
    fi
done

if [ "$respuesta_redis_cache" = "Y" ] || [ "$respuesta_redis_cache" = "y" ]
then

    redis_setup_resolve_engine

    if [ $MSJ_REDIS_VERSION_HUB = 1 ] ; then
        warp_message_info2 "Selected cache engine: $(warp_message_info "$CACHE_ENGINE_SELECTED") [$(warp_app_context_engine_class cache "$CACHE_ENGINE_SELECTED")]"
        if [ "$CACHE_ENGINE_SELECTED" = "valkey" ]; then
            warp_message_info2 "You can check the ${CACHE_ENGINE_SELECTED} versions available here: $(warp_message_info '[ https://hub.docker.com/r/valkey/valkey/tags/ ]')"
        else
            warp_message_info2 "You can check the ${CACHE_ENGINE_SELECTED} versions available here: $(warp_message_info '[ https://hub.docker.com/_/redis/ ]')"
        fi
        [ -n "$CACHE_TAGS_SUGGESTED" ] && warp_message_info2 "Suggested ${CACHE_ENGINE_SELECTED} tags: $(warp_message_info "$CACHE_TAGS_SUGGESTED")"
        [ -n "$CACHE_TAGS_LEGACY" ] && warp_message_info2 "Legacy/manual ${CACHE_ENGINE_SELECTED} tags: $(warp_message_info "$CACHE_TAGS_LEGACY")"
        MSJ_REDIS_VERSION_HUB=0 # False
        echo "#Config Redis" >> $ENVIRONMENTVARIABLESFILESAMPLE
    fi
  
    resp_version_cache=$( warp_service_version_prompt_tag cache "$CACHE_ENGINE_SELECTED" "What version of ${CACHE_ENGINE_SELECTED} cache do you want to use? $(warp_message_info [$CACHE_VERSION_DEFAULT]) " "$CACHE_VERSION_DEFAULT" )
    warp_message_info2 "Selected Redis Cache version: $resp_version_cache, in the internal port 6379 $(warp_message_bold 'redis-cache:6379')"

    cache_config_file_cache=$( warp_question_ask_default "Set Redis configuration file: $(warp_message_info [$(redis_setup_default_config)]) " "$(redis_setup_default_config)" )
    warp_message_info2 "Selected configuration file: $cache_config_file_cache"
    
    warp_compose_sample_append_dev \
        "$PROJECTPATH/.warp/setup/redis/tpl/redis_cache.yml" || exit 1

    echo "REDIS_CACHE_VERSION=$resp_version_cache" >> $ENVIRONMENTVARIABLESFILESAMPLE
    echo "REDIS_CACHE_CONF=$cache_config_file_cache" >> $ENVIRONMENTVARIABLESFILESAMPLE
    echo "REDIS_CACHE_MAXMEMORY=512mb" >> $ENVIRONMENTVARIABLESFILESAMPLE
    echo "REDIS_CACHE_MAXMEMORY_POLICY=allkeys-lru" >> $ENVIRONMENTVARIABLESFILESAMPLE
    echo "REDIS_CACHE_BINDED_PORT=6379" >> $ENVIRONMENTVARIABLESFILESAMPLE
    echo "" >> $ENVIRONMENTVARIABLESFILESAMPLE
    REDIS_SERVICE_SELECTED=1
    [ -n "$CACHE_CANON_SCOPE" ] || CACHE_CANON_SCOPE="cache"
    [ -n "$CACHE_CANON_HOST" ] || CACHE_CANON_HOST="redis-cache"
    [ -n "$CACHE_CANON_PORT" ] || CACHE_CANON_PORT="6379"

    # Control will enter here if $PATH_CONFIG_REDIS doesn't exist.
    if [ ! -d "$PATH_CONFIG_REDIS" ]; then
        cp -R ./.warp/setup/redis/config/redis $PATH_CONFIG_REDIS
    fi
    warp_message ""
fi; 

while : ; do
    respuesta_redis_session=$( warp_question_ask_default "Do you want to add a service for Redis Session? $(warp_message_info [Y/n]) " "Y" )

    if [ "$respuesta_redis_session" = "Y" ] || [ "$respuesta_redis_session" = "y" ] || [ "$respuesta_redis_session" = "N" ] || [ "$respuesta_redis_session" = "n" ] ; then
        break
    else
        warp_message_warn "wrong answer, you must select between two options: $(warp_message_info [Y/n]) "
    fi
done

if [ "$respuesta_redis_session" = "Y" ] || [ "$respuesta_redis_session" = "y" ]
then

    redis_setup_resolve_engine

    if [ $MSJ_REDIS_VERSION_HUB = 1 ] ; then
        warp_message_info2 "Selected cache engine: $(warp_message_info "$CACHE_ENGINE_SELECTED") [$(warp_app_context_engine_class cache "$CACHE_ENGINE_SELECTED")]"
        if [ "$CACHE_ENGINE_SELECTED" = "valkey" ]; then
            warp_message_info2 "You can check the ${CACHE_ENGINE_SELECTED} versions available here: $(warp_message_info '[ https://hub.docker.com/r/valkey/valkey/tags/ ]')"
        else
            warp_message_info2 "You can check the ${CACHE_ENGINE_SELECTED} versions available here: $(warp_message_info '[ https://hub.docker.com/_/redis/ ]')"
        fi
        [ -n "$CACHE_TAGS_SUGGESTED" ] && warp_message_info2 "Suggested ${CACHE_ENGINE_SELECTED} tags: $(warp_message_info "$CACHE_TAGS_SUGGESTED")"
        [ -n "$CACHE_TAGS_LEGACY" ] && warp_message_info2 "Legacy/manual ${CACHE_ENGINE_SELECTED} tags: $(warp_message_info "$CACHE_TAGS_LEGACY")"
        MSJ_REDIS_VERSION_HUB=0 # False
        echo "#Config Redis" >> $ENVIRONMENTVARIABLESFILESAMPLE
    fi
  
    resp_version_session=$( warp_service_version_prompt_tag cache "$CACHE_ENGINE_SELECTED" "What version of ${CACHE_ENGINE_SELECTED} Session do you want to use? $(warp_message_info [$CACHE_VERSION_DEFAULT]) " "$CACHE_VERSION_DEFAULT" )
    warp_message_info2 "Selected version of Redis Session: $resp_version_session, in the internal port 6379 $(warp_message_bold 'redis-session:6379')"

    cache_config_file_session=$( warp_question_ask_default "Set Redis configuration file: $(warp_message_info [$(redis_setup_default_config)]) " "$(redis_setup_default_config)" )
    warp_message_info2 "Selected configuration file: $cache_config_file_session"

    warp_compose_sample_append_dev \
        "$PROJECTPATH/.warp/setup/redis/tpl/redis_session.yml" || exit 1

    echo "REDIS_SESSION_VERSION=$resp_version_session" >> $ENVIRONMENTVARIABLESFILESAMPLE
    echo "REDIS_SESSION_CONF=$cache_config_file_session" >> $ENVIRONMENTVARIABLESFILESAMPLE
    echo "REDIS_SESSION_MAXMEMORY=256mb" >> $ENVIRONMENTVARIABLESFILESAMPLE
    echo "REDIS_SESSION_MAXMEMORY_POLICY=noeviction" >> $ENVIRONMENTVARIABLESFILESAMPLE
    echo "REDIS_SESSION_BINDED_PORT=6380" >> $ENVIRONMENTVARIABLESFILESAMPLE
    echo "" >> $ENVIRONMENTVARIABLESFILESAMPLE
    REDIS_SERVICE_SELECTED=1
    if [ -z "$CACHE_CANON_SCOPE" ]; then
        CACHE_CANON_SCOPE="session"
        CACHE_CANON_HOST="redis-session"
        CACHE_CANON_PORT="6379"
    fi

    # Control will enter here if $PATH_CONFIG_REDIS doesn't exist.
    if [ ! -d "$PATH_CONFIG_REDIS" ]; then
        cp -R ./.warp/setup/redis/config/redis $PATH_CONFIG_REDIS
    fi
    warp_message ""
fi; 

while : ; do
    respuesta_redis_fpc=$( warp_question_ask_default "Do you want to add a service for Redis FPC? $(warp_message_info [Y/n]) " "Y" )

    if [ "$respuesta_redis_fpc" = "Y" ] || [ "$respuesta_redis_fpc" = "y" ] || [ "$respuesta_redis_fpc" = "N" ] || [ "$respuesta_redis_fpc" = "n" ] ; then
        break
    else
        warp_message_warn "wrong answer, you must select between two options: $(warp_message_info [Y/n]) "
    fi
done

if [ "$respuesta_redis_fpc" = "Y" ] || [ "$respuesta_redis_fpc" = "y" ]
then

    redis_setup_resolve_engine

    if [ $MSJ_REDIS_VERSION_HUB = 1 ] ; then
        warp_message_info2 "Selected cache engine: $(warp_message_info "$CACHE_ENGINE_SELECTED") [$(warp_app_context_engine_class cache "$CACHE_ENGINE_SELECTED")]"
        if [ "$CACHE_ENGINE_SELECTED" = "valkey" ]; then
            warp_message_info2 "You can check the ${CACHE_ENGINE_SELECTED} versions available here: $(warp_message_info '[ https://hub.docker.com/r/valkey/valkey/tags/ ]')"
        else
            warp_message_info2 "You can check the ${CACHE_ENGINE_SELECTED} versions available here: $(warp_message_info '[ https://hub.docker.com/_/redis/ ]')"
        fi
        [ -n "$CACHE_TAGS_SUGGESTED" ] && warp_message_info2 "Suggested ${CACHE_ENGINE_SELECTED} tags: $(warp_message_info "$CACHE_TAGS_SUGGESTED")"
        [ -n "$CACHE_TAGS_LEGACY" ] && warp_message_info2 "Legacy/manual ${CACHE_ENGINE_SELECTED} tags: $(warp_message_info "$CACHE_TAGS_LEGACY")"
        MSJ_REDIS_VERSION_HUB=0 # False
        #echo "#Config Redis" >> $ENVIRONMENTVARIABLESFILESAMPLE
    fi

    resp_version_fpc=$( warp_service_version_prompt_tag cache "$CACHE_ENGINE_SELECTED" "What version of ${CACHE_ENGINE_SELECTED} FPC do you want to use? $(warp_message_info [$CACHE_VERSION_DEFAULT]) " "$CACHE_VERSION_DEFAULT" )
    warp_message_info2 "Selected Redis FPC version: $resp_version_fpc, in the internal port 6379 $(warp_message_bold 'redis-fpc:6379')"

    cache_config_file_fpc=$( warp_question_ask_default "Set Redis configuration file: $(warp_message_info [$(redis_setup_default_config)]) " "$(redis_setup_default_config)" )
    warp_message_info2 "Selected configuration file: $cache_config_file_fpc"

    warp_compose_sample_append_dev \
        "$PROJECTPATH/.warp/setup/redis/tpl/redis_fpc.yml" || exit 1

    echo "REDIS_FPC_VERSION=$resp_version_fpc" >> $ENVIRONMENTVARIABLESFILESAMPLE
    echo "REDIS_FPC_CONF=$cache_config_file_fpc" >> $ENVIRONMENTVARIABLESFILESAMPLE
    echo "REDIS_FPC_MAXMEMORY=512mb" >> $ENVIRONMENTVARIABLESFILESAMPLE
    echo "REDIS_FPC_MAXMEMORY_POLICY=allkeys-lru" >> $ENVIRONMENTVARIABLESFILESAMPLE
    echo "REDIS_FPC_BINDED_PORT=6381" >> $ENVIRONMENTVARIABLESFILESAMPLE
    echo "" >> $ENVIRONMENTVARIABLESFILESAMPLE
    REDIS_SERVICE_SELECTED=1
    if [ -z "$CACHE_CANON_SCOPE" ]; then
        CACHE_CANON_SCOPE="fpc"
        CACHE_CANON_HOST="redis-fpc"
        CACHE_CANON_PORT="6379"
    fi

    # Control will enter here if $PATH_CONFIG_REDIS doesn't exist.
    if [ ! -d "$PATH_CONFIG_REDIS" ]; then
        cp -R ./.warp/setup/redis/config/redis $PATH_CONFIG_REDIS
    fi
    warp_message ""
fi; 

if [ "$REDIS_SERVICE_SELECTED" = "1" ]
then
    cache_version_canonical="$resp_version_cache"
    if [ -z "$cache_version_canonical" ]; then
        cache_version_canonical="$resp_version_session"
    fi
    if [ -z "$cache_version_canonical" ]; then
        cache_version_canonical="$resp_version_fpc"
    fi

    redis_setup_write_canonical_env "$cache_version_canonical"
fi
