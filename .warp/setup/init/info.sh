warp_message "* Configuring environment variable files $(warp_message_ok [ok])"
 [ ! -f $ENVIRONMENTVARIABLESFILE ] && cp $ENVIRONMENTVARIABLESFILESAMPLE $ENVIRONMENTVARIABLESFILE
 [ ! -f $DOCKERCOMPOSEFILE ] && cp $DOCKERCOMPOSEFILESAMPLE $DOCKERCOMPOSEFILE
 [ ! -f $DOCKERIGNOREFILE ] && cp $PROJECTPATH/.warp/setup/init/.dockerignore $DOCKERIGNOREFILE

warp_init_run_or_sudo() {
    "$@" 2>/dev/null && return 0

    if command -v sudo >/dev/null 2>&1; then
        sudo "$@"
        return $?
    fi

    return 1
}

# creating ext-xdebug.ini
if [ ! -f "$PROJECTPATH/.warp/docker/config/php/ext-xdebug.ini" ]; then
    warp_php_config_ensure_xdebug_file || exit 1

    case "$(uname -s)" in
        Darwin)

        IP_XDEBUG_MAC="10.254.254.254"
        IP_XDEBUG_LINUX="172.17.0.1"

        cat $PROJECTPATH/.warp/docker/config/php/ext-xdebug.ini | sed -e "s/$IP_XDEBUG_LINUX/$IP_XDEBUG_MAC/" > $PROJECTPATH/.warp/docker/config/php/ext-xdebug.ini.tmp
        mv $PROJECTPATH/.warp/docker/config/php/ext-xdebug.ini.tmp $PROJECTPATH/.warp/docker/config/php/ext-xdebug.ini

        # Disable XDEBUG for MacOS only, performance purpose
        sed -i -e 's/^zend_extension/\;zend_extension/g' $PROJECTPATH/.warp/docker/config/php/ext-xdebug.ini
        [ -f $PROJECTPATH/.warp/docker/config/php/ext-xdebug.ini-e ] && rm $PROJECTPATH/.warp/docker/config/php/ext-xdebug.ini-e 2> /dev/null
        ;;
    esac
fi

if [ ! -z "$DOCKER_PRIVATE_REGISTRY" ]
then
    # CONFIGURE VOLUME_DB MYSQL
    VOLUME_DB_WARP_DEFAULT="warp-volume-db"
    VOLUME_DB_WARP="$(basename $(pwd))-volume-db"

    cat $DOCKERCOMPOSEFILE | sed -e "s/$VOLUME_DB_WARP_DEFAULT/$VOLUME_DB_WARP/" > "$DOCKERCOMPOSEFILE.tmp"
    mv "$DOCKERCOMPOSEFILE.tmp" $DOCKERCOMPOSEFILE
fi

if [ -f $ENVIRONMENTVARIABLESFILE ]
then
    case "$(uname -s)" in
        Darwin)

        IP_XDEBUG_MAC="10.254.254.254"
        IP_XDEBUG_LINUX="172.17.0.1"

        cat $ENVIRONMENTVARIABLESFILE | sed -e "s/$IP_XDEBUG_LINUX/$IP_XDEBUG_MAC/" > $ENVIRONMENTVARIABLESFILE.tmp
        mv $ENVIRONMENTVARIABLESFILE.tmp $ENVIRONMENTVARIABLESFILE
        ;;
    esac

    VIRTUAL_HOST=$(warp_env_read_var VIRTUAL_HOST)

    cat $ENVIRONMENTVARIABLESFILE | sed -e "s/PHP_IDE_CONFIG=serverName=docker/PHP_IDE_CONFIG=serverName=$VIRTUAL_HOST/" > $ENVIRONMENTVARIABLESFILE.tmp
    mv $ENVIRONMENTVARIABLESFILE.tmp $ENVIRONMENTVARIABLESFILE
fi

warp_compose_dev_generate_from_final "$DOCKERCOMPOSEFILE" "$DOCKERCOMPOSEFILEDEV" || exit 1
warp_compose_prod_generate_from_final "$DOCKERCOMPOSEFILEDEV" "$DOCKERCOMPOSEFILEPROD" || exit 1

WARP_COMPOSE_PROFILE=$(warp_compose_profile_from_env "$ENVIRONMENTVARIABLESFILE")
warp_compose_activate_profile "$WARP_COMPOSE_PROFILE" "$DOCKERCOMPOSEFILE" "$DOCKERCOMPOSEFILEDEV" "$DOCKERCOMPOSEFILEPROD" || exit 1

# creating ext-ioncube.ini
if  [ ! -f $PROJECTPATH/.warp/docker/config/php/ext-ioncube.ini ] && [ -f $PROJECTPATH/.warp/docker/config/php/ext-ioncube.ini.sample ]
then
    cp $PROJECTPATH/.warp/docker/config/php/ext-ioncube.ini.sample $PROJECTPATH/.warp/docker/config/php/ext-ioncube.ini
fi

if [ ! -z $WARP_DETECT_MODE_TL ] ; then

    # Add include/exclude files to gitignore
    warp_check_gitignore
fi

if [ -d $PROJECTPATH/.warp ]; then
    warp_message "* Directory .warp $(warp_message_ok [ok])"
else
    warp_message "* Directory .warp $(warp_message_error [error])"
fi

warp_message "* Applying permissions to subdirectories .warp/docker/volumes $(warp_message_ok [ok])"

    # SET PERMISSIONS FOLDERS
    mkdir -p $PROJECTPATH/.warp/docker/volumes/nginx/logs
    warp_init_run_or_sudo chmod -R 777 $PROJECTPATH/.warp/docker/volumes/nginx
    warp_init_run_or_sudo chgrp -R 33 $PROJECTPATH/.warp/docker/volumes/nginx

    mkdir -p   $PROJECTPATH/.warp/docker/volumes/php-fpm/logs
    [ ! -f $PROJECTPATH/.warp/docker/volumes/php-fpm/logs/access.log ] && warp_init_run_or_sudo touch $PROJECTPATH/.warp/docker/volumes/php-fpm/logs/access.log
    [ ! -f $PROJECTPATH/.warp/docker/volumes/php-fpm/logs/fpm-error.log ] && warp_init_run_or_sudo touch $PROJECTPATH/.warp/docker/volumes/php-fpm/logs/fpm-error.log
    [ ! -f $PROJECTPATH/.warp/docker/volumes/php-fpm/logs/fpm-php.www.log ] && warp_init_run_or_sudo touch $PROJECTPATH/.warp/docker/volumes/php-fpm/logs/fpm-php.www.log
    warp_init_run_or_sudo chmod -R 777 $PROJECTPATH/.warp/docker/volumes/php-fpm
    warp_init_run_or_sudo chgrp -R 33 $PROJECTPATH/.warp/docker/volumes/php-fpm

    mkdir -p   $PROJECTPATH/.warp/docker/volumes/elasticsearch
    warp_init_run_or_sudo chmod -R 777 $PROJECTPATH/.warp/docker/volumes/elasticsearch

if declare -F warp_install_system_wrapper >/dev/null 2>&1; then
    warp_install_system_wrapper || exit 1
else
    WARP_WRAPPER_TEMPLATE="$PROJECTPATH/.warp/setup/bin/warp-wrapper.sh"
    if [ ! -f "$WARP_BINARY_FILE" ] ; then
        warp_message "* Installing warp wrapper $(warp_message_ok [ok])"
        sudo sh "$PROJECTPATH/.warp/lib/binary.sh" "$WARP_BINARY_FILE" "$WARP_WRAPPER_TEMPLATE"
    elif cmp -s "$WARP_BINARY_FILE" "$WARP_WRAPPER_TEMPLATE" 2>/dev/null; then
        warp_message "* Warp wrapper $(warp_message_ok [ok])"
    else
        warp_message "* Warp binary exists at $WARP_BINARY_FILE $(warp_message_warn [skip])"
        warp_message_warn "To replace it manually with the canonical wrapper:"
        warp_message_warn "sudo cp \"$WARP_WRAPPER_TEMPLATE\" \"$WARP_BINARY_FILE\" && sudo chmod 755 \"$WARP_BINARY_FILE\""
    fi
fi

warp_message ""
if [ ! -z $WARP_DETECT_MODE_TL ] ; then
    NGINX_CONFIG_FILE=$(warp_env_read_var NGINX_CONFIG_FILE)
    warp_message_warn "To complete the Nginx configuration, please edit this file: $(warp_message_bold $NGINX_CONFIG_FILE)"
    warp_message ""
fi

warp_message_warn "To start the containers: $(warp_message_bold './warp start')"
warp_message_warn "To see detailed information for each service configured: $(warp_message_bold './warp info')"
if [ -f "$DOCKERCOMPOSEFILEDEV" ]; then
    warp_message_warn "Development compose available: $(warp_message_bold './$(basename "$DOCKERCOMPOSEFILEDEV")')"
fi
if [ -f "$DOCKERCOMPOSEFILEPROD" ]; then
    warp_message_warn "Production compose available: $(warp_message_bold './$(basename "$DOCKERCOMPOSEFILEPROD")')"
fi

case "$(uname -s)" in
    Darwin)
        USE_DOCKER_SYNC=$(warp_env_read_var USE_DOCKER_SYNC)
        if [ "$USE_DOCKER_SYNC" = "N" ] || [ "$USE_DOCKER_SYNC" = "n" ]
        then 
            warp_message_warn "To copy all files from host to container: $(warp_message_bold './warp rsync push --all')"
        fi
    ;;
esac

sleep 1
