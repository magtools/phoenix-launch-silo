#!/bin/bash

. "$PROJECTPATH/.warp/bin/scan_help.sh"

SCAN_OUTPUT_DIR="$PROJECTPATH/var/static"
SCAN_RULESET_RUNTIME="$PROJECTPATH/.warp/docker/config/lint/TestPR.xml"
SCAN_RULESET_PROJECT="$PROJECTPATH/app/devops/TestPR.xml"
SCAN_RULESET_TEMPLATE="$PROJECTPATH/.warp/setup/init/config/lint/TestPR.xml"
SCAN_PHPSTAN_CONFIG="$PROJECTPATH/phpstan.neon.dist"
SCAN_PHPSTAN_TEMPLATE="$PROJECTPATH/.warp/setup/init/config/lint/phpstan.neon.dist"
SCAN_PHP_CONTAINER="${WARP_SCAN_PHP_CONTAINER:-}"
SCAN_LAST_CAPTURED_OUTPUT=""

SCAN_PHPCS_BIN="vendor/squizlabs/php_codesniffer/bin/phpcs"
SCAN_PHPCBF_BIN="vendor/squizlabs/php_codesniffer/bin/phpcbf"
SCAN_PHPMD_BIN=""
SCAN_PHPSTAN_BIN="vendor/bin/phpstan"

scan_spinner_wait() {
    _pid="$1"
    _message="$2"
    _spin='|/-\'
    _i=0

    [ -t 1 ] || return 0

    while kill -0 "$_pid" 2>/dev/null; do
        _i=$(((_i + 1) % 4))
        printf "\r%s [%c]" "$_message" "${_spin:$_i:1}"
        sleep 0.1
    done

    printf "\r%*s\r" 80 ""
}

scan_run_to_file_with_spinner() {
    _label="$1"
    _outfile="$2"
    shift 2

    "$@" > "$_outfile" 2>&1 &
    _pid=$!
    scan_spinner_wait "$_pid" "$_label"
    wait "$_pid"
    return $?
}

scan_run_capture_with_spinner() {
    _label="$1"
    shift

    _tmp_file=$(mktemp 2>/dev/null)
    [ -n "$_tmp_file" ] || {
        warp_message_error "could not create temporary file for scan output"
        return 1
    }

    "$@" > "$_tmp_file" 2>&1 &
    _pid=$!
    scan_spinner_wait "$_pid" "$_label"
    wait "$_pid"
    _status=$?

    SCAN_LAST_CAPTURED_OUTPUT="$(cat "$_tmp_file" 2>/dev/null)"
    rm -f "$_tmp_file"

    return $_status
}

scan_framework_detect() {
    if [ -f "$PROJECTPATH/bin/magento" ] || [ -f "$PROJECTPATH/app/etc/env.php" ]; then
        echo "magento"
        return 0
    fi

    if [ -f "$PROJECTPATH/artisan" ]; then
        echo "laravel"
        return 0
    fi

    if [ -f "$PROJECTPATH/wp-config.php" ]; then
        echo "wordpress"
        return 0
    fi

    echo "unknown"
}

scan_require_magento_context() {
    _framework=$(scan_framework_detect)
    case "$_framework" in
        magento)
            return 0
            ;;
        laravel)
            warp_message_warn "framework detected: laravel"
            warp_message_warn "scan hooks for laravel are not implemented yet"
            ;;
        wordpress)
            warp_message_warn "framework detected: wordpress"
            warp_message_warn "scan hooks for wordpress are not implemented yet"
            ;;
        *)
            warp_message_warn "framework not detected (magento/laravel/wordpress)"
            ;;
    esac

    warp_message_error "warp scan currently supports Magento only"
    exit 1
}

scan_ensure_output_dir() {
    mkdir -p "$SCAN_OUTPUT_DIR" 2>/dev/null || {
        warp_message_error "could not create output directory: $SCAN_OUTPUT_DIR"
        exit 1
    }
}

scan_runtime_is_available() {
    if [ -n "$SCAN_PHP_CONTAINER" ]; then
        _running=$(docker inspect --format '{{.State.Running}}' "$SCAN_PHP_CONTAINER" 2>/dev/null)
        [ "$_running" = "true" ] && echo true || echo false
        return 0
    fi

    if [ -f "$DOCKERCOMPOSEFILE" ] && [ "$(warp_check_is_running)" = false ]; then
        echo false
        return 0
    fi

    echo true
}

scan_compose_running_required_if_present() {
    if [ "$(scan_runtime_is_available)" = true ]; then
        return 0
    fi

    warp_message_error "The containers are not running"
    if [ -n "$SCAN_PHP_CONTAINER" ]; then
        warp_message_error "container not running: $SCAN_PHP_CONTAINER"
    else
        warp_message_error "please, first run warp start"
    fi

    return 1
}

scan_require_container_runtime() {
    if [ -n "$SCAN_PHP_CONTAINER" ]; then
        scan_compose_running_required_if_present || return 1
        return 0
    fi

    if [ ! -f "$DOCKERCOMPOSEFILE" ]; then
        warp_message_error "this scan action requires the php container runtime"
        warp_message_error "docker-compose-warp.yml not found"
        return 1
    fi

    scan_compose_running_required_if_present || return 1
}

scan_run_php_bin() {
    _bin="$1"
    shift

    if [ -n "$SCAN_PHP_CONTAINER" ]; then
        docker exec -i "$SCAN_PHP_CONTAINER" bash -lc 'cd /var/www/html && php "$@"' bash "$_bin" "$@"
        return $?
    fi

    if [ ! -f "$DOCKERCOMPOSEFILE" ]; then
        (
            cd "$PROJECTPATH" || exit 1
            php "$_bin" "$@"
        )
        return $?
    fi

    scan_compose_running_required_if_present || return 1

    docker-compose -f "$DOCKERCOMPOSEFILE" exec -T php bash -lc 'cd /var/www/html && php "$@"' bash "$_bin" "$@"
}

scan_run_php_runtime() {
    shift 0

    if [ -n "$SCAN_PHP_CONTAINER" ]; then
        docker exec -i "$SCAN_PHP_CONTAINER" bash -lc 'cd /var/www/html && "$@"' bash "$@"
        return $?
    fi

    if [ ! -f "$DOCKERCOMPOSEFILE" ]; then
        warp_message_error "docker-compose-warp.yml not found"
        return 1
    fi

    scan_compose_running_required_if_present || return 1
    docker-compose -f "$DOCKERCOMPOSEFILE" exec -T php bash -lc 'cd /var/www/html && "$@"' bash "$@"
}

scan_phpmd_detect_bin() {
    if [ -x "$PROJECTPATH/vendor/phpmd/phpmd/bin/phpmd" ]; then
        SCAN_PHPMD_BIN="vendor/phpmd/phpmd/bin/phpmd"
        return 0
    fi

    if [ -x "$PROJECTPATH/vendor/phpmd/phpmd/src/bin/phpmd" ]; then
        SCAN_PHPMD_BIN="vendor/phpmd/phpmd/src/bin/phpmd"
        return 0
    fi

    SCAN_PHPMD_BIN=""
    return 1
}

scan_require_phpcs_bin() {
    [ -x "$PROJECTPATH/$SCAN_PHPCS_BIN" ] && return 0

    warp_message_error "missing binary: $SCAN_PHPCS_BIN"
    warp_message_error "scan requires development executables installed in vendor/"
    warp_message_error "if this environment was installed with --no-dev, warp scan cannot run here"
    warp_message_error "run composer install (with require-dev) in the target environment first"
    return 1
}

scan_require_phpcbf_bin() {
    [ -x "$PROJECTPATH/$SCAN_PHPCBF_BIN" ] && return 0

    warp_message_error "missing binary: $SCAN_PHPCBF_BIN"
    warp_message_error "scan requires development executables installed in vendor/"
    warp_message_error "if this environment was installed with --no-dev, warp scan cannot run here"
    warp_message_error "run composer install (with require-dev) in the target environment first"
    return 1
}

scan_require_phpmd_bin() {
    scan_phpmd_detect_bin && return 0

    warp_message_error "missing binary: vendor/phpmd/phpmd/(bin|src/bin)/phpmd"
    warp_message_error "scan requires development executables installed in vendor/"
    warp_message_error "if this environment was installed with --no-dev, warp scan cannot run here"
    warp_message_error "run composer install (with require-dev) in the target environment first"
    return 1
}

scan_require_phpstan_bin() {
    [ -x "$PROJECTPATH/$SCAN_PHPSTAN_BIN" ] && return 0

    warp_message_error "missing binary: $SCAN_PHPSTAN_BIN"
    warp_message_error "install/configure it with: ./warp composer require --dev phpstan/phpstan"
    warp_message_error "then validate the binary with: ./warp composer exec -- phpstan --version"
    return 1
}

scan_require_phpcompat_standard() {
    scan_require_phpcs_bin || return 1
    scan_require_container_runtime || return 1

    scan_run_capture_with_spinner "checking PHPCompatibility standard" scan_run_php_bin "$SCAN_PHPCS_BIN" -i
    _status=$?
    if [ $_status -eq 0 ] && echo "$SCAN_LAST_CAPTURED_OUTPUT" | grep -q 'PHPCompatibility'; then
        return 0
    fi

    warp_message_error "required PHPCS standard is not available: PHPCompatibility"
    warp_message_error "install/configure it with: ./warp composer require --dev magento/php-compatibility-fork"
    warp_message_error "then validate the standard with: ./warp composer exec -- phpcs -i"
    return 1
}

scan_ensure_ruleset_runtime() {
    [ -f "$SCAN_RULESET_RUNTIME" ] && return 0

    mkdir -p "$(dirname "$SCAN_RULESET_RUNTIME")" 2>/dev/null || {
        warp_message_error "could not create lint config path: $(dirname "$SCAN_RULESET_RUNTIME")"
        exit 1
    }

    if [ -f "$SCAN_RULESET_PROJECT" ]; then
        cp "$SCAN_RULESET_PROJECT" "$SCAN_RULESET_RUNTIME" || {
            warp_message_error "could not copy $SCAN_RULESET_PROJECT to $SCAN_RULESET_RUNTIME"
            exit 1
        }
        warp_message_info "copied ruleset from app/devops/TestPR.xml to .warp/docker/config/lint/TestPR.xml"
        return 0
    fi

    if [ -f "$SCAN_RULESET_TEMPLATE" ]; then
        cp "$SCAN_RULESET_TEMPLATE" "$SCAN_RULESET_RUNTIME" || {
            warp_message_error "could not copy template ruleset to runtime config"
            exit 1
        }
        warp_message_info "copied template ruleset to .warp/docker/config/lint/TestPR.xml"
        return 0
    fi

    warp_message_error "ruleset not found: $SCAN_RULESET_RUNTIME"
    warp_message_error "missing fallback source: $SCAN_RULESET_TEMPLATE"
    exit 1
}

scan_ensure_phpstan_config() {
    [ -f "$SCAN_PHPSTAN_CONFIG" ] && return 0

    if [ ! -f "$SCAN_PHPSTAN_TEMPLATE" ]; then
        warp_message_error "phpstan config template not found: $SCAN_PHPSTAN_TEMPLATE"
        return 1
    fi

    cp "$SCAN_PHPSTAN_TEMPLATE" "$SCAN_PHPSTAN_CONFIG" || {
        warp_message_error "could not copy phpstan config to $SCAN_PHPSTAN_CONFIG"
        return 1
    }

    warp_message_info "copied template phpstan.neon.dist to project root"
    return 0
}

scan_normalize_php_version() {
    _version="$1"
    _normalized=$(echo "$_version" | sed 's/-.*$//' | sed -n 's/^\([0-9]\+\.[0-9]\+\).*/\1/p')
    echo "$_normalized"
}

scan_phpcompat_target_version() {
    _raw_version=""

    if scan_require_container_runtime >/dev/null 2>&1; then
        scan_run_capture_with_spinner "detecting php runtime version" scan_run_php_runtime php -r 'echo PHP_VERSION;'
        if [ $? -eq 0 ]; then
            _raw_version="$SCAN_LAST_CAPTURED_OUTPUT"
        fi
    fi

    if [ -z "$_raw_version" ] && [ -f "$ENVIRONMENTVARIABLESFILE" ]; then
        _raw_version=$(warp_env_read_var PHP_VERSION)
    fi

    scan_normalize_php_version "$_raw_version"
}

scan_run_phpmd_compat() {
    _target="$1"
    _mode="$2"
    _ruleset="$3"
    shift 3
    _args=("$@")

    scan_run_capture_with_spinner "running phpmd on ${_target}" scan_run_php_bin "$SCAN_PHPMD_BIN" "$_target" "$_mode" "$_ruleset" "${_args[@]}"
    _status=$?
    _output="$SCAN_LAST_CAPTURED_OUTPUT"

    if [ $_status -ne 0 ] && echo "$_output" | grep -Eq 'Command ".+" is not defined\.'; then
        scan_run_capture_with_spinner "running phpmd analyze on ${_target}" scan_run_php_bin "$SCAN_PHPMD_BIN" analyze "$_target" --format "$_mode" --ruleset "$_ruleset" --no-progress "${_args[@]}"
        _status=$?
        _output="$SCAN_LAST_CAPTURED_OUTPUT"

        if [ $_status -ne 0 ] && echo "$_output" | grep -Eq 'Command ".+" is not defined\.'; then
            scan_run_capture_with_spinner "running phpmd check on ${_target}" scan_run_php_bin "$SCAN_PHPMD_BIN" check "$_target" "$_ruleset" --format "$_mode" --no-progress "${_args[@]}"
            _status=$?
            _output="$SCAN_LAST_CAPTURED_OUTPUT"
        fi

        if [ $_status -ne 0 ] && echo "$_output" | grep -Eq 'Command ".+" is not defined\.'; then
            scan_run_capture_with_spinner "running phpmd legacy on ${_target}" scan_run_php_bin "$SCAN_PHPMD_BIN" phpmd "$_target" "$_mode" "$_ruleset" "${_args[@]}"
            _status=$?
            _output="$SCAN_LAST_CAPTURED_OUTPUT"
        fi
    fi

    SCAN_LAST_CAPTURED_OUTPUT="$_output"
    return $_status
}

scan_output_file() {
    _prefix="$1"
    _suffix="$2"
    _ts=$(date +%Y%m%d-%H%M%S)
    printf "%s/%s_%s_%s.txt" "$SCAN_OUTPUT_DIR" "$_prefix" "$_suffix" "$_ts"
}

scan_rel_path_from_project() {
    _in="$1"

    if [ -z "$_in" ]; then
        return 1
    fi

    if [ "${_in#/}" != "$_in" ]; then
        _abs="$_in"
    else
        _abs="$PROJECTPATH/$_in"
    fi

    _abs=$(cd "$(dirname "$_abs")" 2>/dev/null && pwd)/$(basename "$_abs")

    if [ ! -e "$_abs" ]; then
        return 1
    fi

    case "$_abs" in
        "$PROJECTPATH")
            echo "."
            return 0
            ;;
        "$PROJECTPATH"/*)
            echo "${_abs#$PROJECTPATH/}"
            return 0
            ;;
        *)
            warp_message_error "path must be inside project root: $PROJECTPATH"
            return 2
            ;;
    esac
}

scan_report_result() {
    _status="$1"
    _file="$2"
    _display_file="$_file"

    case "$_file" in
        "$PROJECTPATH"/*)
            _display_file="${_file#$PROJECTPATH/}"
            ;;
    esac

    if [ "$_status" -ne 0 ]; then
        warp_message_error "scan found issues"
    else
        warp_message_ok "scan finished without issues"
    fi

    warp_message ""
    warp_message "    output file: $_display_file"
    warp_message ""
}

scan_run_pr() {
    scan_require_magento_context
    scan_ensure_output_dir
    scan_require_phpcs_bin || return 1
    scan_require_phpmd_bin || return 1
    scan_require_phpcompat_standard || return 1
    scan_ensure_ruleset_runtime

    _path_code="app/code"
    _path_design="app/design"
    _standard="vendor/magento/magento-coding-standard/Magento2"
    _ruleset=".warp/docker/config/lint/TestPR.xml"
    _file=$(scan_output_file "scan" "testpr")
    _status=0
    _phpcompat_target_version=$(scan_phpcompat_target_version)

    if [ -z "$_phpcompat_target_version" ]; then
        warp_message_error "could not resolve PHPCompatibility target version"
        return 1
    fi

    if ! scan_run_to_file_with_spinner "running phpcs PR checks" "$_file" scan_run_php_bin "$SCAN_PHPCS_BIN" --ignore=*/Test/Unit/* --standard="$_standard" --severity=7 "$_path_code" "$_path_design"; then
        _status=1
    fi

    echo "PHP MESS DETECTOR" >> "$_file"
    scan_run_phpmd_compat "$_path_code" text "$_ruleset"
    _phpmd_status=$?
    echo "$SCAN_LAST_CAPTURED_OUTPUT" >> "$_file"
    if [ $_phpmd_status -ne 0 ]; then
        _status=1
    fi

    echo "PHP COMPATIBILITY" >> "$_file"
    if ! scan_run_to_file_with_spinner "running phpcompat on ${_path_code}" "$_file.tmp" scan_run_php_bin "$SCAN_PHPCS_BIN" --ignore=*/Test/Unit/* --extensions=php,phtml --standard=PHPCompatibility --runtime-set testVersion "$_phpcompat_target_version" "$_path_code"; then
        _status=1
    fi
    cat "$_file.tmp" >> "$_file"
    rm -f "$_file.tmp"
    {
        echo ""
        echo "PHPCompatibility target version: ${_phpcompat_target_version}"
        echo "Scanned path: ${_path_code}"
    } >> "$_file"

    scan_report_result "$_status" "$_file"
    return $_status
}

scan_run_phpcs_on_path() {
    _path="$1"
    scan_require_phpcs_bin || return 1
    _standard="vendor/magento/magento-coding-standard/Magento2"
    _safe=$(echo "$_path" | tr '/ ' '__' | tr -cd '[:alnum:]._-')
    _file=$(scan_output_file "scan" "phpcs_${_safe}")

    if scan_run_to_file_with_spinner "running phpcs on ${_path}" "$_file" scan_run_php_bin "$SCAN_PHPCS_BIN" --ignore=*/Test/Unit/* --standard="$_standard" "$_path"; then
        scan_report_result 0 "$_file"
        return 0
    fi

    scan_report_result 1 "$_file"
    return 1
}

scan_run_phpcbf_on_path() {
    _path="$1"
    scan_require_phpcbf_bin || return 1
    _standard="vendor/magento/magento-coding-standard/Magento2"
    _safe=$(echo "$_path" | tr '/ ' '__' | tr -cd '[:alnum:]._-')
    _file=$(scan_output_file "scan" "phpcbf_${_safe}")
    if scan_run_to_file_with_spinner "running phpcbf on ${_path}" "$_file" scan_run_php_bin "$SCAN_PHPCBF_BIN" --ignore=*/Test/Unit/* --standard="$_standard" "$_path"; then
        scan_report_result 0 "$_file"
        return 0
    fi

    scan_report_result 1 "$_file"
    return 1
}

scan_run_phpmd_on_path() {
    _path="$1"
    scan_require_phpmd_bin || return 1
    _safe=$(echo "$_path" | tr '/ ' '__' | tr -cd '[:alnum:]._-')
    _file=$(scan_output_file "scan" "phpmd_${_safe}")
    _status=0

    _ruleset_path="vendor/phpmd/phpmd/rulesets"
    [ -d "$PROJECTPATH/$_ruleset_path" ] || _ruleset_path="vendor/phpmd/phpmd/src/main/resources/rulesets"

    _rules=(cleancode codesize controversial design naming unusedcode)
    : > "$_file"

    for _rule in "${_rules[@]}"; do
        echo " $_rule" >> "$_file"
        echo "============================================================" >> "$_file"
        scan_run_phpmd_compat "$_path" text "${_ruleset_path}/${_rule}.xml" --exclude "*/Unit/*Test.php"
        _phpmd_status=$?
        echo "$SCAN_LAST_CAPTURED_OUTPUT" >> "$_file"
        if [ $_phpmd_status -ne 0 ]; then
            _status=1
        fi
        echo " " >> "$_file"
    done

    scan_report_result "$_status" "$_file"
    return $_status
}

scan_run_testpr_on_path() {
    _path="$1"
    scan_require_phpcs_bin || return 1
    scan_require_phpmd_bin || return 1
    scan_ensure_ruleset_runtime || return 1
    _standard="vendor/magento/magento-coding-standard/Magento2"
    _ruleset=".warp/docker/config/lint/TestPR.xml"
    _safe=$(echo "$_path" | tr '/ ' '__' | tr -cd '[:alnum:]._-')
    _file=$(scan_output_file "scan" "testpr_${_safe}")
    _status=0

    if ! scan_run_to_file_with_spinner "running phpcs test PR on ${_path}" "$_file" scan_run_php_bin "$SCAN_PHPCS_BIN" --ignore=*/Test/Unit/* --standard="$_standard" --severity=7 "$_path"; then
        _status=1
    fi

    echo "PHP MESS DETECTOR" >> "$_file"
    scan_run_phpmd_compat "$_path" text "$_ruleset"
    _phpmd_status=$?
    echo "$SCAN_LAST_CAPTURED_OUTPUT" >> "$_file"
    if [ $_phpmd_status -ne 0 ]; then
        _status=1
    fi

    scan_report_result "$_status" "$_file"
    return $_status
}

scan_run_phpcompat_on_path() {
    _path="$1"
    scan_require_phpcompat_standard || return 1
    _target_version=$(scan_phpcompat_target_version)
    if [ -z "$_target_version" ]; then
        warp_message_error "could not resolve PHPCompatibility target version"
        return 1
    fi

    _safe=$(echo "$_path" | tr '/ ' '__' | tr -cd '[:alnum:]._-')
    _file=$(scan_output_file "scan" "phpcompat_${_safe}")

    if scan_run_to_file_with_spinner "running phpcompat on ${_path}" "$_file" scan_run_php_bin "$SCAN_PHPCS_BIN" --ignore=*/Test/Unit/* --extensions=php,phtml --standard=PHPCompatibility --runtime-set testVersion "$_target_version" "$_path"; then
        {
            echo ""
            echo "PHPCompatibility target version: ${_target_version}"
            echo "Scanned path: ${_path}"
        } >> "$_file"
        scan_report_result 0 "$_file"
        return 0
    fi

    {
        echo ""
        echo "PHPCompatibility target version: ${_target_version}"
        echo "Scanned path: ${_path}"
    } >> "$_file"
    scan_report_result 1 "$_file"
    return 1
}

scan_run_phpstan_default() {
    _level="$1"
    scan_require_phpstan_bin || return 1
    scan_require_container_runtime || return 1
    scan_ensure_phpstan_config || return 1

    _file=$(scan_output_file "scan" "phpstan_default")
    _args=(analyse --no-progress)
    [ -n "$_level" ] && _args+=(--level "$_level")

    if scan_run_to_file_with_spinner "running phpstan on default scope" "$_file" scan_run_php_bin "$SCAN_PHPSTAN_BIN" "${_args[@]}"; then
        scan_report_result 0 "$_file"
        return 0
    fi

    scan_report_result 1 "$_file"
    return 1
}

scan_run_phpstan_on_path() {
    _path="$1"
    _level="$2"
    scan_require_phpstan_bin || return 1
    scan_require_container_runtime || return 1
    scan_ensure_phpstan_config || return 1

    _safe=$(echo "$_path" | tr '/ ' '__' | tr -cd '[:alnum:]._-')
    _file=$(scan_output_file "scan" "phpstan_${_safe}")
    _args=(analyse --no-progress)
    [ -n "$_level" ] && _args+=(--level "$_level")
    _args+=("$_path")

    if scan_run_to_file_with_spinner "running phpstan on ${_path}" "$_file" scan_run_php_bin "$SCAN_PHPSTAN_BIN" "${_args[@]}"; then
        scan_report_result 0 "$_file"
        return 0
    fi

    scan_report_result 1 "$_file"
    return 1
}

scan_path_option_add() {
    _candidate="$1"
    [ -n "$_candidate" ] || return 0

    for _existing in "${SCAN_PATH_OPTIONS[@]}"; do
        [ "$_existing" = "$_candidate" ] && return 0
    done

    SCAN_PATH_OPTIONS+=("$_candidate")
}

scan_path_option_add_children() {
    _base="$1"
    _maxdepth="$2"

    [ -d "$PROJECTPATH/$_base" ] || return 0

    while IFS= read -r _dir; do
        _rel="${_dir#$PROJECTPATH/}"
        scan_path_option_add "$_rel"
    done <<EOF
$(find "$PROJECTPATH/$_base" -mindepth 1 -maxdepth "$_maxdepth" -type d | sort)
EOF
}

scan_build_path_options() {
    SCAN_PATH_OPTIONS=("custom path")

    if [ -d "$PROJECTPATH/app/code" ]; then
        scan_path_option_add "app/code"
        scan_path_option_add_children "app/code" 1
    fi

    if [ -d "$PROJECTPATH/app/design" ]; then
        scan_path_option_add "app/design"
        scan_path_option_add "app/design/frontend"
        scan_path_option_add "app/design/adminhtml"
    fi

    if [ -d "$PROJECTPATH/extensions" ]; then
        scan_path_option_add "extensions"
        scan_path_option_add_children "extensions" 1
    fi
}

scan_select_path_menu() {
    SCAN_SELECTED_PATH=""
    scan_build_path_options

    _options=("cancel" "${SCAN_PATH_OPTIONS[@]}")
    PS3="choose path to scan: "

    while : ; do
        select _selected in "${_options[@]}"; do
            case "$_selected" in
                "cancel")
                    return 1
                    ;;
                "custom path")
                    read -r -p "path to scan (inside project): " _custom_path
                    if [ -z "$_custom_path" ]; then
                        warp_message_warn "path is required"
                        break
                    fi

                    _rel=$(scan_rel_path_from_project "$_custom_path")
                    _rel_status=$?
                    if [ $_rel_status -ne 0 ]; then
                        [ $_rel_status -eq 1 ] && warp_message_error "path not found: $_custom_path"
                        break
                    fi

                    SCAN_SELECTED_PATH="$_rel"
                    return 0
                    ;;
                "")
                    warp_message_warn "invalid option"
                    break
                    ;;
                *)
                    SCAN_SELECTED_PATH="$_selected"
                    return 0
                    ;;
            esac
        done
    done
}

scan_menu_tools_for_path() {
    _rel="$1"
    PS3="choose scan action for ${_rel}: "
    _options=("cancel" "phpcs" "phpcbf" "phpmd" "phpcompat" "phpstan" "test PR")
    select _opt in "${_options[@]}"; do
        case "$_opt" in
            cancel)
                warp_message_info "scan cancelled"
                return 0
                ;;
            phpcs)
                scan_run_phpcs_on_path "$_rel"
                return $?
                ;;
            phpcbf)
                scan_run_phpcbf_on_path "$_rel"
                return $?
                ;;
            phpmd)
                scan_run_phpmd_on_path "$_rel"
                return $?
                ;;
            phpcompat)
                scan_run_phpcompat_on_path "$_rel"
                return $?
                ;;
            phpstan)
                scan_run_phpstan_on_path "$_rel"
                return $?
                ;;
            "test PR")
                scan_run_testpr_on_path "$_rel"
                return $?
                ;;
            *)
                warp_message_warn "invalid option"
                ;;
        esac
    done
}

scan_menu_path() {
    _input="$1"

    if [ -z "$_input" ]; then
        read -r -p "path to scan (inside project): " _input
    fi

    _rel=$(scan_rel_path_from_project "$_input")
    _rel_status=$?
    if [ $_rel_status -ne 0 ]; then
        [ $_rel_status -eq 1 ] && warp_message_error "path not found: $_input"
        exit 1
    fi

    scan_require_magento_context
    scan_ensure_output_dir

    scan_menu_tools_for_path "$_rel"
    return $?
}

scan_warp_exec() {
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

scan_run_integrity() {
    scan_require_magento_context
    _warp_exec=$(scan_warp_exec)

    warp_message_info "running Magento integrity compile"
    if ! $_warp_exec magento setup:di:compile; then
        warp_message_error "setup:di:compile failed"
        return 1
    fi

    scan_run_pr
}

scan_menu_main() {
    scan_require_magento_context
    scan_ensure_output_dir

    PS3="choose scan action: "
    _options=("cancel" "phpcs" "phpcbf" "phpmd" "phpcompat" "phpstan" "test PR")
    select _opt in "${_options[@]}"; do
        case "$_opt" in
            cancel)
                warp_message_info "scan cancelled"
                return 0
                ;;
            phpcs)
                scan_select_path_menu || { warp_message_info "scan cancelled"; return 0; }
                scan_run_phpcs_on_path "$SCAN_SELECTED_PATH"
                return $?
                ;;
            phpcbf)
                scan_select_path_menu || { warp_message_info "scan cancelled"; return 0; }
                scan_run_phpcbf_on_path "$SCAN_SELECTED_PATH"
                return $?
                ;;
            phpmd)
                scan_select_path_menu || { warp_message_info "scan cancelled"; return 0; }
                scan_run_phpmd_on_path "$SCAN_SELECTED_PATH"
                return $?
                ;;
            phpcompat)
                scan_select_path_menu || { warp_message_info "scan cancelled"; return 0; }
                scan_run_phpcompat_on_path "$SCAN_SELECTED_PATH"
                return $?
                ;;
            phpstan)
                scan_run_phpstan_default
                return $?
                ;;
            "test PR")
                scan_run_pr
                return $?
                ;;
            *)
                warp_message_warn "invalid option"
                ;;
        esac
    done
}

scan_resolve_path_argument() {
    _input="$1"
    _rel=$(scan_rel_path_from_project "$_input")
    _rel_status=$?
    if [ $_rel_status -ne 0 ]; then
        [ $_rel_status -eq 1 ] && warp_message_error "path not found: $_input"
        return $_rel_status
    fi

    echo "$_rel"
}

scan_parse_direct_path_args() {
    SCAN_DIRECT_PATH=""

    case "$1" in
        "")
            return 0
            ;;
        --path)
            shift
            [ "$#" -eq 1 ] || { warp_message_error "--path requires exactly one argument"; return 1; }
            SCAN_DIRECT_PATH=$(scan_resolve_path_argument "$1") || return $?
            return 0
            ;;
        *)
            warp_message_error "unknown option: $1"
            return 1
            ;;
    esac
}

scan_parse_phpstan_args() {
    SCAN_DIRECT_PATH=""
    SCAN_PHPSTAN_LEVEL=""

    while [ "$#" -gt 0 ]; do
        case "$1" in
            --path)
                shift
                [ "$#" -gt 0 ] || { warp_message_error "phpstan --path requires exactly one argument"; return 1; }
                [ -z "$SCAN_DIRECT_PATH" ] || { warp_message_error "phpstan --path specified more than once"; return 1; }
                SCAN_DIRECT_PATH=$(scan_resolve_path_argument "$1") || return $?
                ;;
            --level)
                shift
                [ "$#" -gt 0 ] || { warp_message_error "phpstan --level requires exactly one argument"; return 1; }
                [ -z "$SCAN_PHPSTAN_LEVEL" ] || { warp_message_error "phpstan --level specified more than once"; return 1; }
                echo "$1" | rg -q '^[0-9]+$' || { warp_message_error "phpstan --level must be numeric"; return 1; }
                SCAN_PHPSTAN_LEVEL="$1"
                ;;
            *)
                warp_message_error "unknown option for phpstan: $1"
                return 1
                ;;
        esac
        shift
    done

    return 0
}

scan_command()
{
    case "$1" in
        -h|--help)
            scan_help_usage
            return 0
            ;;
        --pr|pr)
            shift
            [ "$#" -eq 0 ] || { warp_message_error "pr/--pr does not accept extra arguments"; return 1; }
            scan_run_pr
            return $?
            ;;
        integrity|-i)
            shift
            [ "$#" -eq 0 ] || { warp_message_error "integrity/-i does not accept extra arguments"; return 1; }
            scan_run_integrity
            return $?
            ;;
        phpcs)
            shift
            scan_require_magento_context
            scan_ensure_output_dir
            scan_parse_direct_path_args "$@" || return $?
            if [ -n "$SCAN_DIRECT_PATH" ]; then
                scan_run_phpcs_on_path "$SCAN_DIRECT_PATH"
            else
                scan_select_path_menu || { warp_message_info "scan cancelled"; return 0; }
                scan_run_phpcs_on_path "$SCAN_SELECTED_PATH"
            fi
            return $?
            ;;
        phpcbf)
            shift
            scan_require_magento_context
            scan_ensure_output_dir
            scan_parse_direct_path_args "$@" || return $?
            if [ -n "$SCAN_DIRECT_PATH" ]; then
                scan_run_phpcbf_on_path "$SCAN_DIRECT_PATH"
            else
                scan_select_path_menu || { warp_message_info "scan cancelled"; return 0; }
                scan_run_phpcbf_on_path "$SCAN_SELECTED_PATH"
            fi
            return $?
            ;;
        phpmd)
            shift
            scan_require_magento_context
            scan_ensure_output_dir
            scan_parse_direct_path_args "$@" || return $?
            if [ -n "$SCAN_DIRECT_PATH" ]; then
                scan_run_phpmd_on_path "$SCAN_DIRECT_PATH"
            else
                scan_select_path_menu || { warp_message_info "scan cancelled"; return 0; }
                scan_run_phpmd_on_path "$SCAN_SELECTED_PATH"
            fi
            return $?
            ;;
        phpcompat)
            shift
            scan_require_magento_context
            scan_ensure_output_dir
            scan_parse_direct_path_args "$@" || return $?
            if [ -n "$SCAN_DIRECT_PATH" ]; then
                scan_run_phpcompat_on_path "$SCAN_DIRECT_PATH"
            else
                scan_select_path_menu || { warp_message_info "scan cancelled"; return 0; }
                scan_run_phpcompat_on_path "$SCAN_SELECTED_PATH"
            fi
            return $?
            ;;
        phpstan)
            shift
            scan_require_magento_context
            scan_ensure_output_dir
            scan_parse_phpstan_args "$@" || return $?
            if [ -n "$SCAN_DIRECT_PATH" ] && [ "$SCAN_DIRECT_PATH" != "." ]; then
                scan_run_phpstan_on_path "$SCAN_DIRECT_PATH" "$SCAN_PHPSTAN_LEVEL"
            else
                scan_run_phpstan_default "$SCAN_PHPSTAN_LEVEL"
            fi
            return $?
            ;;
        --path)
            shift
            [ "$#" -eq 1 ] || { warp_message_error "--path requires exactly one argument"; return 1; }
            scan_menu_path "$1"
            return $?
            ;;
        "")
            scan_menu_main
            return $?
            ;;
        *)
            warp_message_error "unknown option: $1"
            scan_help_usage
            return 1
            ;;
    esac
}

function scan_main()
{
    scan_command "$@"
}
