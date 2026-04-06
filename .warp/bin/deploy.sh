#!/bin/bash

. "$PROJECTPATH/.warp/bin/deploy_help.sh"

DEPLOY_FILE="$PROJECTPATH/.deploy"
DEPLOY_LOG_DIR="$PROJECTPATH/var/log/warp-deploy"
DEPLOY_DRY_RUN=0
DEPLOY_ASSUME_YES=0
DEPLOY_BORDER_WIDTH=80
DEPLOY_COLOR=1

deploy_warp_exec() {
    if [ -x "$PROJECTPATH/warp" ]; then
        echo "$PROJECTPATH/warp"
        return 0
    fi
    if [ -x "$PROJECTPATH/warp.sh" ]; then
        echo "$PROJECTPATH/warp.sh"
        return 0
    fi
    echo "warp"
}

deploy_bool() {
    case "$(echo "$1" | tr '[:upper:]' '[:lower:]')" in
        1|y|yes|true|on) echo "1" ;;
        *) echo "0" ;;
    esac
}

deploy_threads_detect() {
    warp_host_worker_threads_default
}

deploy_has_grunt_cfg() {
    [ -f "$PROJECTPATH/app/design/themes.js" ]
}

deploy_has_hyva_cfg() {
    [ -f "$PROJECTPATH/app/design/hyva-themes.json" ] || [ -f "$PROJECTPATH/app/design/hyva-themes.js" ]
}

deploy_detect_env() {
    _env_file="$PROJECTPATH/app/etc/env.php"
    if [ -f "$_env_file" ]; then
        if grep -Eq "['\"]MAGE_MODE['\"][[:space:]]*=>[[:space:]]*['\"]production['\"]" "$_env_file"; then
            echo "prod"
            return 0
        fi
        if grep -Eq "['\"]MAGE_MODE['\"][[:space:]]*=>[[:space:]]*['\"]developer['\"]" "$_env_file"; then
            echo "local"
            return 0
        fi
    fi

    _is_dev=$(warp_question_ask_default "Es entorno de desarrollo? $(warp_message_info [y/N]) " "N")
    if [ "$(deploy_bool "$_is_dev")" = "1" ]; then
        echo "local"
    else
        echo "prod"
    fi
}

deploy_ensure_gitignore() {
    _gitignore="$PROJECTPATH/.gitignore"
    [ -f "$_gitignore" ] || touch "$_gitignore"

    grep -Eq '^/\.deploy$' "$_gitignore" 2>/dev/null
    if [ $? -ne 0 ]; then
        {
            echo ""
            echo "# WARP DEPLOY"
            echo "/.deploy"
        } >> "$_gitignore"
    fi
}

deploy_ensure_optional_defaults() {
    [ -f "$DEPLOY_FILE" ] || return 0

    grep -Eq '^FRONT_STATIC_THEMES=' "$DEPLOY_FILE" 2>/dev/null
    if [ $? -ne 0 ]; then
        {
            echo ""
            echo 'FRONT_STATIC_THEMES='
        } >> "$DEPLOY_FILE"
    fi
}

deploy_set_write_file() {
    _env="$1"
    _threads=$(deploy_threads_detect)
    _warp_exec=$(deploy_warp_exec)

    if [ "$_env" = "local" ]; then
        _run_grunt=0
        _run_hyva=0
        deploy_has_grunt_cfg && _run_grunt=1
        deploy_has_hyva_cfg && _run_hyva=1

        cat > "$DEPLOY_FILE" <<EOF
DEPLOY_SCHEMA_VERSION=1
ENV=local
AUTO_START=1
USE_MAINTENANCE=0
COMPOSER_FLAGS=
RUN_SETUP_UPGRADE=1
RUN_DI_COMPILE=1
RUN_REINDEX=0
RUN_CACHE_FLUSH=1
RUN_GRUNT=$_run_grunt
RUN_HYVA=$_run_hyva
HYVA_PREPARE=1
HYVA_BUILD=1
RUN_SEARCH_FLUSH=0
SEARCH_FLUSH_CMD="$_warp_exec search flush"
CONFIRM_PROD=1
ALLOW_DIR_PERMS_FIX=0
EOF
    else
        warp_message "I18N: ingresa locales separados por espacios. Presiona Enter para aceptar el valor por defecto."
        _admin_i18n=$(warp_question_ask_default "ADMIN_I18N default [en_US es_AR]: " "en_US es_AR")
        _front_i18n=$(warp_question_ask_default "FRONT_I18N default [es_AR en_US]: " "es_AR en_US")
        _run_hyva=0
        deploy_has_hyva_cfg && _run_hyva=1

        cat > "$DEPLOY_FILE" <<EOF
DEPLOY_SCHEMA_VERSION=1
ENV=prod
AUTO_START=1
USE_MAINTENANCE=1
COMPOSER_FLAGS=--no-dev
RUN_SETUP_UPGRADE=1
RUN_DI_COMPILE=1
RUN_REINDEX=1
RUN_CACHE_FLUSH=1
RUN_STATIC_ADMIN=1
RUN_STATIC_FRONT=1
ADMIN_I18N="$_admin_i18n"
FRONT_I18N="$_front_i18n"
FRONT_STATIC_THEMES=
THREADS=$_threads
STATIC_EXTRA_FLAGS="-f"
RUN_SEARCH_FLUSH=1
SEARCH_FLUSH_CMD="$_warp_exec search flush"
RUN_HYVA=$_run_hyva
HYVA_BUILD=1
CONFIRM_PROD=1
ALLOW_DIR_PERMS_FIX=0
EOF
    fi
}

deploy_front_static_theme_args() {
    local _themes_raw="${FRONT_STATIC_THEMES:-}"
    local _theme
    local _out=""

    [ -n "$_themes_raw" ] || return 0

    for _theme in $_themes_raw; do
        [ -n "$_theme" ] || continue
        _out="$_out $(printf "%q" "--theme") $(printf "%q" "$_theme")"
    done

    printf "%s" "$_out"
}

deploy_set_interactive() {
    warp_message ""
    warp_message_info "Configuring deploy settings (.deploy)"
    _env=$(deploy_detect_env)
    deploy_set_write_file "$_env"
    deploy_ensure_gitignore
    warp_message_ok "Created/updated .deploy (ENV=$_env)"
}

deploy_load_config() {
    if [ ! -f "$DEPLOY_FILE" ]; then
        deploy_set_interactive
    fi

    deploy_ensure_optional_defaults

    # shellcheck disable=SC1090
    . "$DEPLOY_FILE"
}

deploy_cmd_run() {
    _label="$1"
    shift
    # Deploy recipes are stored as shell snippets and executed via eval below.
    _cmd="$*"

    if [ "$DEPLOY_DRY_RUN" = "1" ]; then
        warp_message "  - $_label"
        return 0
    fi

    _border=$(printf '%*s' "$DEPLOY_BORDER_WIDTH" '' | tr ' ' '=')
    echo "$_border"
    echo "   $_label"
    echo "$_border"

    if [ "$DEPLOY_COLOR" = "1" ] && [ -t 1 ]; then
        FORCE_COLOR=1 CLICOLOR_FORCE=1 TERM="${TERM:-xterm-256color}" eval "$_cmd"
    else
        eval "$_cmd"
    fi
    _status=$?
    if [ $_status -ne 0 ]; then
        warp_message_error "failed step: $_label"
        exit $_status
    fi
}

deploy_doctor() {
    _ok=1
    _auto_start=$(deploy_bool "${AUTO_START:-1}")
    _run_grunt=$(deploy_bool "${RUN_GRUNT:-0}")
    _run_hyva=$(deploy_bool "${RUN_HYVA:-0}")

    warp_message ""
    warp_message_info "Deploy doctor"

    [ -f "$DOCKERCOMPOSEFILE" ] && warp_message "* docker-compose file: $(warp_message_ok [ok])" || { warp_message "* docker-compose file: $(warp_message_error [error])"; _ok=0; }
    [ -f "$ENVIRONMENTVARIABLESFILE" ] && warp_message "* .env file: $(warp_message_ok [ok])" || { warp_message "* .env file: $(warp_message_error [error])"; _ok=0; }
    hash docker >/dev/null 2>&1 && warp_message "* docker: $(warp_message_ok [ok])" || { warp_message "* docker: $(warp_message_error [error])"; _ok=0; }
    hash docker-compose >/dev/null 2>&1 && warp_message "* docker-compose: $(warp_message_ok [ok])" || { warp_message "* docker-compose: $(warp_message_error [error])"; _ok=0; }

    if [ "$(warp_check_is_running)" = true ] || [ "$_auto_start" = "1" ]; then
        warp_message "* runtime state: $(warp_message_ok [ok])"
    else
        warp_message "* runtime state: $(warp_message_error [error]) containers stopped and AUTO_START=0"
        _ok=0
    fi

    if [ "$_run_grunt" = "1" ]; then
        deploy_has_grunt_cfg && warp_message "* themes.js: $(warp_message_ok [ok])" || { warp_message "* themes.js: $(warp_message_error [error]) RUN_GRUNT=1"; _ok=0; }
    fi

    if [ "$_run_hyva" = "1" ]; then
        deploy_has_hyva_cfg && warp_message "* hyva config: $(warp_message_ok [ok])" || { warp_message "* hyva config: $(warp_message_error [error]) RUN_HYVA=1"; _ok=0; }
    fi

    if [ "${ENV:-}" = "prod" ]; then
        [[ "$THREADS" =~ ^[0-9]+$ ]] && [ "$THREADS" -ge 1 ] && warp_message "* THREADS: $(warp_message_ok [ok])" || { warp_message "* THREADS: $(warp_message_error [error])"; _ok=0; }
        [ -n "${ADMIN_I18N:-}" ] && warp_message "* ADMIN_I18N: $(warp_message_ok [ok])" || { warp_message "* ADMIN_I18N: $(warp_message_error [error])"; _ok=0; }
        [ -n "${FRONT_I18N:-}" ] && warp_message "* FRONT_I18N: $(warp_message_ok [ok])" || { warp_message "* FRONT_I18N: $(warp_message_error [error])"; _ok=0; }
        if [ -n "${FRONT_STATIC_THEMES:-}" ]; then
            warp_message "* FRONT_STATIC_THEMES: $(warp_message_ok [subset]) ${FRONT_STATIC_THEMES}"
        else
            warp_message "* FRONT_STATIC_THEMES: $(warp_message_info [all])"
        fi
    fi

    if [ $_ok -eq 1 ]; then
        warp_message_ok "doctor passed"
        return 0
    fi

    warp_message_error "doctor failed"
    return 1
}

deploy_show() {
    if [ ! -f "$DEPLOY_FILE" ]; then
        warp_message_warn ".deploy not found. Run: warp deploy set"
        return 1
    fi
    cat "$DEPLOY_FILE"
}

deploy_run_frontend_local() {
    _warp_exec=$(deploy_warp_exec)
    _run_grunt=$(deploy_bool "${RUN_GRUNT:-0}")
    _run_hyva=$(deploy_bool "${RUN_HYVA:-0}")
    _hyva_prepare=$(deploy_bool "${HYVA_PREPARE:-1}")
    _hyva_build=$(deploy_bool "${HYVA_BUILD:-1}")

    if [ "$_run_grunt" = "1" ] && deploy_has_grunt_cfg; then
        deploy_cmd_run "grunt exec" "$_warp_exec grunt exec"
        deploy_cmd_run "grunt less" "$_warp_exec grunt less"
    fi

    if [ "$_run_hyva" = "1" ] && deploy_has_hyva_cfg; then
        [ "$_hyva_prepare" = "1" ] && deploy_cmd_run "hyva prepare" "$_warp_exec hyva prepare"
        [ "$_hyva_build" = "1" ] && deploy_cmd_run "hyva build" "$_warp_exec hyva build"
    fi
}

deploy_run_frontend_prod() {
    _warp_exec=$(deploy_warp_exec)
    _run_hyva=$(deploy_bool "${RUN_HYVA:-0}")
    _hyva_build=$(deploy_bool "${HYVA_BUILD:-1}")
    _run_static_admin=$(deploy_bool "${RUN_STATIC_ADMIN:-1}")
    _run_static_front=$(deploy_bool "${RUN_STATIC_FRONT:-1}")
    _front_static_theme_args="$(deploy_front_static_theme_args)"

    if [ "$_run_hyva" = "1" ] && [ "$_hyva_build" = "1" ] && deploy_has_hyva_cfg; then
        deploy_cmd_run "hyva build" "$_warp_exec hyva build"
    fi

    if [ "$_run_static_admin" = "1" ]; then
        deploy_cmd_run "static content deploy (admin)" "$_warp_exec magento setup:static-content:deploy ${ADMIN_I18N:-en_US} -a adminhtml -j ${THREADS:-4} ${STATIC_EXTRA_FLAGS:--f}"
    fi

    if [ "$_run_static_front" = "1" ]; then
        deploy_cmd_run "static content deploy (frontend)" "$_warp_exec magento setup:static-content:deploy ${FRONT_I18N:-en_US} -a frontend -j ${THREADS:-4} ${STATIC_EXTRA_FLAGS:--f}${_front_static_theme_args}"
    fi
}

deploy_run_main() {
    # Accept run flags in both forms:
    # - warp deploy --dry-run run
    # - warp deploy run --dry-run
    while [ $# -gt 0 ]; do
        case "$1" in
            --dry-run)
                DEPLOY_DRY_RUN=1
            ;;
            --yes)
                DEPLOY_ASSUME_YES=1
            ;;
        esac
        shift
    done

    deploy_load_config

    # In dry-run mode print only the recipe (no execution, no doctor gates).
    if [ "$DEPLOY_DRY_RUN" = "1" ]; then
        _env="${ENV:-local}"
        _auto_start=$(deploy_bool "${AUTO_START:-1}")
        _use_maintenance=$(deploy_bool "${USE_MAINTENANCE:-0}")
        _run_setup_upgrade=$(deploy_bool "${RUN_SETUP_UPGRADE:-1}")
        _run_di_compile=$(deploy_bool "${RUN_DI_COMPILE:-1}")
        _run_reindex=$(deploy_bool "${RUN_REINDEX:-0}")
        _run_cache_flush=$(deploy_bool "${RUN_CACHE_FLUSH:-1}")
        _run_search_flush=$(deploy_bool "${RUN_SEARCH_FLUSH:-0}")
        _run_grunt=$(deploy_bool "${RUN_GRUNT:-0}")
        _run_hyva=$(deploy_bool "${RUN_HYVA:-0}")
        _hyva_prepare=$(deploy_bool "${HYVA_PREPARE:-1}")
        _hyva_build=$(deploy_bool "${HYVA_BUILD:-1}")
        _run_static_admin=$(deploy_bool "${RUN_STATIC_ADMIN:-1}")
        _run_static_front=$(deploy_bool "${RUN_STATIC_FRONT:-1}")

        warp_message ""
        warp_message_info "Deploy recipe (dry-run)"

        if [ "$_auto_start" = "1" ] && [ "$(warp_check_is_running)" = false ]; then
            deploy_cmd_run "start containers" ":"
        fi

        if [ "$_env" = "prod" ] && [ "$_use_maintenance" = "1" ]; then
            deploy_cmd_run "enable maintenance mode" ":"
        fi

        deploy_cmd_run "composer install" ":"
        [ "$_run_setup_upgrade" = "1" ] && deploy_cmd_run "setup:upgrade" ":"
        [ "$_run_di_compile" = "1" ] && deploy_cmd_run "setup:di:compile" ":"

        if [ "$_env" = "local" ]; then
            if [ "$_run_grunt" = "1" ] && deploy_has_grunt_cfg; then
                deploy_cmd_run "grunt exec" ":"
                deploy_cmd_run "grunt less" ":"
            fi
            if [ "$_run_hyva" = "1" ] && deploy_has_hyva_cfg; then
                [ "$_hyva_prepare" = "1" ] && deploy_cmd_run "hyva prepare" ":"
                [ "$_hyva_build" = "1" ] && deploy_cmd_run "hyva build" ":"
            fi
        else
            if [ "$_run_hyva" = "1" ] && [ "$_hyva_build" = "1" ] && deploy_has_hyva_cfg; then
                deploy_cmd_run "hyva build" ":"
            fi
            [ "$_run_static_admin" = "1" ] && deploy_cmd_run "static content deploy (admin)" ":"
            [ "$_run_static_front" = "1" ] && deploy_cmd_run "static content deploy (frontend)" ":"
        fi

        [ "$_run_search_flush" = "1" ] && deploy_cmd_run "search flush" ":"
        [ "$_run_reindex" = "1" ] && deploy_cmd_run "indexer:reindex" ":"
        [ "$_run_cache_flush" = "1" ] && deploy_cmd_run "cache:flush" ":"

        if [ "$_env" = "prod" ] && [ "$_use_maintenance" = "1" ]; then
            deploy_cmd_run "disable maintenance mode" ":"
        fi

        warp_message_ok "dry-run recipe completed"
        return 0
    fi

    if ! deploy_doctor; then
        exit 1
    fi

    _warp_exec=$(deploy_warp_exec)
    _env="${ENV:-local}"
    _auto_start=$(deploy_bool "${AUTO_START:-1}")
    _use_maintenance=$(deploy_bool "${USE_MAINTENANCE:-0}")
    _run_setup_upgrade=$(deploy_bool "${RUN_SETUP_UPGRADE:-1}")
    _run_di_compile=$(deploy_bool "${RUN_DI_COMPILE:-1}")
    _run_reindex=$(deploy_bool "${RUN_REINDEX:-0}")
    _run_cache_flush=$(deploy_bool "${RUN_CACHE_FLUSH:-1}")
    _run_search_flush=$(deploy_bool "${RUN_SEARCH_FLUSH:-0}")
    _confirm_prod=$(deploy_bool "${CONFIRM_PROD:-1}")
    _maintenance_enabled=0

    if [ "$_env" = "prod" ] && [ "$_confirm_prod" = "1" ] && [ "$DEPLOY_ASSUME_YES" != "1" ]; then
        _resp=$(warp_question_ask_default "Confirm deploy PROD? $(warp_message_info [y/N]) " "N")
        if [ "$(deploy_bool "$_resp")" != "1" ]; then
            warp_message_warn "deploy canceled"
            exit 1
        fi
    fi

    if [ "$_auto_start" = "1" ] && [ "$(warp_check_is_running)" = false ]; then
        deploy_cmd_run "start containers" "$_warp_exec start"
    fi

    if [ "$_env" = "prod" ] && [ "$_use_maintenance" = "1" ]; then
        deploy_cmd_run "enable maintenance mode" "$_warp_exec magento maintenance:enable --ansi"
        _maintenance_enabled=1
    fi

    _composer_flags="${COMPOSER_FLAGS:-}"
    deploy_cmd_run "composer install" "$_warp_exec composer install $_composer_flags --ansi"

    if [ "$_run_setup_upgrade" = "1" ]; then
        deploy_cmd_run "setup:upgrade" "$_warp_exec magento setup:upgrade --ansi"
    fi

    if [ "$_run_di_compile" = "1" ]; then
        deploy_cmd_run "setup:di:compile" "$_warp_exec magento setup:di:compile --ansi"
    fi

    if [ "$_env" = "local" ]; then
        deploy_run_frontend_local
    else
        deploy_run_frontend_prod
    fi

    if [ "$_run_search_flush" = "1" ]; then
        _search_cmd="${SEARCH_FLUSH_CMD:-$_warp_exec search flush}"
        deploy_cmd_run "search flush" "$_search_cmd"
    fi

    if [ "$_run_reindex" = "1" ]; then
        deploy_cmd_run "indexer:reindex" "$_warp_exec magento indexer:reindex --ansi"
    fi

    if [ "$_run_cache_flush" = "1" ]; then
        deploy_cmd_run "cache:flush" "$_warp_exec magento cache:flush --ansi"
    fi

    if [ "$_maintenance_enabled" = "1" ]; then
        deploy_cmd_run "disable maintenance mode" "$_warp_exec magento maintenance:disable --ansi"
    fi

    warp_message_ok "deploy finished"
}

deploy_static_main() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --dry-run)
                DEPLOY_DRY_RUN=1
            ;;
            --yes)
                DEPLOY_ASSUME_YES=1
            ;;
        esac
        shift
    done

    deploy_load_config

    _env="${ENV:-local}"
    _run_grunt=$(deploy_bool "${RUN_GRUNT:-0}")
    _run_hyva=$(deploy_bool "${RUN_HYVA:-0}")
    _hyva_prepare=$(deploy_bool "${HYVA_PREPARE:-1}")
    _hyva_build=$(deploy_bool "${HYVA_BUILD:-1}")
    _run_static_admin=$(deploy_bool "${RUN_STATIC_ADMIN:-1}")
    _run_static_front=$(deploy_bool "${RUN_STATIC_FRONT:-1}")

    if [ "$DEPLOY_DRY_RUN" = "1" ]; then
        warp_message ""
        warp_message_info "Deploy static recipe (dry-run)"

        if [ "$_env" = "local" ]; then
            if [ "$_run_grunt" = "1" ] && deploy_has_grunt_cfg; then
                deploy_cmd_run "grunt exec" ":"
                deploy_cmd_run "grunt less" ":"
            fi
            if [ "$_run_hyva" = "1" ] && deploy_has_hyva_cfg; then
                [ "$_hyva_prepare" = "1" ] && deploy_cmd_run "hyva prepare" ":"
                [ "$_hyva_build" = "1" ] && deploy_cmd_run "hyva build" ":"
            fi
        else
            if [ "$_run_hyva" = "1" ] && [ "$_hyva_build" = "1" ] && deploy_has_hyva_cfg; then
                deploy_cmd_run "hyva build" ":"
            fi
            [ "$_run_static_admin" = "1" ] && deploy_cmd_run "static content deploy (admin)" ":"
            [ "$_run_static_front" = "1" ] && deploy_cmd_run "static content deploy (frontend)" ":"
        fi

        warp_message_ok "dry-run static recipe completed"
        return 0
    fi

    if ! deploy_doctor; then
        exit 1
    fi

    if [ "$_env" = "local" ]; then
        deploy_run_frontend_local
    else
        deploy_run_frontend_prod
    fi

    warp_message_ok "deploy static finished"
}

deploy_parse_global_options() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --dry-run)
                DEPLOY_DRY_RUN=1
                shift
            ;;
            --yes)
                DEPLOY_ASSUME_YES=1
                shift
            ;;
            *)
                break
            ;;
        esac
    done
    echo "$@"
}

deploy_main() {
    _args=$(deploy_parse_global_options "$@")
    # shellcheck disable=SC2086
    set -- $_args

    case "$1" in
        run)
            shift
            deploy_run_main "$@"
        ;;
        static)
            shift
            deploy_static_main "$@"
        ;;
        "")
            deploy_help_usage
        ;;
        set)
            shift
            deploy_set_interactive
        ;;
        show)
            shift
            deploy_show
        ;;
        doctor)
            shift
            deploy_load_config
            deploy_doctor
        ;;
        -h|--help)
            deploy_help_usage
        ;;
        *)
            deploy_help_usage
            return 1
        ;;
    esac
}
