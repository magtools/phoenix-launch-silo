#!/bin/bash +x

echo ""
warp_message_info "Configuring PHP Service"

while : ; do
    respuesta_php=$( warp_question_ask_default "Do you want to add a php service? $(warp_message_info [Y/n]) " "Y" )

    if [ "$respuesta_php" = "Y" ] || [ "$respuesta_php" = "y" ] || [ "$respuesta_php" = "N" ] || [ "$respuesta_php" = "n" ] ; then
        break
    else
        warp_message_warn "wrong answer, you must select between two options: $(warp_message_info [Y/n]) "
    fi
done

if [ "$respuesta_php" = "Y" ] || [ "$respuesta_php" = "y" ]
then
    warp_message_info2 "You can check the available PHP versions from: $(warp_message_info '[ https://hub.docker.com/r/summasolutions/php/tags/ ]')"
    while : ; do
        if [ $(uname -m) == 'arm64' ] ; then
            php_version=$( warp_question_ask_default "Set the PHP version of your project: $(warp_message_info [7.4-fpm-v2_arm]) " "7.4-fpm-v2_arm" )
        else 
            php_version=$( warp_question_ask_default "Set the PHP version of your project: $(warp_message_info [7.4-fpm_v2]) " "7.4-fpm_v2" )
        fi
        case $php_version in
        '5.6-fpm' | '7.0-fpm' | '7.1.26-fpm' | '7.2.24-fpm' | '7.3-fpm' | '7.3-fpm_v2' | '7.3-fpm-v2_arm' | '7.4-fpm' | '7.4-fpm_v2' | '7.4-fpm-v2_arm' | '7.4.15-fpm' | '8.1.3-fpm' | '8.2.3-fpm' | '8.3-fpm' | '8.4-fpm')
            break
        ;;
        *)
            warp_message_info2 "Selected: $php_version, the available versions are 5.6-fpm, 7.0-fpm, 7.1.26-fpm, 7.2-fpm, 7.2-fpm_arm, 7.2.24-fpm, 7.3-fpm, 7.3-fpm_v2, 7.3-fpm-v2_arm, 7.4-fpm, 7.4-fpm_v2, 7.4-fpm-v2_arm, 7.4.15-fpm, 8.1.3-fpm, 8.2.3-fpm, 8.3-fpm, 8.4-fpm"
        ;;
        esac
    done
    warp_message_info2 "PHP version selected: $php_version"

    PHP_EXTRA_LIBS_FLAG=$( warp_question_ask_default "Do you want to add extra libs? $(warp_message_info [y/N]) " "N" )

    if [[ $PHP_EXTRA_LIBS_FLAG == 'Y' || $PHP_EXTRA_LIBS_FLAG == 'y' ]]; then
        case "$php_version" in
            5.6-fpm)
                PHP_BASE_LIBS=("${PHP_5_6_fpm_BASE_LIBS[@]}")
                PHP_AVAILABLE_LIBS=("${PHP_5_6_AVAILABLE_LIBS[@]}")
            ;;
            7.0-fpm)
                PHP_BASE_LIBS=("${PHP_7_0_fpm_BASE_LIBS[@]}")
                PHP_AVAILABLE_LIBS=("${PHP_7_0_AVAILABLE_LIBS[@]}")
            ;;
            7.1-fpm)
                PHP_BASE_LIBS=("${PHP_7_1_fpm_BASE_LIBS[@]}")
                PHP_AVAILABLE_LIBS=("${PHP_7_1_AVAILABLE_LIBS[@]}")
            ;;
            7.1.17-fpm)
                PHP_BASE_LIBS=("${PHP_7_1_17_fpm_BASE_LIBS[@]}")
                PHP_AVAILABLE_LIBS=("${PHP_7_1_AVAILABLE_LIBS[@]}")
            ;;
            7.1.26-fpm)
                PHP_BASE_LIBS=("${PHP_7_1_26_fpm_BASE_LIBS[@]}")
                PHP_AVAILABLE_LIBS=("${PHP_7_1_AVAILABLE_LIBS[@]}")
            ;;
            7.2-fpm)
                PHP_BASE_LIBS=("${PHP_7_2_fpm_BASE_LIBS[@]}")
                PHP_AVAILABLE_LIBS=("${PHP_7_2_AVAILABLE_LIBS[@]}")
            ;;
            7.2.24-fpm)
                PHP_BASE_LIBS=("${PHP_7_2_24_fpm_BASE_LIBS[@]}")
                PHP_AVAILABLE_LIBS=("${PHP_7_2_AVAILABLE_LIBS[@]}")
            ;;
            7.3-fpm)
                PHP_BASE_LIBS=("${PHP_7_3_fpm_BASE_LIBS[@]}")
                PHP_AVAILABLE_LIBS=("${PHP_7_3_AVAILABLE_LIBS[@]}")
            ;;
            7.4-fpm)
                PHP_BASE_LIBS=("${PHP_7_4_fpm_BASE_LIBS[@]}")
                PHP_AVAILABLE_LIBS=("${PHP_7_4_AVAILABLE_LIBS[@]}")
            ;;
            *)
                warp_message_warn "Can not install modules in your PHP Image version."
                warp_message_warn "Please report it to maintainers."
                GETOUT_F=true
            ;;
        esac

        # Cleaning PHP_EXTRA_LIBS array:
        if [[ ! $GETOUT_F ]]; then
            PHP_EXTRA_LIBS=$(warp_question_ask "Which ones? (separate each one with commas and no spaces): ")
            PHP_EXTRA_LIBS=($(echo $PHP_EXTRA_LIBS | tr "," "\n"))
            # Check if already exists and if could be installed:
            for (( extra_libs_p = 0 ; extra_libs_p < ${#PHP_EXTRA_LIBS[@]} ; extra_libs_p++ )); do
                HOP_AVAIL_LIBS_F=0
                for (( inst_libs_p = 0 ; inst_libs_p < ${#PHP_BASE_LIBS[@]} ; inst_libs_p++ )); do
                    if [[ ${PHP_EXTRA_LIBS[$extra_libs_p]} == ${PHP_BASE_LIBS[inst_libs_p]} ]]; then
                        warp_message_warn "${PHP_EXTRA_LIBS[$extra_libs_p]} is already installed"
                        HOP_AVAIL_LIBS_F=1
                        break
                    fi
                done
                if [[ $HOP_AVAIL_LIBS_F -eq 0 ]]; then
                    for (( avail_libs_p = 0 ; avail_libs_p < ${#PHP_AVAILABLE_LIBS[@]} ; avail_libs_p++ )); do
                        if [[ ${PHP_EXTRA_LIBS[$extra_libs_p]} == ${PHP_AVAILABLE_LIBS[avail_libs_p]} ]]; then
                            PHP_EXTRA_LIBS_OK+=(${PHP_EXTRA_LIBS[$extra_libs_p]})
                            break
                        fi
                        if [[ $avail_libs_p -eq $((${#PHP_AVAILABLE_LIBS[@]} - 1 )) ]]; then
                            warp_message_warn "${PHP_EXTRA_LIBS[$extra_libs_p]} is not available"
                            break
                        fi
                    done
                fi
            done
        fi
    fi

    # Clean aux vars:
    unset HOP_AVAIL_LIBS_F
    unset GETOUT_F
    unset PHP_EXTRA_LIBS

    cat $PROJECTPATH/.warp/setup/php/tpl/php.yml >> $DOCKERCOMPOSEFILESAMPLE

    echo ""  >> $ENVIRONMENTVARIABLESFILESAMPLE
    echo "# Config PHP" >> $ENVIRONMENTVARIABLESFILESAMPLE
    echo "PHP_VERSION=$php_version" >> $ENVIRONMENTVARIABLESFILESAMPLE
    echo "WARP_HOST_THREADS_RESERVE=${WARP_HOST_THREADS_RESERVE_DEFAULT:-1}" >> $ENVIRONMENTVARIABLESFILESAMPLE

    echo ""  >> $ENVIRONMENTVARIABLESFILESAMPLE
    echo "# Config xdebug by Console"  >> $ENVIRONMENTVARIABLESFILESAMPLE
    echo "XDEBUG_CONFIG=remote_host=172.17.0.1" >> $ENVIRONMENTVARIABLESFILESAMPLE
    echo "PHP_IDE_CONFIG=serverName=docker" >> $ENVIRONMENTVARIABLESFILESAMPLE
    echo ""  >> $ENVIRONMENTVARIABLESFILESAMPLE

    echo "# PHP Extra Modules" >> $ENVIRONMENTVARIABLESFILESAMPLE
    echo "PHP_EXTRA_LIBS=(${PHP_EXTRA_LIBS_OK[@]})" >> $ENVIRONMENTVARIABLESFILESAMPLE
    echo "" >> $ENVIRONMENTVARIABLESFILESAMPLE

    mkdir -p $PROJECTPATH/.warp/docker/volumes/php-fpm/logs 2> /dev/null
    # Create logs file
    [ ! -f $PROJECTPATH/.warp/docker/volumes/php-fpm/logs/access.log ] && touch $PROJECTPATH/.warp/docker/volumes/php-fpm/logs/access.log  2> /dev/null
    [ ! -f $PROJECTPATH/.warp/docker/volumes/php-fpm/logs/fpm-error.log ] && touch $PROJECTPATH/.warp/docker/volumes/php-fpm/logs/fpm-error.log 2> /dev/null
    [ ! -f $PROJECTPATH/.warp/docker/volumes/php-fpm/logs/fpm-php.www.log ] && touch $PROJECTPATH/.warp/docker/volumes/php-fpm/logs/fpm-php.www.log 2> /dev/null
    # chmod -R 775 $PROJECTPATH/.warp/docker/volumes/php-fpm 2> /dev/null
        
    mkdir -p $PROJECTPATH/.warp/docker/volumes/supervisor/logs 2> /dev/null
    [ ! -f $PROJECTPATH/.warp/docker/volumes/supervisor/logs/supervisord.log ] && touch $PROJECTPATH/.warp/docker/volumes/supervisor/logs/supervisord.log 2> /dev/null
    chmod 777 $PROJECTPATH/.warp/docker/volumes/supervisor/logs/supervisord.log 2> /dev/null

    cp -R $PROJECTPATH/.warp/setup/php/config/php $PROJECTPATH/.warp/docker/config/php
    cp -R $PROJECTPATH/.warp/setup/php/config/crontab $PROJECTPATH/.warp/docker/config/crontab
    cp -R $PROJECTPATH/.warp/setup/php/config/supervisor $PROJECTPATH/.warp/docker/config/supervisor

    # helper create .sample files
    . "$WARPFOLDER/setup/php/php-helper.sh"
fi; 
