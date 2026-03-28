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
    local _pid="$1"
    local _message="$2"
    local _spin='|/-\'
    local _i=0

    [ -t 1 ] || return 0

    while kill -0 "$_pid" 2>/dev/null; do
        _i=$(((_i + 1) % 4))
        printf "\r%s [%c]" "$_message" "${_spin:$_i:1}"
        sleep 0.1
    done

    printf "\r%*s\r" 100 ""
}

scan_run_to_file_with_spinner() {
    local _label="$1"
    local _outfile="$2"
    local _pid
    local _status
    shift 2

    "$@" > "$_outfile" 2>&1 &
    _pid=$!
    scan_spinner_wait "$_pid" "$_label"
    wait "$_pid"
    _status=$?
    if [ $_status -ne 0 ]; then
        return $_status
    fi

    return 0
}

scan_run_capture_with_spinner() {
    local _label="$1"
    local _tmp_file
    local _pid
    local _status
    shift

    _tmp_file=$(mktemp 2>/dev/null)
    [ -n "$_tmp_file" ] || {
        warp_message_error "could not create temporary file for audit output"
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

scan_has_rg() {
    command -v rg >/dev/null 2>&1
}

scan_search_named_content() {
    local _pattern="$1"
    shift
    local _root="$1"
    shift
    local _names=("$@")
    local _name=""

    if scan_has_rg; then
        local _rg_args=()
        for _name in "${_names[@]}"; do
            _rg_args+=(-g "$_name")
        done
        rg -n -H -e "$_pattern" "${_rg_args[@]}" "$_root" 2>/dev/null
        return 0
    fi

    for _name in "${_names[@]}"; do
        find "$_root" -type f -name "$_name" 2>/dev/null
    done | while IFS= read -r _file; do
        [ -f "$_file" ] || continue
        grep -nHE -- "$_pattern" "$_file" 2>/dev/null
    done
}

scan_should_ignore_risky_line() {
    local _line="$1"
    local _content=""
    local _trimmed=""

    _content="${_line#*:}"
    _content="${_content#*:}"
    _trimmed="${_content#"${_content%%[![:space:]]*}"}"

    case "$_trimmed" in
        //*) return 0 ;;
        '/*'*) return 0 ;;
        '*/'*) return 0 ;;
        \**) return 0 ;;
    esac

    return 1
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
    local _framework
    _framework=$(scan_framework_detect)
    case "$_framework" in
        magento)
            return 0
            ;;
        laravel)
            warp_message_warn "framework detected: laravel"
            warp_message_warn "audit hooks for laravel are not implemented yet"
            ;;
        wordpress)
            warp_message_warn "framework detected: wordpress"
            warp_message_warn "audit hooks for wordpress are not implemented yet"
            ;;
        *)
            warp_message_warn "framework not detected (magento/laravel/wordpress)"
            ;;
    esac

    warp_message_error "warp audit currently supports Magento only"
    exit 1
}

scan_ensure_output_dir() {
    mkdir -p "$SCAN_OUTPUT_DIR" 2>/dev/null || {
        warp_message_error "could not create output directory: $SCAN_OUTPUT_DIR"
        exit 1
    }
}

scan_runtime_is_available() {
    local _running
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
        warp_message_error "this audit action requires the php container runtime"
        warp_message_error "docker-compose-warp.yml not found"
        return 1
    fi

    scan_compose_running_required_if_present || return 1
}

scan_run_php_bin() {
    local _bin="$1"
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
    warp_message_error "audit requires development executables installed in vendor/"
        warp_message_error "if this environment was installed with --no-dev, warp audit cannot run here"
    warp_message_error "run composer install (with require-dev) in the target environment first"
    return 1
}

scan_require_phpcbf_bin() {
    [ -x "$PROJECTPATH/$SCAN_PHPCBF_BIN" ] && return 0

    warp_message_error "missing binary: $SCAN_PHPCBF_BIN"
    warp_message_error "audit requires development executables installed in vendor/"
    warp_message_error "if this environment was installed with --no-dev, warp audit cannot run here"
    warp_message_error "run composer install (with require-dev) in the target environment first"
    return 1
}

scan_require_phpmd_bin() {
    scan_phpmd_detect_bin && return 0

    warp_message_error "missing binary: vendor/phpmd/phpmd/(bin|src/bin)/phpmd"
    warp_message_error "audit requires development executables installed in vendor/"
    warp_message_error "if this environment was installed with --no-dev, warp audit cannot run here"
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
    local _status
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

scan_validate_phpstan_level() {
    local _level="$1"

    case "$_level" in
        ''|*[!0-9]*)
            warp_message_error "phpstan --level requires a numeric value"
            return 1
            ;;
    esac

    return 0
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
    local _version="$1"
    local _normalized
    _normalized=$(echo "$_version" | sed 's/-.*$//' | sed -n 's/^\([0-9]\+\.[0-9]\+\).*/\1/p')
    echo "$_normalized"
}

scan_phpcompat_target_version() {
    local _raw_version=""

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
    local _target="$1"
    local _mode="$2"
    local _ruleset="$3"
    shift 3
    local _args=("$@")
    local _status
    local _output
    local _ruleset_label

    _ruleset_label="$(basename "$_ruleset" .xml)"

    scan_run_capture_with_spinner "running phpmd analyze [${_ruleset_label}] on ${_target}" scan_run_php_bin "$SCAN_PHPMD_BIN" analyze "$_target" --format "$_mode" --ruleset "$_ruleset" --no-progress "${_args[@]}"
    _status=$?
    _output="$SCAN_LAST_CAPTURED_OUTPUT"

    if [ $_status -ne 0 ] && echo "$_output" | grep -Eq 'Command ".+" is not defined\.'; then
        scan_run_capture_with_spinner "running phpmd check [${_ruleset_label}] on ${_target}" scan_run_php_bin "$SCAN_PHPMD_BIN" check "$_target" "$_ruleset" --format "$_mode" --no-progress "${_args[@]}"
        _status=$?
        _output="$SCAN_LAST_CAPTURED_OUTPUT"

        if [ $_status -ne 0 ] && echo "$_output" | grep -Eq 'Command ".+" is not defined\.'; then
            scan_run_capture_with_spinner "running phpmd legacy [${_ruleset_label}] on ${_target}" scan_run_php_bin "$SCAN_PHPMD_BIN" "$_target" "$_mode" "$_ruleset" "${_args[@]}"
            _status=$?
            _output="$SCAN_LAST_CAPTURED_OUTPUT"

            if [ $_status -ne 0 ] && echo "$_output" | grep -Eq 'Command ".+" is not defined\.'; then
                scan_run_capture_with_spinner "running phpmd legacy alt [${_ruleset_label}] on ${_target}" scan_run_php_bin "$SCAN_PHPMD_BIN" phpmd "$_target" "$_mode" "$_ruleset" "${_args[@]}"
                _status=$?
                _output="$SCAN_LAST_CAPTURED_OUTPUT"
            fi
        fi
    fi

    SCAN_LAST_CAPTURED_OUTPUT="$_output"
    return $_status
}

scan_is_phpmd_project_target() {
    local _abs="$1"

    [ -f "$_abs/registration.php" ] && return 0
    [ -f "$_abs/etc/module.xml" ] && return 0
    [ -f "$_abs/theme.xml" ] && return 0

    return 1
}

scan_resolve_phpmd_targets() {
    local _target="$1"
    local _absolute="$PROJECTPATH/$_target"
    local _expanded=()
    local _child
    local _nested

    if [ ! -d "$_absolute" ]; then
        printf '%s\n' "$_target"
        return
    fi

    shopt -s nullglob

    for _child in "$_absolute"/*/; do
        _child="${_child%/}"
        if scan_is_phpmd_project_target "$_child"; then
            _expanded+=("${_child#$PROJECTPATH/}")
        fi
    done

    if [ ${#_expanded[@]} -eq 0 ]; then
        for _child in "$_absolute"/*/; do
            for _nested in "$_child"*/; do
                _nested="${_nested%/}"
                if scan_is_phpmd_project_target "$_nested"; then
                    _expanded+=("${_nested#$PROJECTPATH/}")
                fi
            done
        done
    fi

    shopt -u nullglob

    if [ ${#_expanded[@]} -gt 0 ]; then
        printf '%s\n' "${_expanded[@]}"
        return
    fi

    printf '%s\n' "$_target"
}

scan_run_phpmd_compat_targets() {
    local _target="$1"
    local _mode="$2"
    local _ruleset="$3"
    shift 3
    local _args=("$@")
    local _targets=()
    local _status=0
    local _combined_output=""
    local _resolved_target
    local _target_status

    mapfile -t _targets < <(scan_resolve_phpmd_targets "$_target")

    if [ ${#_targets[@]} -eq 0 ]; then
        _targets=("$_target")
    fi

    for _resolved_target in "${_targets[@]}"; do
        scan_run_phpmd_compat "$_resolved_target" "$_mode" "$_ruleset" "${_args[@]}"
        _target_status=$?
        if [ -n "$SCAN_LAST_CAPTURED_OUTPUT" ]; then
            if [ ${#_targets[@]} -gt 1 ]; then
                _combined_output="${_combined_output}TARGET: ${_resolved_target}"$'\n'
            fi
            _combined_output="${_combined_output}${SCAN_LAST_CAPTURED_OUTPUT}"$'\n'$'\n'
        fi

        if [ $_target_status -ne 0 ]; then
            _status=1
        fi
    done

    SCAN_LAST_CAPTURED_OUTPUT="${_combined_output%$'\n'}"
    return $_status
}

scan_output_file() {
    local _prefix="$1"
    local _suffix="$2"
    local _ts
    _ts=$(date +%Y%m%d-%H%M%S)
    printf "%s/%s_%s_%s.txt" "$SCAN_OUTPUT_DIR" "$_prefix" "$_suffix" "$_ts"
}

scan_rel_path_from_project() {
    local _in="$1"
    local _abs

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
    local _status="$1"
    local _file="$2"
    local _display_file="$_file"

    case "$_file" in
        "$PROJECTPATH"/*)
            _display_file="${_file#$PROJECTPATH/}"
            ;;
    esac

    if [ "$_status" -ne 0 ]; then
        warp_message_error "audit found issues"
    else
        warp_message_ok "audit finished without issues"
    fi

    warp_message ""
    warp_message "    output file: $_display_file"
    warp_message ""
}

scan_append_phpcompat_metadata() {
    local _file="$1"
    local _target_version="$2"
    local _path="$3"

    {
        echo ""
        echo "PHPCompatibility target version: ${_target_version}"
        echo "Scanned path: ${_path}"
        echo ""
    } >> "$_file"
}

scan_append_phpmd_output() {
    local _file="$1"

    echo "PHP MESS DETECTOR" >> "$_file"
    if [ -n "$SCAN_LAST_CAPTURED_OUTPUT" ]; then
        echo "$SCAN_LAST_CAPTURED_OUTPUT" >> "$_file"
    fi
}

scan_build_safe_suffix() {
    local _path="$1"

    echo "$_path" | tr '/ ' '__' | tr -cd '[:alnum:]._-'
}

scan_run_simple_tool_to_file() {
    local _label="$1"
    local _file="$2"
    shift 2

    if scan_run_to_file_with_spinner "$_label" "$_file" "$@"; then
        return 0
    fi

    return 1
}

scan_run_testpr_suite() {
    local _output_suffix="$1"
    local _phpcompat_path="$2"
    shift 2
    local _phpcs_paths=("$@")
    local _standard="vendor/magento/magento-coding-standard/Magento2"
    local _ruleset=".warp/docker/config/lint/TestPR.xml"
    local _file
    local _status=0
    local _target_version
    local _phpmd_status

    _file=$(scan_output_file "audit" "${_output_suffix}")
    : > "$_file"

    _target_version=$(scan_phpcompat_target_version)
    if [ -z "$_target_version" ]; then
        warp_message_error "could not resolve PHPCompatibility target version"
        return 1
    fi

    scan_run_capture_with_spinner "running phpcompat PR checks" scan_run_php_bin "$SCAN_PHPCS_BIN" --standard=PHPCompatibility --runtime-set testVersion "$_target_version" --extensions=php,phtml "$_phpcompat_path"
    if [ $? -ne 0 ]; then
        _status=1
    fi
    if [ -n "$SCAN_LAST_CAPTURED_OUTPUT" ]; then
        echo "$SCAN_LAST_CAPTURED_OUTPUT" >> "$_file"
    fi
    scan_append_phpcompat_metadata "$_file" "$_target_version" "$_phpcompat_path"

    scan_run_capture_with_spinner "running phpcs PR checks" scan_run_php_bin "$SCAN_PHPCS_BIN" --ignore=*/Test/Unit/* --standard="$_standard" --severity=7 "${_phpcs_paths[@]}"
    if [ $? -ne 0 ]; then
        _status=1
    fi
    if [ -n "$SCAN_LAST_CAPTURED_OUTPUT" ]; then
        echo "$SCAN_LAST_CAPTURED_OUTPUT" >> "$_file"
    fi

    scan_run_phpmd_compat_targets "$_phpcompat_path" text "$_ruleset"
    _phpmd_status=$?
    scan_append_phpmd_output "$_file"
    if [ $_phpmd_status -ne 0 ]; then
        _status=1
    fi

    scan_report_result "$_status" "$_file"
    return $_status
}

scan_run_pr() {
    scan_require_magento_context
    scan_ensure_output_dir
    scan_require_phpcs_bin || return 1
    scan_require_phpmd_bin || return 1
    scan_require_phpcompat_standard || return 1
    scan_ensure_ruleset_runtime

    scan_run_testpr_suite "testpr" "app/code" "app/code" "app/design"
    return $?
}

scan_run_phpcs_on_path() {
    local _path="$1"
    local _standard
    local _safe
    local _file
    scan_require_phpcs_bin || return 1
    _standard="vendor/magento/magento-coding-standard/Magento2"
    _safe=$(scan_build_safe_suffix "$_path")
    _file=$(scan_output_file "audit" "phpcs_${_safe}")

    if scan_run_simple_tool_to_file "running phpcs on ${_path}" "$_file" scan_run_php_bin "$SCAN_PHPCS_BIN" --ignore=*/Test/Unit/* --standard="$_standard" "$_path"; then
        scan_report_result 0 "$_file"
        return 0
    fi

    scan_report_result 1 "$_file"
    return 1
}

scan_run_phpcbf_on_path() {
    local _path="$1"
    local _standard
    local _safe
    local _file
    scan_require_phpcbf_bin || return 1
    _standard="vendor/magento/magento-coding-standard/Magento2"
    _safe=$(scan_build_safe_suffix "$_path")
    _file=$(scan_output_file "audit" "phpcbf_${_safe}")
    if scan_run_simple_tool_to_file "running phpcbf on ${_path}" "$_file" scan_run_php_bin "$SCAN_PHPCBF_BIN" --ignore=*/Test/Unit/* --standard="$_standard" "$_path"; then
        scan_report_result 0 "$_file"
        return 0
    fi

    scan_report_result 1 "$_file"
    return 1
}

scan_run_phpmd_on_path() {
    local _path="$1"
    scan_require_phpmd_bin || return 1
    local _safe
    local _file
    local _status=0
    local _ruleset_path
    local _rules
    local _rule
    local _phpmd_status

    _safe=$(scan_build_safe_suffix "$_path")
    _file=$(scan_output_file "audit" "phpmd_${_safe}")

    _ruleset_path="vendor/phpmd/phpmd/rulesets"
    [ -d "$PROJECTPATH/$_ruleset_path" ] || _ruleset_path="vendor/phpmd/phpmd/src/main/resources/rulesets"

    _rules=(cleancode codesize controversial design naming unusedcode)
    : > "$_file"

    for _rule in "${_rules[@]}"; do
        echo " $_rule" >> "$_file"
        echo "============================================================" >> "$_file"
        scan_run_phpmd_compat_targets "$_path" text "${_ruleset_path}/${_rule}.xml" --exclude "*/Unit/*Test.php"
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
    local _path="$1"
    local _safe

    scan_require_phpcs_bin || return 1
    scan_require_phpmd_bin || return 1
    scan_require_phpcompat_standard || return 1
    scan_ensure_ruleset_runtime || return 1

    _safe=$(scan_build_safe_suffix "$_path")
    scan_run_testpr_suite "testpr_${_safe}" "$_path" "$_path"
    return $?
}

scan_run_phpcompat_on_path() {
    local _path="$1"
    local _target_version
    local _safe
    local _file
    scan_require_phpcompat_standard || return 1
    _target_version=$(scan_phpcompat_target_version)
    if [ -z "$_target_version" ]; then
        warp_message_error "could not resolve PHPCompatibility target version"
        return 1
    fi

    _safe=$(scan_build_safe_suffix "$_path")
    _file=$(scan_output_file "audit" "phpcompat_${_safe}")

    if scan_run_simple_tool_to_file "running phpcompat on ${_path}" "$_file" scan_run_php_bin "$SCAN_PHPCS_BIN" --ignore=*/Test/Unit/* --extensions=php,phtml --standard=PHPCompatibility --runtime-set testVersion "$_target_version" "$_path"; then
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

scan_run_risky_on_path() {
    local _path="$1"
    local _safe
    local _file
    local _status=0
    local _line=""
    local _found=0
    local _pattern='eval\s*\(|base64_decode\s*\(|(^|[^[:alnum:]_])system\s*\(|shell_exec\s*\(|passthru\s*\(|assert\s*\(|proc_open\s*\(|preg_replace\s*\(.*/e|(^|[^[:alnum:]_])create_function\s*\(|hash_equals\s*\(\s*md5\(|md5\(\$_COOKIE|\$_REQUEST|\$_COOKIE|\$_POST'

    _safe=$(scan_build_safe_suffix "$_path")
    _file=$(scan_output_file "audit" "risky_${_safe}")
    : > "$_file"

    while IFS= read -r _line; do
        [ -n "$_line" ] || continue
        scan_should_ignore_risky_line "$_line" && continue
        printf '%s\n' "$_line" >> "$_file"
        _found=1
    done < <(scan_search_named_content "$_pattern" "$PROJECTPATH/$_path" '*.php' '*.phtml' '*.phar' '*.inc' | sed "s#^$PROJECTPATH/##")

    if [ "$_found" -eq 1 ]; then
        _status=1
    fi

    scan_report_result "$_status" "$_file"
    return $_status
}

scan_run_phpstan_default() {
    local _level="${1:-}"
    local _file
    local -a _cmd
    scan_require_phpstan_bin || return 1
    scan_require_container_runtime || return 1
    scan_ensure_phpstan_config || return 1

    _cmd=("$SCAN_PHPSTAN_BIN" analyse --no-progress)
    if [ -n "$_level" ]; then
        _cmd+=(--level "$_level")
    fi

    _file=$(scan_output_file "audit" "phpstan_default")
    if scan_run_simple_tool_to_file "running phpstan on default scope" "$_file" scan_run_php_bin "${_cmd[@]}"; then
        scan_report_result 0 "$_file"
        return 0
    fi

    scan_report_result 1 "$_file"
    return 1
}

scan_run_phpstan_on_path() {
    local _path="$1"
    local _level="${2:-}"
    local _safe
    local _file
    local -a _cmd
    scan_require_phpstan_bin || return 1
    scan_require_container_runtime || return 1
    scan_ensure_phpstan_config || return 1

    _cmd=("$SCAN_PHPSTAN_BIN" analyse --no-progress)
    if [ -n "$_level" ]; then
        _cmd+=(--level "$_level")
    fi
    _cmd+=("$_path")

    _safe=$(scan_build_safe_suffix "$_path")
    _file=$(scan_output_file "audit" "phpstan_${_safe}")

    if scan_run_simple_tool_to_file "running phpstan on ${_path}" "$_file" scan_run_php_bin "${_cmd[@]}"; then
        scan_report_result 0 "$_file"
        return 0
    fi

    scan_report_result 1 "$_file"
    return 1
}

scan_path_option_add() {
    local _candidate="$1"
    local _existing
    [ -n "$_candidate" ] || return 0

    for _existing in "${SCAN_PATH_OPTIONS[@]}"; do
        [ "$_existing" = "$_candidate" ] && return 0
    done

    SCAN_PATH_OPTIONS+=("$_candidate")
}

scan_path_option_add_children() {
    local _base="$1"
    local _maxdepth="$2"
    local _dir
    local _rel

    [ -d "$PROJECTPATH/$_base" ] || return 0

    while IFS= read -r _dir; do
        _rel="${_dir#$PROJECTPATH/}"
        scan_path_option_add "$_rel"
    done <<EOF
$(find "$PROJECTPATH/$_base" -mindepth 1 -maxdepth "$_maxdepth" -type d | sort)
EOF
}

scan_build_path_options() {
    local _dummy
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
    local _options
    local _selected
    local _custom_path
    local _rel
    local _rel_status
    SCAN_SELECTED_PATH=""
    scan_build_path_options

    _options=("cancel" "${SCAN_PATH_OPTIONS[@]}")
    PS3="choose path to audit: "

    while : ; do
        select _selected in "${_options[@]}"; do
            case "$_selected" in
                "cancel")
                    return 1
                    ;;
                "custom path")
                    read -r -p "path to audit (inside project): " _custom_path
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
    local _rel="$1"
    local _options
    local _opt
    PS3="choose audit action for ${_rel}: "
    _options=("cancel" "phpcs" "phpcbf" "phpmd" "phpcompat" "risky" "phpstan" "test PR")
    select _opt in "${_options[@]}"; do
        case "$_opt" in
            cancel)
                warp_message_info "audit cancelled"
                return 0
                ;;
            phpcs)
                scan_run_selected_action "$_opt" "$_rel"
                return $?
                ;;
            phpcbf)
                scan_run_selected_action "$_opt" "$_rel"
                return $?
                ;;
            phpmd)
                scan_run_selected_action "$_opt" "$_rel"
                return $?
                ;;
            phpcompat)
                scan_run_selected_action "$_opt" "$_rel"
                return $?
                ;;
            risky)
                scan_run_selected_action "$_opt" "$_rel"
                return $?
                ;;
            phpstan)
                scan_run_selected_action "$_opt" "$_rel"
                return $?
                ;;
            "test PR")
                scan_run_selected_action "$_opt" "$_rel"
                return $?
                ;;
            *)
                warp_message_warn "invalid option"
                ;;
        esac
    done
}

scan_run_selected_action() {
    local _action="$1"
    local _path="${2:-}"

    case "$_action" in
        phpcs)
            scan_run_phpcs_on_path "$_path"
            return $?
            ;;
        phpcbf)
            scan_run_phpcbf_on_path "$_path"
            return $?
            ;;
        phpmd)
            scan_run_phpmd_on_path "$_path"
            return $?
            ;;
        phpcompat)
            scan_run_phpcompat_on_path "$_path"
            return $?
            ;;
        risky)
            scan_run_risky_on_path "$_path"
            return $?
            ;;
        phpstan)
            if [ -n "$_path" ] && [ "$_path" != "." ]; then
                scan_run_phpstan_on_path "$_path"
                return $?
            fi

            scan_run_phpstan_default
            return $?
            ;;
        "test PR")
            if [ -n "$_path" ]; then
                scan_run_testpr_on_path "$_path"
                return $?
            fi

            scan_run_pr
            return $?
            ;;
        *)
            warp_message_error "unknown audit action: $_action"
            return 1
            ;;
    esac
}

scan_menu_path() {
    local _input="$1"
    local _rel
    local _rel_status

    if [ -z "$_input" ]; then
        read -r -p "path to audit (inside project): " _input
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
    local _warp_exec
    local _status=0
    scan_require_magento_context
    _warp_exec=$(scan_warp_exec)

    warp_message_info "running Magento integrity compile"
    if ! $_warp_exec magento setup:di:compile; then
        warp_message_error "setup:di:compile failed"
        return 1
    fi

    scan_run_pr || _status=1
    scan_run_risky_on_path "app/code" || _status=1
    scan_run_phpstan_on_path "app/code" "1" || _status=1
    return $_status
}

scan_menu_main() {
    local _options
    local _opt
    scan_require_magento_context
    scan_ensure_output_dir

    PS3="choose audit action: "
    _options=("cancel" "phpcs" "phpcbf" "phpmd" "phpcompat" "risky" "phpstan" "test PR")
    select _opt in "${_options[@]}"; do
        case "$_opt" in
            cancel)
                warp_message_info "audit cancelled"
                return 0
                ;;
            phpcs)
                scan_select_path_menu || { warp_message_info "audit cancelled"; return 0; }
                scan_run_selected_action "$_opt" "$SCAN_SELECTED_PATH"
                return $?
                ;;
            phpcbf)
                scan_select_path_menu || { warp_message_info "audit cancelled"; return 0; }
                scan_run_selected_action "$_opt" "$SCAN_SELECTED_PATH"
                return $?
                ;;
            phpmd)
                scan_select_path_menu || { warp_message_info "audit cancelled"; return 0; }
                scan_run_selected_action "$_opt" "$SCAN_SELECTED_PATH"
                return $?
                ;;
            phpcompat)
                scan_select_path_menu || { warp_message_info "audit cancelled"; return 0; }
                scan_run_selected_action "$_opt" "$SCAN_SELECTED_PATH"
                return $?
                ;;
            risky)
                scan_select_path_menu || { warp_message_info "audit cancelled"; return 0; }
                scan_run_selected_action "$_opt" "$SCAN_SELECTED_PATH"
                return $?
                ;;
            phpstan)
                scan_run_selected_action "$_opt"
                return $?
                ;;
            "test PR")
                scan_run_selected_action "$_opt"
                return $?
                ;;
            *)
                warp_message_warn "invalid option"
                ;;
        esac
    done
}

scan_resolve_path_argument() {
    local _input="$1"
    local _rel
    local _rel_status
    _rel=$(scan_rel_path_from_project "$_input")
    _rel_status=$?
    if [ $_rel_status -ne 0 ]; then
        [ $_rel_status -eq 1 ] && warp_message_error "path not found: $_input"
        return $_rel_status
    fi

    echo "$_rel"
}

scan_handle_path_scoped_action() {
    local _action="$1"
    local _rel
    shift

    scan_require_magento_context
    scan_ensure_output_dir

    case "$1" in
        "")
            scan_select_path_menu || { warp_message_info "audit cancelled"; return 0; }
            scan_run_selected_action "$_action" "$SCAN_SELECTED_PATH"
            return $?
            ;;
        --path)
            shift
            [ "$#" -eq 1 ] || { warp_message_error "${_action} --path requires exactly one argument"; return 1; }
            _rel=$(scan_resolve_path_argument "$1") || return $?
            scan_run_selected_action "$_action" "$_rel"
            return $?
            ;;
        *)
            warp_message_error "unknown option for ${_action}: $1"
            return 1
            ;;
    esac
}

scan_handle_phpstan_action() {
    local _level=""
    local _path=""
    local _rel

    scan_require_magento_context
    scan_ensure_output_dir

    while [ $# -gt 0 ]; do
        case "$1" in
            --level)
                shift
                [ $# -gt 0 ] || { warp_message_error "phpstan --level requires a value"; return 1; }
                [ -z "$_level" ] || { warp_message_error "phpstan --level can only be provided once"; return 1; }
                scan_validate_phpstan_level "$1" || return 1
                _level="$1"
                ;;
            --path)
                shift
                [ $# -gt 0 ] || { warp_message_error "phpstan --path requires a value"; return 1; }
                [ -z "$_path" ] || { warp_message_error "phpstan --path can only be provided once"; return 1; }
                _path="$1"
                ;;
            *)
                warp_message_error "unknown option for phpstan: $1"
                return 1
                ;;
        esac
        shift
    done

    if [ -n "$_path" ]; then
        _rel=$(scan_resolve_path_argument "$_path") || return $?
        scan_run_phpstan_on_path "$_rel" "$_level"
        return $?
    fi

    scan_run_phpstan_default "$_level"
    return $?
}

scan_command()
{
    local _rel
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
            scan_handle_path_scoped_action "phpcs" "$@"
            return $?
            ;;
        phpcbf)
            shift
            scan_handle_path_scoped_action "phpcbf" "$@"
            return $?
            ;;
        phpmd)
            shift
            scan_handle_path_scoped_action "phpmd" "$@"
            return $?
            ;;
        phpcompat)
            shift
            scan_handle_path_scoped_action "phpcompat" "$@"
            return $?
            ;;
        risky)
            shift
            scan_handle_path_scoped_action "risky" "$@"
            return $?
            ;;
        phpstan)
            shift
            scan_handle_phpstan_action "$@"
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
