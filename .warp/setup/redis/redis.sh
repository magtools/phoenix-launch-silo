#!/bin/bash +x

warp_message ""
warp_message_info "Configuring the Redis Service"

PATH_CONFIG_REDIS='./.warp/docker/config/redis'
MSJ_REDIS_VERSION_HUB=1 # True
REDIS_SERVICE_SELECTED=0
CACHE_CANON_SCOPE=""
CACHE_CANON_HOST=""
CACHE_CANON_PORT="6379"

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

    if [ $MSJ_REDIS_VERSION_HUB = 1 ] ; then
        warp_message_info2 "You can check the Redis versions available here: $(warp_message_info '[ https://hub.docker.com/_/redis/ ]')"
        MSJ_REDIS_VERSION_HUB=0 # False
        echo "#Config Redis" >> $ENVIRONMENTVARIABLESFILESAMPLE
    fi
  
    resp_version_cache=$( warp_question_ask_default "What version of Redis cache do you want to use? $(warp_message_info [5.0]) " "5.0" )
    warp_message_info2 "Selected Redis Cache version: $resp_version_cache, in the internal port 6379 $(warp_message_bold 'redis-cache:6379')"

    cache_config_file_cache=$( warp_question_ask_default "Set Redis configuration file: $(warp_message_info [./.warp/docker/config/redis/redis.conf]) " "./.warp/docker/config/redis/redis.conf" )
    warp_message_info2 "Selected configuration file: $cache_config_file_cache"
    
    cat $PROJECTPATH/.warp/setup/redis/tpl/redis_cache.yml >> $DOCKERCOMPOSEFILESAMPLE

    echo "REDIS_CACHE_VERSION=$resp_version_cache" >> $ENVIRONMENTVARIABLESFILESAMPLE
    echo "REDIS_CACHE_CONF=$cache_config_file_cache" >> $ENVIRONMENTVARIABLESFILESAMPLE
    echo "REDIS_CACHE_MAXMEMORY=512mb" >> $ENVIRONMENTVARIABLESFILESAMPLE
    echo "REDIS_CACHE_MAXMEMORY_POLICY=allkeys-lru" >> $ENVIRONMENTVARIABLESFILESAMPLE
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

    if [ $MSJ_REDIS_VERSION_HUB = 1 ] ; then
        warp_message_info2 "You can check the Redis versions available here: $(warp_message_info '[ https://hub.docker.com/_/redis/ ]')"
        MSJ_REDIS_VERSION_HUB=0 # False
        echo "#Config Redis" >> $ENVIRONMENTVARIABLESFILESAMPLE
    fi
  
    resp_version_session=$( warp_question_ask_default "What version of Redis Session do you want to use? $(warp_message_info [5.0]) " "5.0" )
    warp_message_info2 "Selected version of Redis Session: $resp_version_session, in the internal port 6379 $(warp_message_bold 'redis-session:6379')"

    cache_config_file_session=$( warp_question_ask_default "Set Redis configuration file: $(warp_message_info [./.warp/docker/config/redis/redis.conf]) " "./.warp/docker/config/redis/redis.conf" )
    warp_message_info2 "Selected configuration file: $cache_config_file_session"

    cat $PROJECTPATH/.warp/setup/redis/tpl/redis_session.yml >> $DOCKERCOMPOSEFILESAMPLE

    echo "REDIS_SESSION_VERSION=$resp_version_session" >> $ENVIRONMENTVARIABLESFILESAMPLE
    echo "REDIS_SESSION_CONF=$cache_config_file_session" >> $ENVIRONMENTVARIABLESFILESAMPLE
    echo "REDIS_SESSION_MAXMEMORY=256mb" >> $ENVIRONMENTVARIABLESFILESAMPLE
    echo "REDIS_SESSION_MAXMEMORY_POLICY=noeviction" >> $ENVIRONMENTVARIABLESFILESAMPLE
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

    if [ $MSJ_REDIS_VERSION_HUB = 1 ] ; then
        warp_message_info2 "You can check the Redis versions available here: $(warp_message_info '[ https://hub.docker.com/_/redis/ ]')"
        MSJ_REDIS_VERSION_HUB=0 # False
        #echo "#Config Redis" >> $ENVIRONMENTVARIABLESFILESAMPLE
    fi

    resp_version_fpc=$( warp_question_ask_default "What version of Redis FPC do you want to use? $(warp_message_info [5.0]) " "5.0" )
    warp_message_info2 "Selected Redis FPC version: $resp_version_fpc, in the internal port 6379 $(warp_message_bold 'redis-fpc:6379')"

    cache_config_file_fpc=$( warp_question_ask_default "Set Redis configuration file: $(warp_message_info [./.warp/docker/config/redis/redis.conf]) " "./.warp/docker/config/redis/redis.conf" )
    warp_message_info2 "Selected configuration file: $cache_config_file_fpc"

    cat $PROJECTPATH/.warp/setup/redis/tpl/redis_fpc.yml >> $DOCKERCOMPOSEFILESAMPLE

    echo "REDIS_FPC_VERSION=$resp_version_fpc" >> $ENVIRONMENTVARIABLESFILESAMPLE
    echo "REDIS_FPC_CONF=$cache_config_file_fpc" >> $ENVIRONMENTVARIABLESFILESAMPLE
    echo "REDIS_FPC_MAXMEMORY=512mb" >> $ENVIRONMENTVARIABLESFILESAMPLE
    echo "REDIS_FPC_MAXMEMORY_POLICY=allkeys-lru" >> $ENVIRONMENTVARIABLESFILESAMPLE
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
    echo "# Canonical CACHE Configuration" >> $ENVIRONMENTVARIABLESFILESAMPLE
    echo "CACHE_MODE=local" >> $ENVIRONMENTVARIABLESFILESAMPLE
    echo "CACHE_ENGINE=redis" >> $ENVIRONMENTVARIABLESFILESAMPLE
    echo "CACHE_SCOPE=${CACHE_CANON_SCOPE:-cache}" >> $ENVIRONMENTVARIABLESFILESAMPLE
    echo "CACHE_HOST=${CACHE_CANON_HOST:-redis-cache}" >> $ENVIRONMENTVARIABLESFILESAMPLE
    echo "CACHE_PORT=${CACHE_CANON_PORT:-6379}" >> $ENVIRONMENTVARIABLESFILESAMPLE
    echo "" >> $ENVIRONMENTVARIABLESFILESAMPLE
fi
