#!/bin/bash

. "$PROJECTPATH/.warp/bin/hyva_help.sh"

HYVA_THEMES_FILE="$PROJECTPATH/app/design/hyva-themes.json"
HYVA_LOG_DIR="$PROJECTPATH/var/log/warp-hyva"

hyva_logs_ensure_dir() {
    mkdir -p "$HYVA_LOG_DIR" 2>/dev/null
}

hyva_ensure_gitignore_block() {
    local gitignore_file="$PROJECTPATH/.gitignore"
    [ -f "$gitignore_file" ] || touch "$gitignore_file"

    grep -q "^# HYVA / TAILWIND" "$gitignore_file" 2>/dev/null
    if [ $? -eq 0 ]; then
        return 0
    fi

    {
        echo ""
        echo "# HYVA / TAILWIND"
        echo "**/web/tailwind/node_modules/"
        echo "**/web/tailwind/generated/*"
        echo "!**/web/tailwind/generated/.gitkeep"
        echo "**/web/tailwind/.npm/"
        echo "**/web/tailwind/npm-debug.log*"
        echo "**/web/tailwind/yarn-error.log*"
        echo "/var/log/warp-hyva/"
        echo ""
    } >> "$gitignore_file"

    warp_message_info "added HYVA / TAILWIND block to .gitignore"
}

hyva_log_file_for_action() {
    local key="$1"
    local npm_action="$2"
    local ts="$(date +%Y%m%d-%H%M%S)"
    local safe_action="$(printf "%s" "$npm_action" | tr ' /:' '___' | tr -cd '[:alnum:]_-' )"
    local safe_key="$(printf "%s" "$key" | tr -cd '[:alnum:]_-' )"
    printf "%s/%s_%s_%s.log" "$HYVA_LOG_DIR" "$safe_key" "$safe_action" "$ts"
}

hyva_spinner_wait() {
    local pid="$1"
    local message="$2"
    local spin='|/-\'
    local i=0

    while kill -0 "$pid" 2>/dev/null; do
        i=$(( (i + 1) % 4 ))
        printf "\r%s [%c]" "$message" "${spin:$i:1}"
        sleep 0.1
    done
    printf "\r%*s\r" 100 ""
}

hyva_run_npm_with_log() {
    local key="$1"
    local npm_action="$2"
    local tailwind_path="$3"
    local log_file="$4"
    local run_as_root="$5"
    local cmd_display="npm --prefix \"$tailwind_path\" $npm_action"
    local start_ts
    local end_ts
    local elapsed
    local cmd_status
    local cmd_pid

    # watch must remain interactive/live; still tee to log.
    if [ "$npm_action" = "run watch" ]; then
        start_ts="$(date +%s)"
        warp_message_info "[$key] $cmd_display"
        warp_message_info "[$key] log: $log_file"
        warp_message ""
        warp_message_warn "# Watch mode running. Press Ctrl+C to stop."
        warp_message ""
        hyva_npm_exec "$tailwind_path" "$npm_action" "$run_as_root" 2>&1 | tee "$log_file"
        cmd_status=${PIPESTATUS[0]}
        end_ts="$(date +%s)"
        elapsed=$((end_ts - start_ts))

        if [ $cmd_status -eq 0 ]; then
            warp_message_ok "[$key] watch finished in ${elapsed}s"
            warp_message_info2 "[$key] log: $log_file"
        else
            warp_message_warn "[$key] watch stopped after ${elapsed}s"
            warp_message_info2 "[$key] log: $log_file"
        fi

        return $cmd_status
    fi

    start_ts="$(date +%s)"
    hyva_npm_exec "$tailwind_path" "$npm_action" "$run_as_root" > "$log_file" 2>&1 &
    cmd_pid=$!

    if [ -t 1 ]; then
        hyva_spinner_wait "$cmd_pid" "[$key] $npm_action"
    fi

    wait "$cmd_pid"
    cmd_status=$?
    end_ts="$(date +%s)"
    elapsed=$((end_ts - start_ts))

    if [ $cmd_status -eq 0 ]; then
        warp_message_ok "[$key] $npm_action completed in ${elapsed}s"
        warp_message_info2 "[$key] log: $log_file"
    else
        warp_message_error "[$key] $npm_action failed after ${elapsed}s"
        warp_message_error "[$key] log: $log_file"
        warp_message_warn "[$key] last log lines:"
        tail -n 20 "$log_file" 2>/dev/null
    fi

    return $cmd_status
}

hyva_php_container() {
    if [ -n "$WARP_HYVA_PHP_CONTAINER" ]; then
        docker exec -i "$WARP_HYVA_PHP_CONTAINER" php "$@"
        return $?
    fi

    if [ ! -f "$DOCKERCOMPOSEFILE" ]; then
        warp_message_error "file not found $(basename "$DOCKERCOMPOSEFILE")"
        warp_message_error "run: warp init"
        warp_message_error "or set WARP_HYVA_PHP_CONTAINER=<container_id> to use an existing php container"
        return 1
    fi

    if [ "$(warp_check_is_running)" = true ]; then
        docker-compose -f "$DOCKERCOMPOSEFILE" exec -T -u root php php "$@"
    else
        docker-compose -f "$DOCKERCOMPOSEFILE" run --no-deps --rm -T -u root php php "$@"
    fi
}

hyva_npm_command_from_action() {
    local tailwind_path="$1"
    local npm_action="$2"

    case "$npm_action" in
        install)
            printf 'npm\0--prefix\0%s\0install\0' "$tailwind_path"
            ;;
        "run generate")
            printf 'npm\0--prefix\0%s\0run\0generate\0' "$tailwind_path"
            ;;
        "run build")
            printf 'npm\0--prefix\0%s\0run\0build\0' "$tailwind_path"
            ;;
        "run watch")
            printf 'npm\0--prefix\0%s\0run\0watch\0' "$tailwind_path"
            ;;
        *)
            return 1
            ;;
    esac
}

hyva_validate_json_file() {
    if [ ! -f "$HYVA_THEMES_FILE" ]; then
        return 2
    fi

    cat "$HYVA_THEMES_FILE" | hyva_php_container -r '
        $raw = stream_get_contents(STDIN);
        $d = json_decode($raw, true);
        if (json_last_error() !== JSON_ERROR_NONE || !is_array($d)) { exit(3); }
        if (!isset($d["themes"]) || !is_array($d["themes"])) { exit(4); }
    '
}

hyva_require_json_file() {
    local context_action="$1"
    local status
    hyva_validate_json_file >/dev/null 2>&1
    status=$?
    case "$status" in
        0) return 0 ;;
        2)
            warp_message_error "file not found app/design/hyva-themes.json"
            warp_message_error "run: warp hyva discover"
            case "$context_action" in
                setup)
                    warp_message_warn "flow: discover -> setup"
                    ;;
                prepare)
                    warp_message_warn "flow: discover -> setup -> prepare"
                    ;;
                build)
                    warp_message_warn "flow: discover -> setup -> prepare -> build"
                    ;;
                watch)
                    warp_message_warn "flow: discover -> setup -> prepare -> watch"
                    ;;
                list)
                    warp_message_warn "flow: discover -> list"
                    ;;
            esac
            ;;
        *)
            warp_message_error "invalid JSON file app/design/hyva-themes.json"
            warp_message_error "run: warp hyva discover --dry-run and review output"
            ;;
    esac
    exit 1
}

hyva_theme_key_from_code() {
    local code="$1"
    local vendor="$(printf "%s" "$code" | cut -d '/' -f 1)"
    local theme="$(printf "%s" "$code" | cut -d '/' -f 2-)"
    local vendor_key="$(printf "%s" "$vendor" | sed -E 's/[^A-Za-z0-9]+/_/g')"
    local theme_key="$(printf "%s" "$theme" | awk -F'[^A-Za-z0-9]+' '
        {
            out="";
            for (i=1; i<=NF; i++) {
                if ($i == "") continue;
                first=toupper(substr($i,1,1));
                rest=tolower(substr($i,2));
                out=out first rest;
            }
            print out;
        }'
    )"
    printf "%s_%s" "$vendor_key" "$theme_key"
}

hyva_json_rows() {
    local mode="$1"
    cat "$HYVA_THEMES_FILE" | hyva_php_container -r '
        $mode=$argv[1];
        $raw=stream_get_contents(STDIN);
        $d=json_decode($raw, true);
        $themes = isset($d["themes"]) && is_array($d["themes"]) ? $d["themes"] : [];
        ksort($themes);
        foreach ($themes as $k => $t) {
            $enabled = !empty($t["enabled"]) ? "1" : "0";
            if ($mode === "enabled" && $enabled !== "1") { continue; }
            $code = isset($t["code"]) ? $t["code"] : "";
            $path = isset($t["path"]) ? $t["path"] : "";
            $tail = isset($t["tailwindPath"]) ? $t["tailwindPath"] : "";
            $pkg = isset($t["packageJson"]) ? $t["packageJson"] : "";
            echo $k . "\t" . $enabled . "\t" . $code . "\t" . $path . "\t" . $tail . "\t" . $pkg . PHP_EOL;
        }
    ' "$mode"
}

hyva_json_get_field() {
    local key="$1"
    local field="$2"
    cat "$HYVA_THEMES_FILE" | hyva_php_container -r '
        $k=$argv[1]; $field=$argv[2];
        $raw=stream_get_contents(STDIN);
        $d=json_decode($raw, true);
        if (!isset($d["themes"][$k])) { exit(2); }
        $v = isset($d["themes"][$k][$field]) ? $d["themes"][$k][$field] : "";
        if (is_bool($v)) { echo $v ? "1" : "0"; }
        else { echo (string)$v; }
    ' "$key" "$field"
}

hyva_check_runtime_preflight() {
    local _status

    if [ -n "$WARP_HYVA_PHP_CONTAINER" ]; then
        docker inspect --format '{{.State.Running}}' "$WARP_HYVA_PHP_CONTAINER" >/dev/null 2>&1 || {
            warp_message_error "container not found: $WARP_HYVA_PHP_CONTAINER"
            exit 1
        }

        _status=$(docker inspect --format '{{.State.Running}}' "$WARP_HYVA_PHP_CONTAINER" 2>/dev/null)
        if [ "$_status" != "true" ]; then
            warp_message_error "container not running: $WARP_HYVA_PHP_CONTAINER"
            exit 1
        fi

        docker exec -i "$WARP_HYVA_PHP_CONTAINER" sh -lc 'command -v npm >/dev/null 2>&1'
        _status=$?
    else
        if [ "$(warp_check_is_running)" = false ]; then
            warp_message_error "The containers are not running"
            warp_message_error "please, first run warp start"
            exit 1
        fi

        docker-compose -f "$DOCKERCOMPOSEFILE" exec -T php sh -lc 'command -v npm >/dev/null 2>&1'
        _status=$?
    fi

    if [ $_status -ne 0 ]; then
        warp_message_error "npm not found in php container"
        warp_message_error "install Node/NPM in php image or use a php image with npm"
        exit 1
    fi
}

hyva_npm_exec() {
    local tailwind_path="$1"
    local npm_action="$2"
    local run_as_root="$3"
    local -a npm_cmd

    if ! mapfile -d '' -t npm_cmd < <(hyva_npm_command_from_action "$tailwind_path" "$npm_action"); then
        warp_message_error "unsupported npm action: $npm_action"
        return 1
    fi

    if [ -n "$WARP_HYVA_PHP_CONTAINER" ]; then
        if [ "$run_as_root" = "1" ]; then
            docker exec -i -u root "$WARP_HYVA_PHP_CONTAINER" "${npm_cmd[@]}"
        else
            docker exec -i "$WARP_HYVA_PHP_CONTAINER" "${npm_cmd[@]}"
        fi
        return $?
    fi

    if [ "$run_as_root" = "1" ]; then
        docker-compose -f "$DOCKERCOMPOSEFILE" exec -T -u root php "${npm_cmd[@]}"
    else
        docker-compose -f "$DOCKERCOMPOSEFILE" exec -T php "${npm_cmd[@]}"
    fi
}

hyva_get_enabled_keys() {
    hyva_json_rows "enabled" | cut -f1
}

hyva_prompt_select_theme_key() {
    local keys_block="$1"
    local tmpfile="$(mktemp)"
    local count
    local idx
    local key
    local code
    local choice
    local selected
    printf "%s\n" "$keys_block" > "$tmpfile"

    count="$(wc -l < "$tmpfile" | tr -d ' ')"
    if [ "$count" -eq 0 ]; then
        rm -f "$tmpfile"
        return 1
    fi

    warp_message ""
    warp_message_info "Multiple themes found. Choose one:"
    idx=1
    while IFS= read -r key; do
        code="$(hyva_json_get_field "$key" "code" 2>/dev/null)"
        warp_message " $idx) $key ($code)"
        idx=$((idx + 1))
    done < "$tmpfile"
    warp_message ""

    while true; do
        printf "Select option [1-%s]: " "$count"
        read -r choice
        case "$choice" in
            ''|*[!0-9]*)
                warp_message_warn "invalid option"
                ;;
            *)
                if [ "$choice" -ge 1 ] && [ "$choice" -le "$count" ]; then
                    selected="$(sed -n "${choice}p" "$tmpfile")"
                    rm -f "$tmpfile"
                    printf "%s\n" "$selected"
                    return 0
                fi
                warp_message_warn "invalid option"
                ;;
        esac
    done
}

hyva_resolve_targets() {
    local action="$1"
    local explicit_key="$2"
    local keys
    local count

    if [ -n "$explicit_key" ]; then
        hyva_json_get_field "$explicit_key" "code" >/dev/null 2>&1
        if [ $? -ne 0 ]; then
            warp_message_error "theme not found: $explicit_key"
            return 1
        fi
        printf "%s\n" "$explicit_key"
        return 0
    fi

    keys="$(hyva_get_enabled_keys)"
    count="$(printf "%s\n" "$keys" | sed '/^$/d' | wc -l | tr -d ' ')"

    if [ "$count" -eq 0 ]; then
        warp_message_error "no enabled themes found in app/design/hyva-themes.json"
        return 1
    fi

    if [ "$action" = "watch" ]; then
        if [ "$count" -eq 1 ]; then
            printf "%s\n" "$keys"
            return 0
        fi
        hyva_prompt_select_theme_key "$keys"
        return $?
    fi

    printf "%s\n" "$keys"
}

hyva_validate_theme_paths() {
    local key="$1"
    local tailwind_path="$(hyva_json_get_field "$key" "tailwindPath" 2>/dev/null)"
    local package_json="$(hyva_json_get_field "$key" "packageJson" 2>/dev/null)"

    if [ -z "$tailwind_path" ] || [ -z "$package_json" ]; then
        warp_message_error "theme $key is missing tailwindPath or packageJson in hyva-themes.json"
        return 1
    fi

    if [ ! -d "$PROJECTPATH/$tailwind_path" ]; then
        warp_message_error "tailwindPath does not exist for theme $key: $tailwind_path"
        return 1
    fi

    if [ ! -f "$PROJECTPATH/$package_json" ]; then
        warp_message_error "packageJson does not exist for theme $key: $package_json"
        return 1
    fi

    return 0
}

hyva_require_theme_dependencies() {
    local key="$1"
    local consumer_action="$2"
    local tailwind_path="$(hyva_json_get_field "$key" "tailwindPath" 2>/dev/null)"
    local node_modules_path="$PROJECTPATH/$tailwind_path/node_modules"

    if [ ! -d "$node_modules_path" ]; then
        warp_message_error "dependencies not found for theme $key"
        warp_message_error "missing: $tailwind_path/node_modules"
        case "$consumer_action" in
            prepare)
                warp_message_warn "run first: ./warp hyva setup:$key"
                ;;
            build|watch)
                warp_message_warn "run first: ./warp hyva setup:$key"
                warp_message_warn "then run: ./warp hyva prepare:$key"
                ;;
        esac
        return 1
    fi

    return 0
}

hyva_fix_permissions_after_setup() {
    local key="$1"
    local tailwind_path="$(hyva_json_get_field "$key" "tailwindPath" 2>/dev/null)"
    [ -z "$tailwind_path" ] && return 1

    if [ -n "$WARP_HYVA_PHP_CONTAINER" ]; then
        docker exec -i -u root "$WARP_HYVA_PHP_CONTAINER" bash -lc "chown -R www-data:www-data \"$tailwind_path\" >/dev/null 2>&1 || true"
        return 0
    fi

    docker-compose -f "$DOCKERCOMPOSEFILE" exec -T -u root php bash -lc "chown -R www-data:www-data \"$tailwind_path\" >/dev/null 2>&1 || true"
    return 0
}

hyva_run_npm_action_for_key() {
    local key="$1"
    local npm_action="$2"
    local run_as_root="$3"
    local tailwind_path="$(hyva_json_get_field "$key" "tailwindPath" 2>/dev/null)"
    local log_file

    hyva_validate_theme_paths "$key" || return 1

    hyva_logs_ensure_dir
    log_file="$(hyva_log_file_for_action "$key" "$npm_action")"
    warp_message_info "[$key] npm --prefix $tailwind_path $npm_action"
    hyva_run_npm_with_log "$key" "$npm_action" "$tailwind_path" "$log_file" "$run_as_root"
    if [ $? -ne 0 ]; then
        warp_message_error "npm action failed for theme $key: $npm_action"
        return 1
    fi

    return 0
}

hyva_package_script_contains() {
    local key="$1"
    local script_name="$2"
    local needle="$3"
    local package_json="$(hyva_json_get_field "$key" "packageJson" 2>/dev/null)"

    [ -z "$package_json" ] && return 1
    [ ! -f "$PROJECTPATH/$package_json" ] && return 1

    cat "$PROJECTPATH/$package_json" | hyva_php_container -r '
        $script = $argv[1];
        $needle = $argv[2];
        $raw = stream_get_contents(STDIN);
        $d = json_decode($raw, true);
        if (!is_array($d) || !isset($d["scripts"]) || !is_array($d["scripts"]) || !isset($d["scripts"][$script])) {
            exit(2);
        }
        $value = (string)$d["scripts"][$script];
        if (stripos($value, $needle) !== false) {
            exit(0);
        }
        exit(1);
    ' "$script_name" "$needle"
}

hyva_build_has_generate_in_package() {
    key="$1"

    hyva_package_script_contains "$key" "prebuild" "generate" && return 0
    hyva_package_script_contains "$key" "build" "generate" && return 0

    return 1
}

hyva_discover() {
    dry_run=false
    merge=false
    set_default=""

    while [ $# -gt 0 ]; do
        case "$1" in
            --dry-run)
                dry_run=true
                ;;
            --merge)
                merge=true
                ;;
            --set-default)
                shift
                [ -z "$1" ] && warp_message_error "--set-default requires <themeKey>" && return 1
                set_default="$1"
                ;;
            -h|--help)
                hyva_discover_help_usage
                return 0
                ;;
            *)
                warp_message_error "unknown option: $1"
                hyva_discover_help_usage
                return 1
                ;;
        esac
        shift
    done

    scan_file="$(mktemp)"
    found=0
    for pkg in "$PROJECTPATH"/app/design/frontend/*/*/web/tailwind/package.json; do
        [ -f "$pkg" ] || continue
        found=1
        rel_pkg="${pkg#"$PROJECTPATH"/}"
        rel_tailwind="$(dirname "$rel_pkg")"
        code="${rel_pkg#app/design/frontend/}"
        code="${code%/web/tailwind/package.json}"
        key="$(hyva_theme_key_from_code "$code")"
        rel_path="app/design/frontend/$code"
        printf "%s\t%s\t%s\t%s\t%s\n" "$key" "$code" "$rel_path" "$rel_tailwind" "$rel_pkg" >> "$scan_file"
    done

    if [ "$found" -eq 0 ]; then
        warp_message_warn "no hyva themes found in app/design/frontend/*/*/web/tailwind/package.json"
    else
        hyva_ensure_gitignore_block
    fi

    merge_flag=0
    [ "$merge" = true ] && merge_flag=1

    existing_b64=""
    if [ "$merge" = true ] && [ -f "$HYVA_THEMES_FILE" ]; then
        existing_b64="$(base64 < "$HYVA_THEMES_FILE" | tr -d '\n')"
    fi
    scan_b64="$(base64 < "$scan_file" | tr -d '\n')"

    generated_json="$(printf "%s\n%s\n" "$existing_b64" "$scan_b64" | hyva_php_container -r '
        $merge = $argv[1] === "1";
        $setDefault = $argv[2];

        $stdin = stream_get_contents(STDIN);
        $parts = explode("\n", $stdin, 3);
        $existingB64 = isset($parts[0]) ? trim($parts[0]) : "";
        $scanB64 = isset($parts[1]) ? trim($parts[1]) : "";

        $existingRaw = "";
        if ($existingB64 !== "") {
            $decoded = base64_decode($existingB64, true);
            if ($decoded === false) { exit(2); }
            $existingRaw = $decoded;
        }

        $scanRaw = "";
        if ($scanB64 !== "") {
            $decoded = base64_decode($scanB64, true);
            if ($decoded === false) { exit(3); }
            $scanRaw = $decoded;
        }

        $newThemes = [];
        if ($scanRaw !== "") {
            $normalized = str_replace("\r", "\n", $scanRaw);
            $lines = explode("\n", trim($normalized));
            foreach ($lines as $line) {
                if ($line === "") { continue; }
                $parts = explode("\t", $line);
                if (count($parts) < 5) { continue; }
                [$key, $code, $path, $tailwindPath, $packageJson] = $parts;
                $newThemes[$key] = [
                    "code" => $code,
                    "area" => "frontend",
                    "path" => $path,
                    "tailwindPath" => $tailwindPath,
                    "packageJson" => $packageJson,
                    "enabled" => true,
                ];
            }
        }

        $existing = [];
        if ($merge && $existingRaw !== "") {
            $decoded = json_decode($existingRaw, true);
            if (is_array($decoded)) {
                $existing = $decoded;
            }
        }

        if ($merge && isset($existing["themes"]) && is_array($existing["themes"])) {
            foreach ($newThemes as $key => $themeData) {
                if (isset($existing["themes"][$key]) && is_array($existing["themes"][$key])) {
                    $newThemes[$key] = array_merge($existing["themes"][$key], $themeData);
                }
            }
        }

        ksort($newThemes);
        $keys = array_keys($newThemes);

        $default = "";
        if ($setDefault !== "" && isset($newThemes[$setDefault])) {
            $default = $setDefault;
        } elseif (isset($existing["default"]) && is_string($existing["default"]) && isset($newThemes[$existing["default"]])) {
            $default = $existing["default"];
        } elseif (!empty($keys)) {
            $default = $keys[0];
        }

        $meta = [
            "generatedBy" => "warp hyva discover",
            "generatedAt" => gmdate("c"),
        ];
        if ($merge && isset($existing["meta"]) && is_array($existing["meta"])) {
            $meta = array_merge($existing["meta"], $meta);
        }

        $payload = [
            "version" => 1,
            "default" => $default,
            "themes" => $newThemes,
            "meta" => $meta,
        ];

        echo json_encode($payload, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES) . PHP_EOL;
    ' "$merge_flag" "$set_default")"

    status=$?
    rm -f "$scan_file"
    if [ $status -ne 0 ] || [ -z "$generated_json" ]; then
        warp_message_error "failed to generate app/design/hyva-themes.json"
        return 1
    fi

    if [ "$dry_run" = true ]; then
        warp_message "$generated_json"
        warp_message_ok "dry-run completed"
        return 0
    fi

    mkdir -p "$(dirname "$HYVA_THEMES_FILE")"
    printf "%s\n" "$generated_json" > "$HYVA_THEMES_FILE"
    warp_message_ok "app/design/hyva-themes.json updated"
}

hyva_list() {
    hyva_require_json_file "list"
    default_key="$(cat "$HYVA_THEMES_FILE" | hyva_php_container -r '
        $raw=stream_get_contents(STDIN);
        $d=json_decode($raw, true);
        echo isset($d["default"]) ? $d["default"] : "";
    ')"

    warp_message ""
    warp_message_info "Hyva themes file: app/design/hyva-themes.json"
    warp_message "Default: $(warp_message_info "$default_key")"
    warp_message ""

    rows="$(hyva_json_rows "all")"
    if [ -z "$rows" ]; then
        warp_message_warn "No themes found."
        return 0
    fi

    while IFS=$'\t' read -r key enabled code path tailwind package; do
        [ -z "$key" ] && continue
        enabled_label="false"
        [ "$enabled" = "1" ] && enabled_label="true"
        warp_message_info "* $key"
        warp_message "  code:        $code"
        warp_message "  enabled:     $enabled_label"
        warp_message "  path:        $path"
        warp_message "  tailwind:    $tailwind"
        warp_message "  packageJson: $package"
        warp_message ""
    done <<EOF_ROWS
$rows
EOF_ROWS
}

hyva_prepare() {
    explicit_key="$1"
    shift

    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help)
                hyva_prepare_help_usage
                return 0
                ;;
            *)
                warp_message_error "unknown option: $1"
                hyva_prepare_help_usage
                return 1
                ;;
        esac
        shift
    done

    hyva_require_json_file "prepare"
    hyva_check_runtime_preflight

    targets="$(hyva_resolve_targets "prepare" "$explicit_key")" || return 1
    while IFS= read -r key; do
        [ -z "$key" ] && continue
        hyva_validate_theme_paths "$key" || return 1
        hyva_require_theme_dependencies "$key" "prepare" || return 1
        hyva_run_npm_action_for_key "$key" "run generate" "0" || return 1
    done <<EOF_TARGETS
$targets
EOF_TARGETS
}

hyva_setup() {
    explicit_key="$1"
    shift

    no_generate=false
    while [ $# -gt 0 ]; do
        case "$1" in
            --no-generate)
                no_generate=true
                ;;
            -h|--help)
                hyva_prepare_help_usage
                return 0
                ;;
            *)
                warp_message_error "unknown option: $1"
                hyva_prepare_help_usage
                return 1
                ;;
        esac
        shift
    done

    hyva_require_json_file "setup"
    hyva_check_runtime_preflight

    targets="$(hyva_resolve_targets "prepare" "$explicit_key")" || return 1
    while IFS= read -r key; do
        [ -z "$key" ] && continue
        hyva_run_npm_action_for_key "$key" "install" "1" || return 1
        if [ "$no_generate" = false ]; then
            hyva_run_npm_action_for_key "$key" "run generate" "1" || return 1
        fi
        hyva_fix_permissions_after_setup "$key"
        warp_message_info2 "[$key] ownership normalized for non-root commands"
    done <<EOF_TARGETS
$targets
EOF_TARGETS
}

hyva_build() {
    explicit_key="$1"
    shift
    [ $# -gt 0 ] && [ "$1" = "-h" -o "$1" = "--help" ] && hyva_build_help_usage && return 0

    hyva_require_json_file "build"
    hyva_check_runtime_preflight

    targets="$(hyva_resolve_targets "build" "$explicit_key")" || return 1
    while IFS= read -r key; do
        [ -z "$key" ] && continue
        hyva_validate_theme_paths "$key" || return 1
        hyva_require_theme_dependencies "$key" "build" || return 1

        if hyva_build_has_generate_in_package "$key"; then
            warp_message_info "[$key] package.json already includes generate in prebuild/build"
            warp_message_info "[$key] skipping explicit prepare step"
        else
            warp_message_info "[$key] package.json does not include generate in prebuild/build"
            warp_message_info "[$key] running prepare step before build"
            hyva_run_npm_action_for_key "$key" "run generate" "0" || return 1
        fi

        hyva_run_npm_action_for_key "$key" "run build" "0" || return 1
    done <<EOF_TARGETS
$targets
EOF_TARGETS
}

hyva_watch() {
    explicit_key="$1"
    shift
    [ $# -gt 0 ] && [ "$1" = "-h" -o "$1" = "--help" ] && hyva_watch_help_usage && return 0

    hyva_require_json_file "watch"
    hyva_check_runtime_preflight

    targets="$(hyva_resolve_targets "watch" "$explicit_key")" || return 1
    key="$(printf "%s\n" "$targets" | head -n 1)"
    [ -z "$key" ] && warp_message_error "no theme selected for watch" && return 1
    hyva_validate_theme_paths "$key" || return 1
    hyva_require_theme_dependencies "$key" "watch" || return 1
    hyva_run_npm_action_for_key "$key" "run watch" "0"
}

hyva_main() {
    case "$1" in
        discover)
            shift
            hyva_discover "$@"
        ;;
        list)
            shift
            hyva_list "$@"
        ;;
        prepare)
            shift
            hyva_prepare "" "$@"
        ;;
        prepare:*)
            explicit_key="${1#prepare:}"
            shift
            hyva_prepare "$explicit_key" "$@"
        ;;
        setup)
            shift
            hyva_setup "" "$@"
        ;;
        setup:*)
            explicit_key="${1#setup:}"
            shift
            hyva_setup "$explicit_key" "$@"
        ;;
        build)
            shift
            hyva_build "" "$@"
        ;;
        build:*)
            explicit_key="${1#build:}"
            shift
            hyva_build "$explicit_key" "$@"
        ;;
        watch)
            shift
            hyva_watch "" "$@"
        ;;
        watch:*)
            explicit_key="${1#watch:}"
            shift
            hyva_watch "$explicit_key" "$@"
        ;;
        -h|--help|"")
            hyva_help_usage
        ;;
        *)
            warp_message_error "unknown hyva command: $1"
            hyva_help_usage
            return 1
        ;;
    esac
}
