#!/bin/bash

main () {
    # PROJECTPATH contains the full
    # directory path of the project itself
    PROJECTPATH=$(pwd)

    # SCRIPTNAME contains the name
    # of the current script (e.g. "server")
    SCRIPTNAME="bin/$(basename "$0")"
    ORIGINAL_COMMAND="$1"

    # Check availability of docker
    hash docker 2>/dev/null || { echo >&2 "warp framework requires \"docker\""; exit 1; }

    # Check availability of docker-compose
    hash docker-compose 2>/dev/null || { echo >&2 "warp framework requires \"docker-compose\""; exit 1; }

    # Check availability of ed
    hash ed 2>/dev/null || { echo >&2 "warp framework requires \"ed command\". On debian install it running \"sudo apt-get install ed\""; exit 1; }

    # Check availability of tr
    hash tr 2>/dev/null || { echo >&2 "warp framework requires \"tr command\". On debian install it running \"sudo apt-get install tr\""; exit 1; }

    [[ $(pwd) =~ [[:space:]]+ ]] && { echo "this folder contains spaces, warp framework requires a folder without spaces"; exit 1; }

    if [ -d "$PROJECTPATH/.warp/lib" ]; then
        include_warp_framework
    fi;

    if [ -d "$PROJECTPATH/.warp/lib" ]; then
        # Check minimum versions
        warp_check_docker_version
    fi;

    # check if binary was updated
    warp_check_binary_was_updated

    # Run update check at command end, so output remains visible.
    if [ -d "$PROJECTPATH/.warp/lib" ]; then
        trap 'warp_post_command_hook "$ORIGINAL_COMMAND"' EXIT
    fi

    case "$1" in
        init)
        shift 1
        setup_main "$@"
        ;;

        db|mysql)
        shift 1
        db_main "$@"
        ;;

        postgres)
        shift 1
        postgres_main "$@"
        ;;

        php)
        shift 1
        php_main "$@"
        ;;

        start)
        start_main "$@"
        ;;

        fix)
        fix_main "$@"
        ;;

        xdebug)
        shift 1
        xdebug_main "$@"
        ;;

        volume)
        shift 1
        volume_main "$@"
        ;;

        ioncube)
        shift 1
        ioncube_main "$@"
        ;;

        restart)
        restart_main "$@"
        ;;

        stop)
        stop_main "$@"
        ;;

        ps)
        ps_main "$@"
        ;;

        info)
        shift 1
        warp_info "$@"
        ;;

        composer)
        composer_main "$@"
        ;;

        magento)
        magento_main "$@"
        ;;

        ece-tools|ece-patches)
        magento_main "$@"
        ;;

        oro)
        oro_main "$@"
        ;;

        crontab)
        crontab_main "$@"
        ;;

        npm)
        npm_main "$@"
        ;;

        grunt)
        grunt_main "$@"
        ;;

        hyva)
        shift 1
        hyva_main "$@"
        ;;

        deploy)
        shift 1
        deploy_main "$@"
        ;;

        telemetry)
        shift 1
        telemetry_main "$@"
        ;;

        logs)
        logs_main "$@"
        ;;

        docker)
        docker_main "$@"
        ;;

        build)
        build_main "$@"
        ;;

        search|elasticsearch|opensearch)
        shift 1
        search_main "$@"
        ;;

        varnish)
        shift 1
        varnish_main "$@"
        ;;

        cache|redis|valkey)
        shift 1
        cache_main "$@"
        ;;

        sync)
        shift 1
        sync_main "$@"
        ;;

        rsync)
        shift 1
        rsync_main "$@"
        ;;

        rabbit)
        shift 1
        rabbit_main "$@"
        ;;

        selenium)
        shift 1
        selenium_main "$@"
        ;;

        mailhog)
        shift 1
        mailhog_main "$@"
        ;;

        sandbox | sb)
        shift 1
        setup_sandbox_main "$@"
        ;;

        reset)
        reset_main "$@"
        ;;

        update)
        shift 1
        warp_update "$@"
        ;;

        nginx)
        shift
        webserver_main "$@"
        ;;

        *)
        help
        ;;
    esac

    exit 0
}

include_warp_framework() {
    # INCLUDE VARIABLES
    . "$PROJECTPATH/.warp/variables.sh"
    # INCLUDE WARP FRAMEWORK
    . "$PROJECTPATH/.warp/includes.sh"
}

setup_main() {
    if [ "$1" = "-h" ] || [ "$1" = "--help" ] ; then
        setup_help_usage
        exit 0;
    elif [ "$1" = "-n" ] || [ "$1" = "--no-interaction" ] ; then
        if [ ! -d "$PROJECTPATH/.warp/setup" ]; then
            warp_setup --no-interaction
            exit 0;
        fi;

        init_main init --no-interaction        
        exit 1
    elif [ "$1" = "-mg" ] || [ "$1" = "--mode-gandalf" ] ; then
        if [ ! -d "$PROJECTPATH/.warp/setup" ]; then
            warp_setup --mode-gandalf "$@"
            exit 0;
        fi;

        init_main init --mode-gandalf "$@"
        exit 0;
    else
        if [ ! -d "$PROJECTPATH/.warp/setup" ]; then
            warp_setup install
            exit 0;
        fi;

        init_main init
    fi
}

setup_sandbox_main() {
    if [ "$1" = "-h" ] || [ "$1" = "--help" ] && [ ! -d "$PROJECTPATH/.warp/setup" ] ; then
        setup_help_usage
        exit 0;
    else
        if [ ! -d "$PROJECTPATH/.warp/setup" ]; then
            warp_setup sandbox
            exit 0;
        fi;

        sandbox_main "$@"
    fi
}

setup_help_usage() {
    if [ -d "$PROJECTPATH/.warp/lib" ]; then
        init_help_usage
        exit 0;
    else

        echo "  if you run for the first time, the installation of the framework begins"
        echo "  After the initial installation, a guided menu with options to create services"
        echo "  The following services can be configured:"
        echo "  1) Nginx Web Server"
        echo "  2) PHP service"
        echo "  3) MySQL service"
        echo "  4) Elasticsearch service"
        echo "  5) Redis service for cache, session, fpc"
        echo "  6) Rabbit service"
        echo "  7) Mailhog Server SMTP"
        echo "  8) Varnish service"
        echo "  9) PostgreSQL service"
        echo "  "
        echo "  If the program detects a previous configuration, it shows a shorter menu of options, to configure:"
        echo "  1) Work with one or more projects in parallel"
        echo "  2) Configure service ports"
        echo "  "
        echo "  Please run ./warp init"

        exit 0;
    fi
}

help() {
    if [ -d "$PROJECTPATH/.warp/bin" ]; then
        warp_banner

        . "$PROJECTPATH/.warp/bin/help.sh"

        help_main

        for filename in $PROJECTPATH/.warp/bin/*_help.sh; do
            . "$filename"
            "$(basename "$filename" .sh)" # execute default function
        done

        help_usage
    else
        warp_message_not_install_yet
        exit 0;
    fi;
}

warp_should_skip_update_check() {
    case "$1" in
        mysql|db|start|stop)
            return 0
        ;;
        *)
            return 1
        ;;
    esac
}

warp_pending_update_file() {
    echo "$PROJECTPATH/var/warp-update/.pending-update"
}

warp_pending_update_ensure() {
    mkdir -p "$PROJECTPATH/var/warp-update" 2>/dev/null
    [ -f "$(warp_pending_update_file)" ] || : > "$(warp_pending_update_file)"
}

warp_pending_update_write() {
    warp_pending_update_ensure
    cat > "$(warp_pending_update_file)"
}

warp_pending_update_box_border() {
    printf '+%58s+\n' '' | tr ' ' '-'
}

warp_pending_update_box_line() {
    # 60 columns total: "| " + 56 chars + " |"
    printf '| %-56.56s |\n' "$1"
}

warp_pending_update_clear() {
    warp_pending_update_ensure
    : > "$(warp_pending_update_file)"
}

warp_pending_update_show() {
    warp_pending_update_ensure
    pending_file="$(warp_pending_update_file)"
    [ -s "$pending_file" ] || return
    echo ""
    cat "$pending_file"
    echo ""
}

warp_date_plus_days_yyyymmdd() {
    days_to_add="$1"
    case "$(uname -s)" in
        Darwin)
            date -v +"${days_to_add}"d +%Y%m%d
        ;;
        Linux)
            date -d "+${days_to_add} days" +%Y%m%d
        ;;
        *)
            date +%Y%m%d
        ;;
    esac
}

warp_post_command_hook() {
    _cmd="$1"

    # keep stdout clean for these commands (e.g. mysql dump/pipe usage)
    if warp_should_skip_update_check "$_cmd"; then
        return
    fi

    # check version if needed and persist pending status
    if [[ ! -z "$CHECK_UPDATE_FILE" ]] && [[ ! -z "$CHECK_FREQUENCY_DAYS" ]]; then
        _today=$(date +%Y%m%d)
        _next_check=0
        [ -f "$CHECK_UPDATE_FILE" ] && _next_check=$(cat "$CHECK_UPDATE_FILE")

        if [[ "$_today" -ge "$_next_check" ]]; then
            if warp_check_latest_version; then
                warp_date_plus_days_yyyymmdd "$CHECK_FREQUENCY_DAYS" > "$CHECK_UPDATE_FILE" 2>/dev/null
            else
                # If remote check fails, retry next day.
                warp_date_plus_days_yyyymmdd "1" > "$CHECK_UPDATE_FILE" 2>/dev/null
            fi
        fi
    fi

    # show pending/error box at command end
    warp_pending_update_show
}

warp_update_version_to_int() {
    echo "$1" | tr -d '.'
}

warp_update_tmp_clean() {
    _tmp_dir="$PROJECTPATH/var/warp-update"
    [ -d "$_tmp_dir" ] || return
    find "$_tmp_dir" -mindepth 1 ! -name ".pending-update" -exec rm -rf {} + 2>/dev/null
}

warp_checksum_file_sha256() {
    file_path="$1"

    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$file_path" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$file_path" | awk '{print $1}'
    elif command -v openssl >/dev/null 2>&1; then
        openssl dgst -sha256 "$file_path" | awk '{print $NF}'
    else
        return 1
    fi
}

warp_fetch_latest_version() {
    warp_remote_base_url="https://raw.githubusercontent.com/magtools/phoenix-launch-silo/refs/heads/master/dist"
    _fetch_output=$(curl --silent --show-error --fail --location "${warp_remote_base_url}/version.md" 2>&1)
    _fetch_status=$?

    if [ $_fetch_status -ne 0 ]; then
        WARP_LAST_CHECK_ERROR="$_fetch_output"
        return 1
    fi

    echo "$_fetch_output" | tr -d '\r\n'
}

warp_check_latest_version() {
    if [ ! -f "$PROJECTPATH/.warp/lib/version.sh" ]; then
        return
    fi

    . "$PROJECTPATH/.warp/lib/version.sh"

    if [ -z "$WARP_VERSION" ]; then
        return
    fi

    WARP_LAST_CHECK_ERROR=""
    WARP_VERSION_LATEST=$(warp_fetch_latest_version)
    if [ $? -ne 0 ] || [ -z "$WARP_VERSION_LATEST" ]; then
        {
            warp_pending_update_box_border
            warp_pending_update_box_line "WARP UPDATE CHECK ERROR"
            warp_pending_update_box_line "Ultima version estable: No se pudo leer"
            warp_pending_update_box_line "el origen remoto (GitHub/raw)."
            warp_pending_update_box_line "Detalle: ${WARP_LAST_CHECK_ERROR:-error desconocido}"
            warp_pending_update_box_line "Reintento automatico: 1 dia"
            warp_pending_update_box_border
        } | warp_pending_update_write
        return 1
    fi

    WARP_VERSION_LOCAL_INT=$(warp_update_version_to_int "$WARP_VERSION")
    WARP_VERSION_LATEST_INT=$(warp_update_version_to_int "$WARP_VERSION_LATEST")

    if [[ "$WARP_VERSION_LOCAL_INT" =~ ^[0-9]+$ ]] && [[ "$WARP_VERSION_LATEST_INT" =~ ^[0-9]+$ ]]; then
        if [ "$WARP_VERSION_LOCAL_INT" -lt "$WARP_VERSION_LATEST_INT" ]; then
            {
                warp_pending_update_box_border
                warp_pending_update_box_line "WARP UPDATE PENDIENTE"
                warp_pending_update_box_line "Buscando actualizaciones..."
                warp_pending_update_box_line "Ultima version estable: $WARP_VERSION_LATEST"
                warp_pending_update_box_line "Estado: desactualizado"
                warp_pending_update_box_line "Ejecutar: ./warp update"
                warp_pending_update_box_border
            } | warp_pending_update_write
        else
            warp_pending_update_clear
        fi
    else
        {
            warp_pending_update_box_border
            warp_pending_update_box_line "WARP UPDATE CHECK ERROR"
            warp_pending_update_box_line "Version local/remota con formato invalido."
            warp_pending_update_box_line "Local: $WARP_VERSION"
            warp_pending_update_box_line "Remota: $WARP_VERSION_LATEST"
            warp_pending_update_box_line "Reintento automatico: 1 dia"
            warp_pending_update_box_border
        } | warp_pending_update_write
        return 1
    fi

    return 0
}

warp_message_not_install_yet() {
    echo "WARP-ENGINE has not been installed yet."
    echo "Please run ./warp init or ./warp init --help"
}

warp_update() {
    WARP_REMOTE_BASE_URL="https://raw.githubusercontent.com/magtools/phoenix-launch-silo/refs/heads/master/dist"
    WARP_TMP_DIR="$PROJECTPATH/var/warp-update"
    WARP_TMP_EXTRACT_DIR="$WARP_TMP_DIR/extracted"
    WARP_TMP_WARP="$WARP_TMP_DIR/warp"
    WARP_TMP_VERSION="$WARP_TMP_DIR/version.md"
    WARP_TMP_SHA256="$WARP_TMP_DIR/sha256sum.md"
    WARP_TARGET_FILE="$PROJECTPATH/warp"

    if [ "$1" = "-f" ] || [ "$1" = "--force" ] ; then
        WARP_FORCE_UPDATE=1
    else
        WARP_FORCE_UPDATE=0
    fi;

    if [ ! -d "$PROJECTPATH/.warp/lib" ]; then
        warp_message_not_install_yet
        exit 0;
    fi;

    if [ "$1" = "-h" ] || [ "$1" = "--help" ] ; then
        . "$PROJECTPATH/.warp/bin/update_help.sh"
        update_help_usage
        exit 0;
    fi

    if [ "$1" = "--images" ] ; then
        echo "checking if there are images available to update"
        docker-compose -f "$DOCKERCOMPOSEFILE" pull
        exit 0;
    fi

    if [ "$1" = "self" ] ; then
        warp_message_info "Buscando actualizaciones..."
        warp_message_info "Self update mode: aplicando payload de ./warp actual"
        warp_pending_update_ensure
        warp_update_tmp_clean
        mkdir -p "$WARP_TMP_EXTRACT_DIR" || { warp_message_error "unable to create $WARP_TMP_EXTRACT_DIR"; exit 1; }

        [ ! -f "$WARP_TARGET_FILE" ] && warp_message_error "file not found: ./warp" && exit 1

        ARCHIVE=$(awk '/^__ARCHIVE__/ {print NR + 1; exit 0; }' "$WARP_TARGET_FILE")
        [ -z "$ARCHIVE" ] && warp_message_error "invalid current warp payload" && exit 1

        tail -n+"${ARCHIVE}" "$WARP_TARGET_FILE" | tar xpJ -C "$WARP_TMP_EXTRACT_DIR" || { warp_message_error "unable to extract current payload"; exit 1; }
        [ ! -d "$WARP_TMP_EXTRACT_DIR/.warp" ] && warp_message_error "current payload does not contain .warp" && exit 1

        warp_message_info "Aplicando cambios"
        # Update .warp without touching .warp/docker/config
        mkdir -p "$PROJECTPATH/.warp" 2>/dev/null
        tar -C "$WARP_TMP_EXTRACT_DIR/.warp" --exclude='./docker/config' --exclude='./docker/config/*' -cf - . | tar -C "$PROJECTPATH/.warp" -xf - || { warp_message_error "unable to update .warp"; exit 1; }

        chmod 755 "$WARP_TARGET_FILE" || { warp_message_error "unable to set executable permissions on warp"; exit 1; }
        warp_pending_update_clear
        warp_update_tmp_clean

        warp_message_info2 "warp self update applied successfully"
        exit 0
    fi

    warp_message_info "Buscando actualizaciones..."
    warp_pending_update_ensure
    warp_update_tmp_clean
    mkdir -p "$WARP_TMP_EXTRACT_DIR" || { warp_message_error "unable to create $WARP_TMP_EXTRACT_DIR"; exit 1; }

    curl --silent --show-error --fail --location "${WARP_REMOTE_BASE_URL}/version.md" -o "$WARP_TMP_VERSION" || { warp_message_error "unable to download version.md"; exit 1; }
    WARP_VERSION_LATEST=$(tr -d '\r\n' < "$WARP_TMP_VERSION")

    if [ -z "$WARP_VERSION_LATEST" ]; then
        warp_message_error "remote version is empty"
        exit 1
    fi

    warp_message_info "Ultima version estable: $WARP_VERSION_LATEST"
    . "$PROJECTPATH/.warp/lib/version.sh"
    WARP_VERSION_LOCAL_INT=$(warp_update_version_to_int "$WARP_VERSION")
    WARP_VERSION_LATEST_INT=$(warp_update_version_to_int "$WARP_VERSION_LATEST")

    if [[ ! "$WARP_VERSION_LOCAL_INT" =~ ^[0-9]+$ ]] || [[ ! "$WARP_VERSION_LATEST_INT" =~ ^[0-9]+$ ]]; then
        warp_message_error "invalid version format (local: $WARP_VERSION, remote: $WARP_VERSION_LATEST)"
        exit 1
    fi

    if [ "$WARP_FORCE_UPDATE" -ne 1 ] && [ "$WARP_VERSION_LOCAL_INT" -ge "$WARP_VERSION_LATEST_INT" ]; then
        warp_message_info "Estado: actualizado"
        warp_message_info2 "warp is up to date ($WARP_VERSION)"
        warp_pending_update_clear
        warp_update_tmp_clean
        exit 0
    fi

    warp_message_warn "Estado: Actualizando a ultima version..."
    curl --silent --show-error --fail --location "${WARP_REMOTE_BASE_URL}/sha256sum.md" -o "$WARP_TMP_SHA256" || { warp_message_error "unable to download sha256sum.md"; exit 1; }
    curl --silent --show-error --fail --location "${WARP_REMOTE_BASE_URL}/warp" -o "$WARP_TMP_WARP" || { warp_message_error "unable to download warp"; exit 1; }

    warp_message_info "Chequeando suma de comprobacion"
    WARP_EXPECTED_SHA256=$(awk 'NR==1 {print $1}' "$WARP_TMP_SHA256" | tr -d '\r\n')
    [ -z "$WARP_EXPECTED_SHA256" ] && warp_message_error "sha256sum.md is empty" && exit 1

    WARP_ACTUAL_SHA256=$(warp_checksum_file_sha256 "$WARP_TMP_WARP")
    [ -z "$WARP_ACTUAL_SHA256" ] && warp_message_error "unable to calculate SHA256 checksum" && exit 1

    if [ "$WARP_EXPECTED_SHA256" != "$WARP_ACTUAL_SHA256" ]; then
        warp_message_error "checksum mismatch for downloaded warp"
        exit 1
    fi

    ARCHIVE=$(awk '/^__ARCHIVE__/ {print NR + 1; exit 0; }' "$WARP_TMP_WARP")
    [ -z "$ARCHIVE" ] && warp_message_error "invalid downloaded warp payload" && exit 1

    tail -n+"${ARCHIVE}" "$WARP_TMP_WARP" | tar xpJ -C "$WARP_TMP_EXTRACT_DIR" || { warp_message_error "unable to extract downloaded payload"; exit 1; }
    [ ! -d "$WARP_TMP_EXTRACT_DIR/.warp" ] && warp_message_error "downloaded payload does not contain .warp" && exit 1

    warp_message_info "Aplicando cambios"
    # Update .warp without touching .warp/docker/config
    mkdir -p "$PROJECTPATH/.warp" 2>/dev/null
    tar -C "$WARP_TMP_EXTRACT_DIR/.warp" --exclude='./docker/config' --exclude='./docker/config/*' -cf - . | tar -C "$PROJECTPATH/.warp" -xf - || { warp_message_error "unable to update .warp"; exit 1; }

    cp "$WARP_TMP_WARP" "$WARP_TARGET_FILE" || { warp_message_error "unable to update warp binary"; exit 1; }
    chmod 755 "$WARP_TARGET_FILE" || { warp_message_error "unable to set executable permissions on warp"; exit 1; }
    warp_pending_update_clear
    warp_update_tmp_clean

    warp_message_info2 "warp updated successfully to $WARP_VERSION_LATEST"
    warp_message_warn "run ./warp to use the new binary"
}

usage() {
    #######################################
    # Print the usage information for the
    # server control script
    # Globals:
    #   SCRIPTNAME
    # Arguments:
    #   None
    # Returns:
    #   None
    #######################################
  echo "Utility for controlling dockerized Web projects\n"
  echo "Usage:\n\n  $SCRIPTNAME <action> [options...] <arguments...>"
  echo ""
}

function warp_info() {
    # IMPORT HELP
    . "$PROJECTPATH/.warp/bin/info_help.sh"

    if [ "$1" = "-h" ] || [ "$1" = "--help" ] ; then  
        info_help_usage
        exit 0;
    fi;    

    if ! warp_check_env_file ; then
        warp_message_error "file not found $(basename $ENVIRONMENTVARIABLESFILE)"
        exit 1;
    fi; 

    if [ "$1" = "--ip" ] ; then
        if [ "$(warp_check_is_running)" = false ]; then
            warp_message_error "The containers are not running"
            warp_message_error "please, first run warp start"

            exit 1;
        fi

        containers_running=$(docker-compose -f "$DOCKERCOMPOSEFILE" ps -q)
        [ -z "$containers_running" ] && exit 0
        docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}   {{.Name}}' $containers_running | sed 's/ \// /'
    else
        mysql_main info   
        postgres_main info   
        webserver_main info   
        php_main info   
        elasticsearch_main info   
        varnish_main info   
        redis_main info   
        rabbit_main info   
        mailhog_main info   
    fi;
}

function warp_setup() {
    # Create destination folder
    DESTINATION="."
    #mkdir -p ${DESTINATION}

    OPTION=$1

    # Find __ARCHIVE__ maker, read archive content and decompress it
    ARCHIVE=$(awk '/^__ARCHIVE__/ {print NR + 1; exit 0; }' "${0}")

    tail -n+"${ARCHIVE}" "${0}" | tar xpJ -C "$DESTINATION"

    if [ "$OPTION" = "sandbox" ]
    then
        if [ -d "$PROJECTPATH/.warp/lib" ] && [ -d "$PROJECTPATH/.warp/bin" ] ; then    
            echo "Installing Warp mode Sandbox, wait a few moments"
            sleep 1
            echo "Successful installation!, starting configurations.."
            sleep 1
            # Init Instalation
            include_warp_framework
            sandbox_main init
        fi
    fi

    if [ "$OPTION" = "--no-interaction" ]
    then
        if [ -d "$PROJECTPATH/.warp/lib" ] && [ -d "$PROJECTPATH/.warp/bin" ] ; then    
            echo "Installing Warp mode --no-interaction, wait a few moments"
            sleep 1
            echo "Successful installation!, starting without wizard.."
            sleep 1
            # Init Instalation
            include_warp_framework
            init_main init --no-interaction
        fi
    fi

    if [ "$OPTION" = "--mode-gandalf" ]
    then
        if [ -d "$PROJECTPATH/.warp/lib" ] && [ -d "$PROJECTPATH/.warp/bin" ] ; then    
            echo "Installing Warp --mode-gandalf, wait a few moments"
            sleep 1
            echo "Successful installation!, starting without wizard.."
            sleep 1
            # Init Instalation
            include_warp_framework
            init_main init --mode-gandalf "$@"
        fi
    fi

    if [ "$OPTION" = "--force" ]
    then
        echo "Force updating Warp, wait a few moments"
        sleep 1
        echo "Successful update!"
        sleep 1
        # Init Instalation
        include_warp_framework
        # save new version to ENVIRONMENTVARIABLESFILESAMPLE
        warp_env_change_version_sample_file
    fi

    if [ "$OPTION" = "--self-update" ]
    then
        echo "Self update Warp, wait a few moments"
        sleep 1
        echo "Successful update!"
        sleep 1
        # Init Instalation
        include_warp_framework
        # save new version to ENVIRONMENTVARIABLESFILESAMPLE
        warp_env_change_version_sample_file
        # load banner
        warp_banner        
        exit 0;
    fi

    if [ "$OPTION" = "install" ]
    then
        if [ -d "$PROJECTPATH/.warp/lib" ] && [ -d "$PROJECTPATH/.warp/bin" ] ; then    
            echo "Installing Warp, wait a few moments"
            sleep 1
            echo "Successful installation!, starting configurations.."
            sleep 1
            # Init Instalation
            include_warp_framework
            init_main init
        fi
    elif [ "$OPTION" = "update" ]
    then
        while : ; do
            respuesta=$( warp_question_ask_default "Are you sure to update Warp Framework? $(warp_message_info [Y/n]) " "Y" )
            if [ "$respuesta" = "Y" ] || [ "$respuesta" = "y" ] || [ "$respuesta" = "N" ] || [ "$respuesta" = "n" ] ; then
                break
            else
                warp_message_warn "Incorrect answer, you must select between two options: $(warp_message_info [Y/n]) "
            fi
        done

        if [ "$respuesta" = "Y" ] || [ "$respuesta" = "y" ]
        then
            echo "Updating Warp, wait a few moments"
            sleep 1
            echo "Successful update!"
            sleep 1
            # Init Instalation
            include_warp_framework
            # save new version to ENVIRONMENTVARIABLESFILESAMPLE
            warp_env_change_version_sample_file
            warp_banner
        fi
    fi
}

function warp_check_binary_was_updated() {
    if [ -f "$ENVIRONMENTVARIABLESFILE" ] && [ -f "$ENVIRONMENTVARIABLESFILESAMPLE" ] && [ -d "$PROJECTPATH/.warp/lib" ]
    then
        WARP_ENV_VERSION=$(grep "^WARP_VERSION" "$ENVIRONMENTVARIABLESFILESAMPLE" | cut -d '=' -f2)
        _WARP_ENV_VERSION=$(echo "$WARP_ENV_VERSION" | tr -d ".")

        . "$PROJECTPATH/.warp/lib/version.sh"
        _WARP_VERSION=$(echo "$WARP_VERSION" | tr -d ".")

        if [ ! -z "$WARP_ENV_VERSION" ] && [[ "$_WARP_ENV_VERSION" =~ ^[0-9]+$ ]] && [[ "$_WARP_VERSION" =~ ^[0-9]+$ ]]
        then
            # .env.sample > version.sh and not equal
            if [ $_WARP_ENV_VERSION -gt $_WARP_VERSION ] && [ ! $_WARP_ENV_VERSION -eq $_WARP_VERSION ]
            then
                # different version binary and current, only notify.
                # Never trigger legacy setup-based update paths automatically.
                warp_message_warn "binary and current version are different"
                warp_message_warn "run ./warp update to apply the safe update process"
            fi
        fi
    fi
}

main "$@"

__ARCHIVE__
