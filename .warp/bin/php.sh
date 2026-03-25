#!/bin/bash

    # IMPORT HELP

    . "$PROJECTPATH/.warp/bin/php_help.sh"

function php_info()
{

    if ! warp_check_env_file ; then
        warp_message_error "file not found $(basename $ENVIRONMENTVARIABLESFILE)"
        exit
    fi; 

    PHP_VERSION=$(warp_env_read_var PHP_VERSION)

    warp_message ""
    warp_message_info "* PHP"

    if [ ! -z "$PHP_VERSION" ]; then
        warp_message "Version:                    $(warp_message_info $PHP_VERSION)"
    fi

    if [ -f "$DOCKERCOMPOSEFILE" ]; then
        warp_message "Mode:                       $(warp_message_info docker)"
        warp_message "Logs:                       $(warp_message_info $PROJECTPATH/.warp/docker/volumes/php-fpm/logs)"
        warp_message "Xdebug file:                $(warp_message_info $PROJECTPATH/.warp/docker/config/php/ext-xdebug.ini)"
        warp_message "php.ini file:               $(warp_message_info $PROJECTPATH/.warp/docker/config/php/php.ini)"
        warp_message "Cron file:                  $(warp_message_info $PROJECTPATH/.warp/docker/config/crontab/cronfile)"
        warp_message ""
        warp_message_warn " - In order to configure Xdebug, please check FAQs here: $(warp_message_bold 'http://ct.summasolutions.net/warp-engine/?#anchorFAQs')"
    else
        _host_php_version="N/A"
        if command -v php >/dev/null 2>&1; then
            _host_php_version=$(php -r 'echo PHP_VERSION;' 2>/dev/null)
        fi
        warp_message "Mode:                       $(warp_message_info host)"
        warp_message "Host php binary:            $(warp_message_info ${_host_php_version:-N/A})"
        warp_message "docker-compose file:        $(warp_message_warn not found)"
        warp_message_warn " - In host mode, use 'warp magento ...' to run bin/magento with local php."
    fi

    warp_message ""
}

function php_version()
{
    if [ -f "$DOCKERCOMPOSEFILE" ]; then
        if [ "$(warp_check_is_running)" = false ]; then
            warp_message_error "The containers are not running"
            warp_message_error "please, first run warp start"
            exit 1
        fi

        docker-compose -f "$DOCKERCOMPOSEFILE" exec -T php php -r 'echo PHP_VERSION;'
        echo ""
        return 0
    fi

    if ! command -v php >/dev/null 2>&1; then
        warp_message_error "php binary not found in host"
        exit 1
    fi

    php -r 'echo PHP_VERSION;'
    echo ""
}

php_simil_ssh() {
    : '
    This function provides a bash pipe as root or www-data user.
    It is called as SSH in order to make it better for developers ack
    but it does not use Secure Shell anywhere.
    '

    # Check for wrong input:
    if [[ $# -gt 1 ]]; then
        php_ssh_wrong_input
        exit 1
    else
        if [ ! -f "$DOCKERCOMPOSEFILE" ]; then
            warp_message_error "docker-compose-warp.yml not found"
            warp_message_warn "php ssh is only available for docker mode"
            exit 1
        fi

        if [[ $1 == "--root" ]]; then
            # Check if warp is running:    
            if [ "$(warp_check_is_running)" = false ]; then
                warp_message_error "The containers are not running"
                warp_message_error "please, first run warp start"
                exit 1
            fi
            docker-compose -f "$DOCKERCOMPOSEFILE" exec -u root php bash
        elif [[ -z $1 || $1 == "--www-data" ]]; then
            # Check if warp is running:    
            if [ "$(warp_check_is_running)" = false ]; then
                warp_message_error "The containers are not running"
                warp_message_error "please, first run warp start"
                exit 1
            fi
            docker-compose -f "$DOCKERCOMPOSEFILE" exec -u www-data php bash
        elif [[ $1 == "-h" || $1 == "--help" ]]; then
            php_ssh_help
            exit 0
        else
            php_ssh_wrong_input
            exit 1
        fi
    fi
}

function php_switch() 
{

    if [ "$1" = "-h" ] || [ "$1" = "--help" ] || [ -z "$1" ]
    then
        php_switch_help 
        exit 1
    fi;

    if [ "$(warp_check_is_running)" = true ]; then
        warp_message_error "The containers are running"
        warp_message_error "please, first run warp stop --hard"

        exit 1;
    fi

    PHP_VERSION_CURRENT=$(warp_env_read_var PHP_VERSION)
    warp_message_info2 "You current PHP version is: $PHP_VERSION_CURRENT"

    if [ $PHP_VERSION_CURRENT = $1 ]
    then
        warp_message_info2 "the selected version is the same as the previous one, no changes will be made"
        warp_message_warn "for help run: $(warp_message_bold './warp php switch --help')"
    else
        php_version=$1
        case $php_version in
        '7.3-fpm'| '7.4-fpm' | '7.4-fpm_v2' |'7.4.15-fpm' | '8.1.3-fpm' | '8.2.3-fpm' | '8.3-fpm' | '8.4-fpm')
            warp_message_info2 "PHP new version selected: $php_version"
        ;;
        *)
            warp_message_info2 "Selected: $php_version, the available versions are 7.3-fpm, 7.4-fpm, 7.4-fpm_v2, 7.4-fpm-v2_arm, 7.4.15-fpm, 8.1.3-fpm, 8.2.3-fpm, 8.3-fpm, 8.4-fpm"
            warp_message_warn "for help run: $(warp_message_bold './warp php switch --help')"
            exit 1;
        ;;
        esac
        
        if [ -d $CONFIGFOLDER/php ]
        then
            warp_message "* reset php configurations files $(warp_message_ok [ok])"
            rm  -rf $CONFIGFOLDER/php 2> /dev/null
        fi

        warp_message "* creating configurations files $(warp_message_ok [ok])"
        # copy base files
        cp -R $PROJECTPATH/.warp/setup/php/config/php $CONFIGFOLDER/php

        warp_message "* setting samples files $(warp_message_ok [ok])"
        # helper create .sample files
        . "$WARPFOLDER/setup/php/php-helper.sh"

        # Change .env and .env.sample
        warp_message "* change environment file $(warp_message_ok [ok])"                

        PHP_VERSION_OLD="PHP_VERSION=$PHP_VERSION_CURRENT"
        PHP_VERSION_NEW="PHP_VERSION=$php_version"

        cat $ENVIRONMENTVARIABLESFILE | sed -e "s/$PHP_VERSION_OLD/$PHP_VERSION_NEW/" > "$ENVIRONMENTVARIABLESFILE.warp_tmp"
        mv "$ENVIRONMENTVARIABLESFILE.warp_tmp" $ENVIRONMENTVARIABLESFILE

        cat $ENVIRONMENTVARIABLESFILESAMPLE | sed -e "s/$PHP_VERSION_OLD/$PHP_VERSION_NEW/" > "$ENVIRONMENTVARIABLESFILESAMPLE.warp_tmp"
        mv "$ENVIRONMENTVARIABLESFILESAMPLE.warp_tmp" $ENVIRONMENTVARIABLESFILESAMPLE

        # creating ext-xdebug.ini
        if  [ ! -f $PROJECTPATH/.warp/docker/config/php/ext-xdebug.ini ] && [ -f $PROJECTPATH/.warp/docker/config/php/ext-xdebug.ini.sample ]
        then
            cp $PROJECTPATH/.warp/docker/config/php/ext-xdebug.ini.sample $PROJECTPATH/.warp/docker/config/php/ext-xdebug.ini

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

        # creating ext-ioncube.ini
        if  [ ! -f $PROJECTPATH/.warp/docker/config/php/ext-ioncube.ini ] && [ -f $PROJECTPATH/.warp/docker/config/php/ext-ioncube.ini.sample ]
        then
            cp $PROJECTPATH/.warp/docker/config/php/ext-ioncube.ini.sample $PROJECTPATH/.warp/docker/config/php/ext-ioncube.ini
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

        warp_message_warn "* commit new changes"
        warp_message_warn "* at each environment run: $(warp_message_bold './warp reset')"
    fi
}

function php_main()
{
    case "$1" in
        ssh)
            shift 1
            php_simil_ssh "$@"
        ;;

        info)
            php_info
        ;;

        version|--version)
            php_version
        ;;

        switch)
            shift 1
            php_switch "$@"
        ;;

        -h | --help)
            php_help_usage
        ;;

        *)            
            php_help_usage
        ;;
    esac
}

php_ssh_wrong_input() {
    warp_message_error "Wrong input."
    php_ssh_help
    exit 1
}
