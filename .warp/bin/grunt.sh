#!/bin/bash

    # IMPORT HELP

    . "$PROJECTPATH/.warp/bin/grunt_help.sh"

function grunt_command() 
{

    if [ "$1" = "-h" ] || [ "$1" = "--help" ]
    then
        grunt_help_usage 
        exit 1
    fi;

    if [ "$(grunt_runtime_is_available)" = false ]; then
        warp_message_error "The containers are not running"
        if [ -n "$WARP_GRUNT_PHP_CONTAINER" ]; then
            warp_message_error "container not running: $WARP_GRUNT_PHP_CONTAINER"
        else
            warp_message_error "please, first run warp start"
        fi

        exit 1;
    fi

    # Build shell-safe argv string for execution inside container shell.
    _grunt_args=""
    for _arg in "$@"; do
        _escaped=$(printf '%q' "$_arg")
        _grunt_args="${_grunt_args} ${_escaped}"
    done

    # Prefer local CLI via npx when global grunt is not available.
    grunt_php_exec "0" "command -v grunt >/dev/null 2>&1 && grunt${_grunt_args} || npx grunt${_grunt_args}"
}

grunt_runtime_is_available() {
    if [ -n "$WARP_GRUNT_PHP_CONTAINER" ]; then
        _running=$(docker inspect --format '{{.State.Running}}' "$WARP_GRUNT_PHP_CONTAINER" 2>/dev/null)
        [ "$_running" = "true" ] && echo true || echo false
        return 0
    fi

    [ "$(warp_check_is_running)" = true ] && echo true || echo false
}

grunt_php_exec() {
    _as_root="$1"
    _cmd="$2"

    if [ -n "$WARP_GRUNT_PHP_CONTAINER" ]; then
        if [ "$_as_root" = "1" ]; then
            docker exec -i -u root "$WARP_GRUNT_PHP_CONTAINER" bash -lc "$_cmd"
        else
            docker exec -i "$WARP_GRUNT_PHP_CONTAINER" bash -lc "$_cmd"
        fi
        return $?
    fi

    if [ "$_as_root" = "1" ]; then
        docker-compose -f "$DOCKERCOMPOSEFILE" exec -T -u root php bash -lc "$_cmd"
    else
        docker-compose -f "$DOCKERCOMPOSEFILE" exec php bash -lc "$_cmd"
    fi
}

grunt_setup_copy_samples() {
    grunt_php_exec "0" '
        set -e
        [ -f package.json ] || [ ! -f package.json.sample ] || cp package.json.sample package.json
        [ -f Gruntfile.js ] || [ ! -f Gruntfile.js.sample ] || cp Gruntfile.js.sample Gruntfile.js
        [ -f grunt-config.json ] || [ ! -f grunt-config.json.sample ] || cp grunt-config.json.sample grunt-config.json
    '
}

grunt_setup_install_deps() {
    grunt_php_exec "1" "npm install"
}

grunt_setup_install_cli_if_missing() {
    grunt_php_exec "1" '
        set -e
        if [ -x node_modules/.bin/grunt ]; then
            exit 0
        fi
        npm install --no-save grunt-cli
    '
}

grunt_setup_fix_permissions() {
    grunt_php_exec "1" '
        chown -R www-data:www-data node_modules >/dev/null 2>&1 || true
        [ -f package-lock.json ] && chown www-data:www-data package-lock.json >/dev/null 2>&1 || true
    '
}

grunt_setup() {
    if [ "$1" = "-h" ] || [ "$1" = "--help" ]
    then
        grunt_setup_help_usage
        return 0
    fi

    if [ "$(grunt_runtime_is_available)" = false ]; then
        warp_message_error "The containers are not running"
        if [ -n "$WARP_GRUNT_PHP_CONTAINER" ]; then
            warp_message_error "container not running: $WARP_GRUNT_PHP_CONTAINER"
        else
            warp_message_error "please, first run warp start"
        fi
        return 1
    fi

    warp_message ""
    warp_message_info "Grunt setup"
    warp_message "* prepare sample files (if missing)"
    grunt_setup_copy_samples || return 1

    warp_message "* npm install (root inside php container)"
    grunt_setup_install_deps || return 1

    warp_message "* ensure grunt-cli (local)"
    grunt_setup_install_cli_if_missing || return 1

    warp_message "* normalize ownership to www-data"
    grunt_setup_fix_permissions || return 1

    warp_message_ok "grunt setup completed"
    warp_message_info "run: warp grunt exec"
    warp_message_info "run: warp grunt less"
}

function grunt_main()
{
    if [ "$1" = "grunt" ]; then
        shift 1
    fi

    case "$1" in
        setup)
            shift 1
            grunt_setup "$@"
        ;;

        -h|--help)
            grunt_help_usage
        ;;

        "")
            grunt_help_usage
        ;;

        *)
            grunt_command "$@"
        ;;
    esac
}
