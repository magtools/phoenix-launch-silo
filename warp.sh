#!/bin/bash

WARP_BINARY_VERSION="__BUILD_VERSION__"

main () {
    # PROJECTPATH contains the full
    # directory path of the project itself
    PROJECTPATH=$(pwd)

    # SCRIPTNAME contains the name
    # of the current script (e.g. "server")
    SCRIPTNAME="bin/$(basename "$0")"
    ORIGINAL_COMMAND="$1"
    BOOT_RUNTIME_MODE=$(warp_runtime_mode_resolve_boot "$ORIGINAL_COMMAND")

    # Check docker tooling only when runtime mode requires docker.
    if [ "$BOOT_RUNTIME_MODE" = "docker" ]; then
        hash docker 2>/dev/null || { echo >&2 "warp framework requires \"docker\""; exit 1; }
        warp_compose_bootstrap
    fi

    # Check availability of ed
    hash ed 2>/dev/null || { echo >&2 "warp framework requires \"ed command\". On debian install it running \"sudo apt-get install ed\""; exit 1; }

    # Check availability of tr
    hash tr 2>/dev/null || { echo >&2 "warp framework requires \"tr command\". On debian install it running \"sudo apt-get install tr\""; exit 1; }

    [[ $(pwd) =~ [[:space:]]+ ]] && { echo "this folder contains spaces, warp framework requires a folder without spaces"; exit 1; }

    if [ -d "$PROJECTPATH/.warp/lib" ]; then
        include_warp_framework
    fi;

    if [ -d "$PROJECTPATH/.warp/lib" ] && [ "$BOOT_RUNTIME_MODE" = "docker" ]; then
        # Check minimum versions
        warp_check_docker_version
    fi;

    # prepare binary/framework sync notice for command end
    warp_check_binary_was_updated

    # Run update check at command end, so output remains visible.
    if [ -d "$PROJECTPATH/.warp/lib" ]; then
        trap 'warp_post_command_hook "$ORIGINAL_COMMAND"' EXIT
    fi

    case "$1" in
        init)
        shift 1
        warp_run_loaded_command setup_main "init" "$@"
        ;;

        db|mysql)
        shift 1
        warp_run_loaded_command db_main "db" "$@"
        ;;

        postgres)
        shift 1
        warp_run_loaded_command postgres_main "postgres" "$@"
        ;;

        php)
        shift 1
        warp_run_loaded_command php_main "php" "$@"
        ;;

        phpini)
        shift 1
        warp_run_loaded_command phpini_main "phpini" "$@"
        ;;

        opcache)
        shift 1
        warp_run_loaded_command opcache_main "opcache" "$@"
        ;;

        profiler)
        shift 1
        warp_run_loaded_command profiler_main "profiler" "$@"
        ;;

        agents)
        shift 1
        warp_run_loaded_command agents_main "agents" "$@"
        ;;

        start)
        warp_run_loaded_command start_main "start" "$@"
        ;;

        fix)
        warp_run_loaded_command fix_main "fix" "$@"
        ;;

        xdebug)
        shift 1
        warp_run_loaded_command xdebug_main "xdebug" "$@"
        ;;

        volume)
        shift 1
        warp_run_loaded_command volume_main "volume" "$@"
        ;;

        ioncube)
        shift 1
        warp_run_loaded_command ioncube_main "ioncube" "$@"
        ;;

        restart)
        warp_run_loaded_command restart_main "restart" "$@"
        ;;

        stop)
        warp_run_loaded_command stop_main "stop" "$@"
        ;;

        ps)
        warp_run_loaded_command ps_main "ps" "$@"
        ;;

        info)
        shift 1
        warp_run_loaded_command warp_info "info" "$@"
        ;;

        composer)
        warp_run_loaded_command composer_main "composer" "$@"
        ;;

        magento)
        warp_run_loaded_command magento_main "magento" "$@"
        ;;

        ece-tools|ece-patches)
        warp_run_loaded_command magento_main "$1" "$@"
        ;;

        oro)
        warp_run_loaded_command oro_main "oro" "$@"
        ;;

        crontab)
        warp_run_loaded_command crontab_main "crontab" "$@"
        ;;

        npm)
        warp_run_loaded_command npm_main "npm" "$@"
        ;;

        grunt)
        warp_run_loaded_command grunt_main "grunt" "$@"
        ;;

        hyva)
        shift 1
        warp_run_loaded_command hyva_main "hyva" "$@"
        ;;

        audit)
        shift 1
        warp_run_loaded_command audit_main "audit" "$@"
        exit $?
        ;;

        scan)
        shift 1
        warp_run_loaded_command scan_main "scan" "$@"
        exit $?
        ;;

        security)
        shift 1
        warp_run_loaded_command security_main "security" "$@"
        exit $?
        ;;

        deploy)
        shift 1
        warp_run_loaded_command deploy_main "deploy" "$@"
        ;;

        telemetry)
        shift 1
        warp_run_loaded_command telemetry_main "telemetry" "$@"
        ;;

        logs)
        warp_run_loaded_command logs_main "logs" "$@"
        ;;

        docker)
        warp_run_loaded_command docker_main "docker" "$@"
        ;;

        build)
        warp_run_loaded_command build_main "build" "$@"
        ;;

        search|elasticsearch|opensearch)
        shift 1
        warp_run_loaded_command search_main "$ORIGINAL_COMMAND" "$@"
        ;;

        varnish)
        shift 1
        warp_run_loaded_command varnish_main "varnish" "$@"
        ;;

        cache|redis|valkey)
        shift 1
        warp_run_loaded_command cache_main "$ORIGINAL_COMMAND" "$@"
        ;;

        sync)
        shift 1
        warp_run_loaded_command sync_main "sync" "$@"
        ;;

        rsync)
        shift 1
        warp_run_loaded_command rsync_main "rsync" "$@"
        ;;

        rabbit)
        shift 1
        warp_run_loaded_command rabbit_main "rabbit" "$@"
        ;;

        selenium)
        shift 1
        warp_run_loaded_command selenium_main "selenium" "$@"
        ;;

        mailhog)
        shift 1
        warp_run_loaded_command mailhog_main "mailhog" "$@"
        ;;

        sandbox | sb)
        shift 1
        warp_run_loaded_command setup_sandbox_main "$ORIGINAL_COMMAND" "$@"
        ;;

        reset)
        warp_run_loaded_command reset_main "reset" "$@"
        ;;

        update)
        shift 1
        warp_update "$@"
        ;;

        nginx)
        shift
        warp_run_loaded_command webserver_main "nginx" "$@"
        ;;

        *)
        help
        ;;
    esac

    exit 0
}

warp_run_loaded_command() {
    local _function_name="$1"
    local _command_name="$2"

    shift 2

    if ! declare -F "$_function_name" >/dev/null 2>&1; then
        warp_message_warn "command unavailable: $_command_name"
        warp_message_warn "the installed framework seems outdated"
        warp_message_warn "run $(warp_local_update_self_hint) update --self to align the installed framework with this executable"
        exit 1
    fi

    "$_function_name" "$@"
}

warp_compose_bootstrap() {
    if hash docker-compose 2>/dev/null; then
        if docker-compose version >/dev/null 2>&1; then
            export WARP_COMPOSE_BACKEND="legacy"
            return 0
        fi
    fi

    if docker compose version >/dev/null 2>&1; then
        _shim_dir="$PROJECTPATH/var/warp-bin"
        _shim_file="$_shim_dir/docker-compose"

        mkdir -p "$_shim_dir" 2>/dev/null || {
            echo >&2 "warp framework could not prepare compose shim at $_shim_dir"
            exit 1
        }

        if [ ! -x "$_shim_file" ]; then
            printf '#!/bin/sh\nexec docker compose "$@"\n' > "$_shim_file" || {
                echo >&2 "warp framework could not write compose shim at $_shim_file"
                exit 1
            }

            chmod +x "$_shim_file" 2>/dev/null || {
                echo >&2 "warp framework could not chmod compose shim at $_shim_file"
                exit 1
            }
        fi

        export PATH="$_shim_dir:$PATH"
        hash -r 2>/dev/null || true
        hash docker-compose 2>/dev/null || {
            echo >&2 "warp framework requires \"docker-compose\" or \"docker compose\" plugin"
            exit 1
        }

        export WARP_COMPOSE_BACKEND="plugin-v2"
        return 0
    fi

    echo >&2 "warp framework requires \"docker-compose\" or \"docker compose\" plugin"
    exit 1
}

warp_runtime_mode_read_raw_from_env() {
    _env_file="$PROJECTPATH/.env"
    [ -f "$_env_file" ] || { echo ""; return 0; }
    _mode=$(grep -m1 '^WARP_RUNTIME_MODE=' "$_env_file" | cut -d '=' -f2- | tr '[:upper:]' '[:lower:]')
    case "$_mode" in
        host|docker|auto) echo "$_mode" ;;
        *) echo "" ;;
    esac
}

warp_command_supports_host_runtime() {
    local _cmd="$1"
    case "$_cmd" in
        ""|-h|--help|help|init|db|mysql|cache|redis|valkey|search|elasticsearch|opensearch|php|phpini|opcache|xdebug|profiler|agents|magento|ece-tools|ece-patches|telemetry|info|composer|audit|scan|security)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

warp_runtime_mode_resolve_boot() {
    local _cmd="$1"
    local _mode

    _mode=$(warp_runtime_mode_read_raw_from_env)
    case "$_mode" in
        host|docker)
            echo "$_mode"
            return 0
            ;;
    esac

    if [ "$_cmd" = "scan" ]; then
        echo "host"
        return 0
    fi

    if [ -f "$PROJECTPATH/docker-compose-warp.yml" ]; then
        echo "docker"
        return 0
    fi

    if warp_command_supports_host_runtime "$_cmd"; then
        echo "host"
    else
        echo "docker"
    fi
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
    if [ "${WARP_SKIP_UPDATE_CHECK:-0}" = "1" ]; then
        return 0
    fi

    case "$1" in
        mysql|db|start|stop|deploy)
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

    warp_binary_sync_notice_show

    # show pending/error box at command end
    warp_pending_update_show
}

warp_update_version_to_int() {
    echo "$1" | tr -d '.'
}

warp_file_size_bytes() {
    local _path="$1"
    local _size=""

    [ -e "$_path" ] || return 1

    _size=$(stat -c '%s' "$_path" 2>/dev/null)
    if [ -z "$_size" ]; then
        _size=$(stat -f '%z' "$_path" 2>/dev/null)
    fi

    [ -n "$_size" ] || return 1
    echo "$_size"
}

warp_abs_path() {
    local _path="$1"
    [ -n "$_path" ] || return 1
    (
        cd "$(dirname "$_path")" 2>/dev/null || exit 1
        printf '%s/%s\n' "$(pwd)" "$(basename "$_path")"
    )
}

warp_binary_version_from_file() {
    local _path="$1"
    local _version=""

    [ -f "$_path" ] || return 1

    _version=$(grep '^WARP_BINARY_VERSION=' "$_path" 2>/dev/null | head -n1 | cut -d '=' -f2 | tr -d '"')
    if [[ "$_version" =~ ^[0-9][0-9.]*$ ]]; then
        echo "$_version"
        return 0
    fi

    return 1
}

warp_delegate_wrapper_template() {
    echo "$PROJECTPATH/.warp/setup/bin/warp-wrapper.sh"
}

warp_is_delegate_wrapper_file() {
    local _path="$1"

    [ -f "$_path" ] || return 1

    grep -Eq '(^|[[:space:]])(\.\/)?warp([[:space:]]|"$@")' "$_path" 2>/dev/null || \
    grep -Eq '(^|[[:space:]])bash[[:space:]]+\./warp([[:space:]]|"$@")' "$_path" 2>/dev/null || \
    grep -Eq '(^|[[:space:]])bash[[:space:]]+\./warp\.sh([[:space:]]|"$@")' "$_path" 2>/dev/null || \
    grep -Eq '(^|[[:space:]])exec[[:space:]]+\./warp([[:space:]]|"$@")' "$_path" 2>/dev/null || \
    grep -Eq '(^|[[:space:]])exec[[:space:]]+bash[[:space:]]+\./warp\.sh([[:space:]]|"$@")' "$_path" 2>/dev/null
}

warp_wrapper_install_command() {
    local _target="$1"
    local _template=""

    _template=$(warp_delegate_wrapper_template)
    printf 'sudo cp "%s" "%s" && sudo chmod 755 "%s"' "$_template" "$_target" "$_target"
}

warp_wrapper_overwrite_system_lines() {
    local _target="$1"
    local _mode="${2:-plain}"
    local _command=""

    _command=$(warp_wrapper_install_command "$_target")

    if [ "$_mode" = "warn" ]; then
        warp_message_warn "overwrite system warp with the project wrapper:"
        warp_message_warn "$_command"
        warp_message_warn "source wrapper: .warp/setup/bin/warp-wrapper.sh"
        warp_message_warn "after this, ${_target} delegates to ./warp or ./warp.sh in the current project"
        return 0
    fi

    warp_message "  overwrite system warp with the project wrapper:"
    warp_message "    $_command"
    warp_message "  source wrapper: .warp/setup/bin/warp-wrapper.sh"
    warp_message "  effect: ${_target} delegates to ./warp or ./warp.sh in the current project"
}

warp_global_binary_paths() {
    type -aP warp 2>/dev/null | awk '!seen[$0]++'
}

warp_global_binary_diff_collect() {
    local _project_warp="$PROJECTPATH/warp"
    local _project_abs=""
    local _project_version=""
    local _project_version_int=""
    local _project_size=""
    local _path=""
    local _path_abs=""
    local _path_version=""
    local _path_version_int=""
    local _path_size=""
    local _cmp_reason=""

    WARP_GLOBAL_BINARY_DIFF_NOTICE=""
    WARP_GLOBAL_BINARY_DIFF_FOUND=0
    WARP_GLOBAL_BINARY_PATHS=""
    WARP_GLOBAL_BINARY_WRAPPER_PATHS=""
    WARP_GLOBAL_BINARY_HAS_WRAPPER=0

    [ -f "$_project_warp" ] || return 0

    _project_abs=$(warp_abs_path "$_project_warp")
    _project_version=$(warp_binary_version_from_file "$_project_warp")
    [ -n "$_project_version" ] && _project_version_int=$(warp_update_version_to_int "$_project_version")
    _project_size=$(warp_file_size_bytes "$_project_warp")

    while IFS= read -r _path; do
        [ -n "$_path" ] || continue
        _path_abs=$(warp_abs_path "$_path")
        [ -n "$_path_abs" ] || continue
        [ "$_path_abs" = "$_project_abs" ] && continue

        if warp_is_delegate_wrapper_file "$_path_abs"; then
            WARP_GLOBAL_BINARY_HAS_WRAPPER=1
            if [ -z "$WARP_GLOBAL_BINARY_WRAPPER_PATHS" ]; then
                WARP_GLOBAL_BINARY_WRAPPER_PATHS="$_path_abs"
            else
                WARP_GLOBAL_BINARY_WRAPPER_PATHS="${WARP_GLOBAL_BINARY_WRAPPER_PATHS}"$'\n'"$_path_abs"
            fi
            continue
        fi

        if [ -z "$WARP_GLOBAL_BINARY_PATHS" ]; then
            WARP_GLOBAL_BINARY_PATHS="$_path_abs"
        else
            WARP_GLOBAL_BINARY_PATHS="${WARP_GLOBAL_BINARY_PATHS}"$'\n'"$_path_abs"
        fi

        _cmp_reason=""
        _path_version=$(warp_binary_version_from_file "$_path_abs")
        [ -n "$_path_version" ] && _path_version_int=$(warp_update_version_to_int "$_path_version") || _path_version_int=""

        if [[ "$_project_version_int" =~ ^[0-9]+$ ]] && [[ "$_path_version_int" =~ ^[0-9]+$ ]]; then
            if [ "$_path_version_int" -lt "$_project_version_int" ]; then
                _cmp_reason="version $_path_version < $_project_version"
            fi
        else
            _path_size=$(warp_file_size_bytes "$_path_abs")
            if [[ "$_project_size" =~ ^[0-9]+$ ]] && [[ "$_path_size" =~ ^[0-9]+$ ]] && [ "$_path_size" -lt "$_project_size" ]; then
                _cmp_reason="size ${_path_size}B < ${_project_size}B"
            fi
        fi

        if [ -n "$_cmp_reason" ]; then
            WARP_GLOBAL_BINARY_DIFF_FOUND=1
            if [ -z "$WARP_GLOBAL_BINARY_DIFF_NOTICE" ]; then
                WARP_GLOBAL_BINARY_DIFF_NOTICE="$_path_abs|$_cmp_reason"
            else
                WARP_GLOBAL_BINARY_DIFF_NOTICE="${WARP_GLOBAL_BINARY_DIFF_NOTICE}"$'\n'"$_path_abs|$_cmp_reason"
            fi
        fi
    done < <(warp_global_binary_paths)

    export WARP_GLOBAL_BINARY_DIFF_NOTICE
    export WARP_GLOBAL_BINARY_DIFF_FOUND
    export WARP_GLOBAL_BINARY_PATHS
    export WARP_GLOBAL_BINARY_WRAPPER_PATHS
    export WARP_GLOBAL_BINARY_HAS_WRAPPER
}

warp_global_binary_diff_doctor_lines() {
    local _line=""
    local _path=""
    local _reason=""

    warp_global_binary_diff_collect

    if [ "${WARP_GLOBAL_BINARY_HAS_WRAPPER:-0}" = "1" ]; then
        _line=$(printf '%s\n' "$WARP_GLOBAL_BINARY_WRAPPER_PATHS" | head -n1)
        warp_message "* PATH warp wrapper: $(warp_message_ok [ok]) ${_line}"
        return 0
    fi

    if [ -z "$WARP_GLOBAL_BINARY_PATHS" ]; then
        warp_message "* PATH warp binary: $(warp_message_info "[not found]")"
        return 0
    fi

    if [ "${WARP_GLOBAL_BINARY_DIFF_FOUND:-0}" != "1" ]; then
        _line=$(printf '%s\n' "$WARP_GLOBAL_BINARY_PATHS" | head -n1)
        warp_message "* PATH warp binary: $(warp_message_ok [ok]) ${_line}"
        return 0
    fi

    while IFS='|' read -r _path _reason; do
        [ -n "$_path" ] || continue
        warp_message "* PATH warp binary differs from project: $(warp_message_warn "[warn]") ${_path} (${_reason})"
        warp_wrapper_overwrite_system_lines "$_path"
    done <<EOF
$WARP_GLOBAL_BINARY_DIFF_NOTICE
EOF
}

warp_global_binary_diff_notice_show() {
    local _path=""
    local _reason=""

    warp_global_binary_diff_collect
    [ "${WARP_GLOBAL_BINARY_DIFF_FOUND:-0}" = "1" ] || return 0
    [ "${WARP_GLOBAL_BINARY_HAS_WRAPPER:-0}" = "1" ] && return 0

    warp_message ""
    while IFS='|' read -r _path _reason; do
        [ -n "$_path" ] || continue
        warp_message_warn "system warp binary differs from project warp: ${_path} (${_reason})"
        warp_wrapper_overwrite_system_lines "$_path" "warn"
    done <<EOF
$WARP_GLOBAL_BINARY_DIFF_NOTICE
EOF
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

warp_update_ensure_php_optional_ini_files() {
    local _config_dir="$PROJECTPATH/.warp/docker/config/php"
    local _gitignore="$PROJECTPATH/.gitignore"
    local _line=""

    mkdir -p "$_config_dir" || {
        warp_message_error "unable to create PHP config directory: $_config_dir"
        return 1
    }

    for _line in \
        "$_config_dir/ext-xdebug.ini" \
        "$_config_dir/zz-warp-opcache.ini"
    do
        if [ -d "$_line" ]; then
            if rmdir "$_line" 2>/dev/null; then
                warp_message_warn "PHP optional ini path was a directory; recreated it as a file: $_line"
            else
                warp_message_error "PHP optional ini path is a non-empty directory: $_line"
                warp_message_warn "move or remove that directory, then rerun warp update"
                return 1
            fi
        fi

        [ -f "$_line" ] || touch "$_line" || {
            warp_message_error "unable to create PHP optional ini file: $_line"
            return 1
        }
    done

    [ -f "$_gitignore" ] || touch "$_gitignore" || {
        warp_message_error "unable to create .gitignore"
        return 1
    }

    for _line in \
        "/.warp/docker/config/php/ext-xdebug.ini" \
        "/.warp/docker/config/php/zz-warp-opcache.ini"
    do
        grep -qxF "$_line" "$_gitignore" 2>/dev/null || echo "$_line" >> "$_gitignore" || {
            warp_message_error "unable to update .gitignore with $_line"
            return 1
        }
    done
}

warp_fetch_latest_version() {
    warp_remote_base_url="https://raw.githubusercontent.com/magtools/phoenix-launch-silo/refs/heads/master/dist"
    _fetch_output=$(curl --silent --show-error --fail --location --connect-timeout 3 --max-time 3 "${warp_remote_base_url}/version.md" 2>&1)
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
            warp_pending_update_box_line "Latest stable version: unavailable"
            warp_pending_update_box_line "from the remote source (GitHub/raw)."
            warp_pending_update_box_line "Details: ${WARP_LAST_CHECK_ERROR:-unknown error}"
            warp_pending_update_box_line "Automatic retry: 1 day"
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
                warp_pending_update_box_line "WARP UPDATE PENDING"
                warp_pending_update_box_line "Checking for updates..."
                warp_pending_update_box_line "Latest stable version: $WARP_VERSION_LATEST"
                warp_pending_update_box_line "Status: outdated"
                warp_pending_update_box_line "Run: ./warp update"
                warp_pending_update_box_border
            } | warp_pending_update_write
        else
            warp_pending_update_clear
        fi
    else
        {
            warp_pending_update_box_border
            warp_pending_update_box_line "WARP UPDATE CHECK ERROR"
            warp_pending_update_box_line "Local/remote version has an invalid format."
            warp_pending_update_box_line "Local: $WARP_VERSION"
            warp_pending_update_box_line "Remote: $WARP_VERSION_LATEST"
            warp_pending_update_box_line "Automatic retry: 1 day"
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

    if [ "$1" = "self" ] || [ "$1" = "--self" ] ; then
        warp_message_info "Checking for updates..."
        warp_message_info "Self update mode: applying payload from the current ./warp"
        warp_message_info2 "No remote version will be downloaded in self mode"
        warp_pending_update_ensure
        warp_update_tmp_clean
        mkdir -p "$WARP_TMP_EXTRACT_DIR" || { warp_message_error "unable to create $WARP_TMP_EXTRACT_DIR"; exit 1; }

        [ ! -f "$WARP_TARGET_FILE" ] && warp_message_error "file not found: ./warp" && exit 1

        ARCHIVE=$(awk '/^__ARCHIVE__/ {print NR + 1; exit 0; }' "$WARP_TARGET_FILE")
        [ -z "$ARCHIVE" ] && warp_message_error "invalid current warp payload" && exit 1

        tail -n+"${ARCHIVE}" "$WARP_TARGET_FILE" | tar xpJ -C "$WARP_TMP_EXTRACT_DIR" || { warp_message_error "unable to extract current payload"; exit 1; }
        [ ! -d "$WARP_TMP_EXTRACT_DIR/.warp" ] && warp_message_error "current payload does not contain .warp" && exit 1

        warp_message_info "Applying changes"
        # Update .warp without touching .warp/docker/config
        mkdir -p "$PROJECTPATH/.warp" 2>/dev/null
        tar -C "$WARP_TMP_EXTRACT_DIR/.warp" --exclude='./docker/config' --exclude='./docker/config/*' -cf - . | tar -C "$PROJECTPATH/.warp" -xf - || { warp_message_error "unable to update .warp"; exit 1; }

        chmod 755 "$WARP_TARGET_FILE" || { warp_message_error "unable to set executable permissions on warp"; exit 1; }
        WARP_BINARY_SYNC_NOTICE=""
        warp_pending_update_clear
        warp_update_ensure_php_optional_ini_files || exit 1
        warp_update_tmp_clean

        warp_message_info2 "warp self update applied successfully"
        warp_global_binary_diff_notice_show
        exit 0
    fi

    warp_message_info "Checking for updates..."
    warp_pending_update_ensure
    warp_update_tmp_clean
    mkdir -p "$WARP_TMP_EXTRACT_DIR" || { warp_message_error "unable to create $WARP_TMP_EXTRACT_DIR"; exit 1; }

    curl --silent --show-error --fail --location "${WARP_REMOTE_BASE_URL}/version.md" -o "$WARP_TMP_VERSION" || { warp_message_error "unable to download version.md"; exit 1; }
    WARP_VERSION_LATEST=$(tr -d '\r\n' < "$WARP_TMP_VERSION")

    if [ -z "$WARP_VERSION_LATEST" ]; then
        warp_message_error "remote version is empty"
        exit 1
    fi

    warp_message_info "Latest stable version: $WARP_VERSION_LATEST"
    . "$PROJECTPATH/.warp/lib/version.sh"
    WARP_VERSION_LOCAL_INT=$(warp_update_version_to_int "$WARP_VERSION")
    WARP_VERSION_LATEST_INT=$(warp_update_version_to_int "$WARP_VERSION_LATEST")

    if [[ ! "$WARP_VERSION_LOCAL_INT" =~ ^[0-9]+$ ]] || [[ ! "$WARP_VERSION_LATEST_INT" =~ ^[0-9]+$ ]]; then
        warp_message_error "invalid version format (local: $WARP_VERSION, remote: $WARP_VERSION_LATEST)"
        exit 1
    fi

    if [ "$WARP_FORCE_UPDATE" -ne 1 ] && [ "$WARP_VERSION_LOCAL_INT" -ge "$WARP_VERSION_LATEST_INT" ]; then
        warp_message_info "Status: up to date"
        warp_message_info2 "warp is up to date ($WARP_VERSION)"
        warp_pending_update_clear
        warp_update_ensure_php_optional_ini_files || exit 1
        warp_update_tmp_clean
        exit 0
    fi

    warp_message_warn "Status: updating to the latest version..."
    curl --silent --show-error --fail --location "${WARP_REMOTE_BASE_URL}/sha256sum.md" -o "$WARP_TMP_SHA256" || { warp_message_error "unable to download sha256sum.md"; exit 1; }
    curl --silent --show-error --fail --location "${WARP_REMOTE_BASE_URL}/warp" -o "$WARP_TMP_WARP" || { warp_message_error "unable to download warp"; exit 1; }

    warp_message_info "Checking checksum"
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

    warp_message_info "Applying changes"
    # Update .warp without touching .warp/docker/config
    mkdir -p "$PROJECTPATH/.warp" 2>/dev/null
    tar -C "$WARP_TMP_EXTRACT_DIR/.warp" --exclude='./docker/config' --exclude='./docker/config/*' -cf - . | tar -C "$PROJECTPATH/.warp" -xf - || { warp_message_error "unable to update .warp"; exit 1; }

    cp "$WARP_TMP_WARP" "$WARP_TARGET_FILE" || { warp_message_error "unable to update warp binary"; exit 1; }
    chmod 755 "$WARP_TARGET_FILE" || { warp_message_error "unable to set executable permissions on warp"; exit 1; }
    WARP_BINARY_SYNC_NOTICE=""
    warp_pending_update_clear
    warp_update_ensure_php_optional_ini_files || exit 1
    warp_update_tmp_clean

    warp_message_info2 "warp updated successfully to $WARP_VERSION_LATEST"
    warp_message_warn "run ./warp to use the new binary"
    warp_global_binary_diff_notice_show
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
    local _installed_version=""
    local _installed_version_int=""
    local _binary_version=""
    local _binary_version_int=""
    local _update_hint=""

    WARP_BINARY_SYNC_NOTICE=""

    [ -d "$PROJECTPATH/.warp/lib" ] || return 0
    [ -f "$PROJECTPATH/.warp/lib/version.sh" ] || return 0

    _binary_version=$(warp_binary_script_version)
    [ -n "$_binary_version" ] || return 0

    _installed_version=$(warp_installed_framework_version)
    [ -n "$_installed_version" ] || return 0

    _binary_version_int=$(warp_update_version_to_int "$_binary_version")
    _installed_version_int=$(warp_update_version_to_int "$_installed_version")

    if [[ ! "$_binary_version_int" =~ ^[0-9]+$ ]] || [[ ! "$_installed_version_int" =~ ^[0-9]+$ ]]; then
        return 0
    fi

    [ "$_binary_version_int" -eq "$_installed_version_int" ] && return 0

    _update_hint=$(warp_local_update_self_hint)

    WARP_BINARY_SYNC_NOTICE="warp binary and installed framework are out of sync
binary version: $_binary_version
installed framework version: $_installed_version"
    if [ "$_binary_version_int" -gt "$_installed_version_int" ]; then
        WARP_BINARY_SYNC_NOTICE="${WARP_BINARY_SYNC_NOTICE}
the local executable is newer than .warp"
    else
        WARP_BINARY_SYNC_NOTICE="${WARP_BINARY_SYNC_NOTICE}
the installed .warp is newer than the local executable"
    fi
    WARP_BINARY_SYNC_NOTICE="${WARP_BINARY_SYNC_NOTICE}
run ${_update_hint} update --self to align the installed framework with this executable"
}

function warp_binary_script_version() {
    if [[ "$WARP_BINARY_VERSION" =~ ^[0-9][0-9.]*$ ]]; then
        echo "$WARP_BINARY_VERSION"
    fi
}

function warp_installed_framework_version() {
    local _installed_version=""

    [ -f "$PROJECTPATH/.warp/lib/version.sh" ] || return 0
    _installed_version=$(grep '^WARP_VERSION=' "$PROJECTPATH/.warp/lib/version.sh" 2>/dev/null | head -n1 | cut -d '=' -f2 | tr -d '"')
    echo "$_installed_version"
}

function warp_local_update_self_hint() {
    if [ -x "$PROJECTPATH/warp" ]; then
        echo "./warp"
    elif [ -f "$PROJECTPATH/warp.sh" ]; then
        echo "bash ./warp.sh"
    else
        echo "warp"
    fi
}

function warp_binary_sync_notice_show() {
    local _line=""

    [ -n "$WARP_BINARY_SYNC_NOTICE" ] || return 0

    printf "\n"
    while IFS= read -r _line; do
        [ -n "$_line" ] || continue
        warp_message_warn "$_line"
    done <<EOF
$WARP_BINARY_SYNC_NOTICE
EOF
}

main "$@"

__ARCHIVE__
