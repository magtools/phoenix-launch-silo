#!/bin/bash

. "$PROJECTPATH/.warp/bin/stress_help.sh"

STRESS_SETUP_DIR="$PROJECTPATH/.warp/setup/stress"
STRESS_TEMPLATE_DIR="$STRESS_SETUP_DIR/tpl"
STRESS_TEMPLATE_CONFIG_DIR="$STRESS_SETUP_DIR/config/stress"
STRESS_CONFIG_DIR="$PROJECTPATH/.warp/docker/config/stress"
STRESS_VAR_DIR="$PROJECTPATH/var/warp-stress"
STRESS_RUNS_DIR="$STRESS_VAR_DIR/runs"
STRESS_DATASETS_DIR="$STRESS_VAR_DIR/datasets"
STRESS_SITEMAP_DIR="$STRESS_VAR_DIR/sitemaps"
STRESS_COMPOSE_FILE="${DOCKERCOMPOSEFILESTRESS:-$PROJECTPATH/docker-compose-stress.yml}"
STRESS_CONFIG_FILE="${STRESSCFGFILE:-$PROJECTPATH/.stresscfg}"
STRESS_SERVICE_NAME="stress"
STRESS_ASSUME_YES=0
STRESS_DRY_RUN=0
STRESS_OVERRIDE_RATE=""
STRESS_OVERRIDE_DURATION=""
STRESS_OVERRIDE_VUS=""
STRESS_OVERRIDE_MAX_VUS=""
STRESS_OVERRIDE_STAGES=""

stress_print_kv() {
    printf '%-18s %s\n' "$1:" "$2"
}

stress_print_report_kv() {
    printf '  %-18s %s\n' "$1:" "$2"
}

stress_format_ms_seconds() {
    local _value="$1"

    [ -n "$_value" ] || return 1
    awk -v value="$_value" 'BEGIN { printf "%.2f", value / 1000 }'
}

stress_format_percent() {
    local _ratio="$1"

    [ -n "$_ratio" ] || return 1
    awk -v value="$_ratio" 'BEGIN { printf "%.2f%%", value * 100 }'
}

stress_count_lines() {
    local _file="$1"

    [ -f "$_file" ] || {
        echo "0"
        return 0
    }

    wc -l < "$_file" | awk '{print $1}'
}

stress_count_csv_items() {
    local _value="$1"

    [ -n "$_value" ] || {
        echo "0"
        return 0
    }

    printf '%s\n' "$_value" | tr ',' '\n' | sed '/^[[:space:]]*$/d' | wc -l | awk '{print $1}'
}

stress_is_positive_number() {
    local _value="$1"

    [ -n "$_value" ] || return 1
    printf '%s\n' "$_value" | awk 'BEGIN{ok=0} /^[0-9]+([.][0-9]+)?$/ {if (($1 + 0) > 0) ok=1} END{exit ok ? 0 : 1}'
}

stress_ga4_sessions_per_second() {
    local _iterations_rate="$1"
    local _pageviews_per_session="$2"

    if ! stress_is_positive_number "$_iterations_rate" || ! stress_is_positive_number "$_pageviews_per_session"; then
        return 1
    fi

    awk -v iter_rate="$_iterations_rate" -v pages="$_pageviews_per_session" 'BEGIN { printf "%.2f", iter_rate / pages }'
}

stress_ga4_pageviews_per_minute() {
    local _iterations_rate="$1"

    if ! stress_is_positive_number "$_iterations_rate"; then
        return 1
    fi

    awk -v value="$_iterations_rate" 'BEGIN { printf "%.2f", value * 60 }'
}

stress_ga4_pages_per_user_per_minute() {
    local _session_seconds="$1"
    local _pageviews_per_session="$2"

    if ! stress_is_positive_number "$_session_seconds" || ! stress_is_positive_number "$_pageviews_per_session"; then
        return 1
    fi

    awk -v seconds="$_session_seconds" -v pages="$_pageviews_per_session" 'BEGIN { printf "%.2f", pages / (seconds / 60) }'
}

stress_ga4_users_per_minute() {
    local _pageviews_per_minute="$1"
    local _pages_per_user_per_minute="$2"

    if ! stress_is_positive_number "$_pageviews_per_minute" || ! stress_is_positive_number "$_pages_per_user_per_minute"; then
        return 1
    fi

    awk -v views="$_pageviews_per_minute" -v pages="$_pages_per_user_per_minute" 'BEGIN { printf "%.2f", views / pages }'
}

stress_ga4_backend_rpm() {
    local _users_per_minute="$1"
    local _section_load_mode="$2"
    local _section_load_ratio="$3"
    local _effective_ratio="0"

    if ! stress_is_positive_number "$_users_per_minute"; then
        return 1
    fi

    case "${_section_load_mode:-never}" in
        always)
            _effective_ratio="1"
            ;;
        sampled)
            if stress_is_positive_number "${_section_load_ratio:-}"; then
                _effective_ratio="$_section_load_ratio"
            fi
            ;;
        never|"")
            _effective_ratio="0"
            ;;
    esac

    awk -v users="$_users_per_minute" -v ratio="$_effective_ratio" 'BEGIN { printf "%.2f", users * (1 + ratio) }'
}

stress_ga4_concurrent_users() {
    local _sessions_per_second="$1"
    local _session_seconds="$2"

    if ! stress_is_positive_number "$_sessions_per_second" || ! stress_is_positive_number "$_session_seconds"; then
        return 1
    fi

    awk -v sessions="$_sessions_per_second" -v seconds="$_session_seconds" 'BEGIN { printf "%.2f", sessions * seconds }'
}

stress_require_compose() {
    hash docker 2>/dev/null || {
        warp_message_error "warp stress requires docker"
        return 1
    }

    if ! hash docker-compose 2>/dev/null; then
        warp_compose_bootstrap || return 1
    fi

    return 0
}

stress_ensure_runtime_dirs() {
    mkdir -p "$STRESS_CONFIG_DIR" "$STRESS_VAR_DIR" "$STRESS_RUNS_DIR" "$STRESS_DATASETS_DIR" "$STRESS_SITEMAP_DIR" || {
        warp_message_error "could not create stress runtime directories"
        return 1
    }
}

stress_ensure_gitignore() {
    local _line=""

    [ -f "$GITIGNOREFILE" ] || : > "$GITIGNOREFILE" || {
        warp_message_error "could not create .gitignore"
        return 1
    }

    for _line in \
        "/.stresscfg" \
        "/$(basename "$STRESS_COMPOSE_FILE")" \
        "/var/warp-stress"
    do
        grep -qxF "$_line" "$GITIGNOREFILE" 2>/dev/null || echo "$_line" >> "$GITIGNOREFILE" || {
            warp_message_error "could not update .gitignore with $_line"
            return 1
        }
    done
}

stress_seed_config_dir() {
    local _source_file=""
    local _target_file=""

    [ -d "$STRESS_TEMPLATE_CONFIG_DIR" ] || {
        warp_message_error "stress seed directory not found: .warp/setup/stress/config/stress"
        return 1
    }

    mkdir -p "$STRESS_CONFIG_DIR" || return 1

    if [ ! -e "$STRESS_CONFIG_DIR/scenarios/catalog.js" ]; then
        warp_message_warn "stress config created: .warp/docker/config/stress"
    fi

    find "$STRESS_TEMPLATE_CONFIG_DIR" -type f | while read -r _source_file; do
        _target_file="$STRESS_CONFIG_DIR/${_source_file#"$STRESS_TEMPLATE_CONFIG_DIR"/}"
        [ -f "$_target_file" ] && continue
        mkdir -p "$(dirname "$_target_file")" || exit 1
        cp "$_source_file" "$_target_file" || exit 1
    done

    [ $? -eq 0 ] || {
        warp_message_error "could not seed stress config directory"
        return 1
    }
}

stress_ensure_compose_file() {
    local _template="$STRESS_TEMPLATE_DIR/docker-compose-stress.yml"

    [ -f "$STRESS_COMPOSE_FILE" ] && return 0
    [ -f "$_template" ] || {
        warp_message_error "stress compose template not found: .warp/setup/stress/tpl/docker-compose-stress.yml"
        return 1
    }

    cp "$_template" "$STRESS_COMPOSE_FILE" || {
        warp_message_error "could not create docker-compose-stress.yml"
        return 1
    }

    warp_message_warn "stress runtime created: docker-compose-stress.yml"
}

stress_ensure_config_file() {
    local _template="$STRESS_TEMPLATE_DIR/stresscfg"

    [ -f "$STRESS_CONFIG_FILE" ] && return 0
    [ -f "$_template" ] || {
        warp_message_error "stress config template not found: .warp/setup/stress/tpl/stresscfg"
        return 1
    }

    cp "$_template" "$STRESS_CONFIG_FILE" || {
        warp_message_error "could not create .stresscfg"
        return 1
    }

    warp_message_warn "stress config created: .stresscfg"
    warp_message_warn "edit STRESS_BASE_URL and target settings before running warp stress"
    return 0
}

stress_prepare_files() {
    stress_ensure_runtime_dirs || return 1
    stress_ensure_gitignore || return 1
    stress_seed_config_dir || return 1
    stress_ensure_compose_file || return 1
    stress_ensure_config_file || return 1
}

stress_prepare_runtime_only() {
    stress_ensure_runtime_dirs || return 1
    stress_ensure_gitignore || return 1
    stress_seed_config_dir || return 1
    stress_ensure_compose_file || return 1
    stress_ensure_config_file || true
}

stress_load_env_file() {
    local _file="$1"

    [ -f "$_file" ] || return 0
    # shellcheck disable=SC1090
    set -a
    . "$_file"
    set +a
}

stress_compose() {
    stress_require_compose || return 1
    docker-compose -f "$STRESS_COMPOSE_FILE" "$@"
}

stress_runtime_is_running() {
    local _id=""

    [ -f "$STRESS_COMPOSE_FILE" ] || return 1
    _id=$(stress_compose ps -q "$STRESS_SERVICE_NAME" 2>/dev/null)
    [ -n "$_id" ]
}

stress_profile_file() {
    local _profile="$1"
    printf '%s/profiles/%s.env\n' "$STRESS_CONFIG_DIR" "$_profile"
}

stress_profile_load() {
    local _profile="$1"
    local _profile_file=""

    _profile_file=$(stress_profile_file "$_profile")
    [ -f "$_profile_file" ] || {
        warp_message_error "stress profile not found: .warp/docker/config/stress/profiles/${_profile}.env"
        return 1
    }

    stress_load_env_file "$_profile_file"
}

stress_profiles_list() {
    local _profile_file=""
    local _profile_name=""

    [ -d "$STRESS_CONFIG_DIR/profiles" ] || {
        warp_message_warn "stress profiles directory not found. Run: warp stress start"
        return 1
    }

    for _profile_file in "$STRESS_CONFIG_DIR"/profiles/*.env; do
        [ -f "$_profile_file" ] || continue
        _profile_name=$(basename "$_profile_file" .env)
        warp_message " $_profile_name"
    done
}

stress_allowed_host() {
    local _host="$1"
    local _allowed="${STRESS_ALLOWED_HOSTS:-}"
    local _candidate=""

    [ -n "$_allowed" ] || return 0
    _allowed=$(printf '%s' "$_allowed" | tr ',' ' ')

    for _candidate in $_allowed; do
        [ "$_candidate" = "$_host" ] && return 0
    done

    return 1
}

stress_extract_host() {
    local _url="$1"
    printf '%s\n' "$_url" | sed -E 's#^[a-zA-Z]+://##' | cut -d '/' -f 1 | sed 's/.*@//' | cut -d ':' -f 1
}

stress_confirm_target() {
    local _host=""
    local _answer=""

    [ -n "${STRESS_BASE_URL:-}" ] || {
        warp_message_error "STRESS_BASE_URL is required in .stresscfg"
        return 1
    }

    case "${STRESS_BASE_URL:-}" in
        https://example.com|http://example.com|https://example.com/*|http://example.com/*)
            warp_message_error "STRESS_BASE_URL still points to example.com"
            warp_message_warn "edit .stresscfg before running stress"
            return 1
            ;;
    esac

    _host=$(stress_extract_host "$STRESS_BASE_URL")
    if ! stress_allowed_host "$_host"; then
        warp_message_error "target host is not allowed: $_host"
        warp_message_warn "review STRESS_ALLOWED_HOSTS in .stresscfg"
        return 1
    fi

    [ "${STRESS_TARGET_CLASS:-}" = "prod" ] || return 0
    [ "$STRESS_ASSUME_YES" = "1" ] && return 0

    warp_message_warn "productive target detected: $STRESS_BASE_URL"
    _answer=$(warp_question_ask_default "continue with stress target class=prod? $(warp_message_info [y/N]) " "N")
    case "$_answer" in
        y|Y|yes|YES)
            return 0
            ;;
        *)
            warp_message_warn "aborted"
            return 1
            ;;
    esac
}

stress_build_run_dir() {
    local _profile="$1"
    local _stamp_year=""
    local _stamp_month=""
    local _stamp_name=""
    local _relative=""

    _stamp_year=$(date +%Y)
    _stamp_month=$(date +%m)
    _stamp_name=$(date +"${_profile}-%d-%H%M")
    _relative="runs/${_stamp_year}/${_stamp_month}/${_stamp_name}"

    mkdir -p "$STRESS_VAR_DIR/$_relative" || return 1
    printf '%s\n' "$_relative"
}

stress_json_escape() {
    printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

stress_write_metadata() {
    local _host_dir="$1"
    local _container_dir="$2"

    cat > "$_host_dir/metadata.json" <<EOF
{
  "profile": "$(stress_json_escape "${STRESS_PROFILE_NAME:-unknown}")",
  "type": "$(stress_json_escape "${STRESS_TYPE:-run}")",
  "baseUrl": "$(stress_json_escape "${STRESS_BASE_URL:-}")",
  "targetClass": "$(stress_json_escape "${STRESS_TARGET_CLASS:-unknown}")",
  "script": "$(stress_json_escape "${STRESS_SCENARIO_SCRIPT:-scenarios/catalog.js}")",
  "executor": "$(stress_json_escape "${STRESS_EXECUTOR:-constant-arrival-rate}")",
  "rate": "$(stress_json_escape "${STRESS_RATE:-}")",
  "duration": "$(stress_json_escape "${STRESS_DURATION:-}")",
  "timeUnit": "$(stress_json_escape "${STRESS_TIME_UNIT:-}")",
  "preAllocatedVUs": "$(stress_json_escape "${STRESS_PRE_ALLOCATED_VUS:-}")",
  "maxVUs": "$(stress_json_escape "${STRESS_MAX_VUS:-}")",
  "stages": "$(stress_json_escape "${STRESS_STAGES:-}")",
  "scenarios": "$(stress_json_escape "${STRESS_SCENARIOS:-catalog=100}")",
  "searchPath": "$(stress_json_escape "${STRESS_SEARCH_PATH:-/catalogsearch/result/?q=}")",
  "datasetFile": "$(stress_json_escape "${STRESS_DATASET_FILE:-}")",
  "datasetCount": "$(stress_json_escape "$(stress_count_lines "${STRESS_DATASET_FILE_RESOLVED:-${STRESS_DATASET_FILE:-}}")")",
  "searchTermsFile": "$(stress_json_escape "${STRESS_SEARCH_TERMS_FILE_RESOLVED:-}")",
  "searchTermsCount": "$(stress_json_escape "$(stress_count_lines "${STRESS_SEARCH_TERMS_FILE_RESOLVED:-}")")",
  "urlRevisitRate": "$(stress_json_escape "${STRESS_URL_REVISIT_RATE:-}")",
  "customerSectionLoadMode": "$(stress_json_escape "${STRESS_CUSTOMER_SECTION_LOAD_MODE:-}")",
  "customerSectionLoadRatio": "$(stress_json_escape "${STRESS_CUSTOMER_SECTION_LOAD_RATIO:-}")",
  "customerSectionLoadPath": "$(stress_json_escape "${STRESS_CUSTOMER_SECTION_LOAD_PATH:-/customer/section/load}")",
  "ga4SessionSeconds": "$(stress_json_escape "${STRESS_GA4_SESSION_SECONDS:-}")",
  "ga4PageviewsPerSession": "$(stress_json_escape "${STRESS_GA4_PAGEVIEWS_PER_SESSION:-}")",
  "runDir": "$(stress_json_escape "$_container_dir")",
  "createdAt": "$(date -Iseconds)"
}
EOF
}

stress_write_runtime_env() {
    local _host_dir="$1"
    local _container_dir="$2"
    local _dataset_container="${STRESS_DATASET_FILE_CONTAINER:-}"

    cat > "$_host_dir/runtime.env" <<EOF
STRESS_PROFILE_NAME=${STRESS_PROFILE_NAME:-default}
STRESS_TYPE=${STRESS_TYPE:-run}
STRESS_BASE_URL=${STRESS_BASE_URL}
STRESS_TARGET_CLASS=${STRESS_TARGET_CLASS:-unknown}
STRESS_SCENARIO_SCRIPT=${STRESS_SCENARIO_SCRIPT:-scenarios/catalog.js}
STRESS_EXECUTOR=${STRESS_EXECUTOR:-constant-arrival-rate}
STRESS_RATE=${STRESS_RATE:-60}
STRESS_DURATION=${STRESS_DURATION:-1m}
STRESS_TIME_UNIT=${STRESS_TIME_UNIT:-1m}
STRESS_PRE_ALLOCATED_VUS=${STRESS_PRE_ALLOCATED_VUS:-10}
STRESS_MAX_VUS=${STRESS_MAX_VUS:-50}
STRESS_STAGES=${STRESS_STAGES:-}
STRESS_DATASET_FILE=${_dataset_container}
STRESS_URL_ORDER=${STRESS_URL_ORDER:-random}
STRESS_URL_REVISIT_RATE=${STRESS_URL_REVISIT_RATE:-1}
STRESS_SCENARIOS=${STRESS_SCENARIOS:-catalog=100}
STRESS_SEARCH_PATH=${STRESS_SEARCH_PATH:-/catalogsearch/result/?q=}
STRESS_SEARCH_TERMS=${STRESS_SEARCH_TERMS:-shirt,shoe}
STRESS_SEARCH_TERMS_FILE=${STRESS_SEARCH_TERMS_FILE_CONTAINER:-}
STRESS_CUSTOMER_SECTION_LOAD=${STRESS_CUSTOMER_SECTION_LOAD:-0}
STRESS_CUSTOMER_SECTION_LOAD_MODE=${STRESS_CUSTOMER_SECTION_LOAD_MODE:-}
STRESS_CUSTOMER_SECTION_LOAD_RATIO=${STRESS_CUSTOMER_SECTION_LOAD_RATIO:-}
STRESS_CUSTOMER_SECTION_LOAD_PATH=${STRESS_CUSTOMER_SECTION_LOAD_PATH:-/customer/section/load}
STRESS_GA4_SESSION_SECONDS=${STRESS_GA4_SESSION_SECONDS:-}
STRESS_GA4_PAGEVIEWS_PER_SESSION=${STRESS_GA4_PAGEVIEWS_PER_SESSION:-}
STRESS_RUN_DIR=${_container_dir}
EOF
}

stress_show_resolved_config() {
    warp_message ""
    warp_message_info "Resolved stress run:"
    warp_message " profile:            ${STRESS_PROFILE_NAME:-default}"
    warp_message " type:               ${STRESS_TYPE:-run}"
    warp_message " base url:           ${STRESS_BASE_URL:-}"
    warp_message " script:             ${STRESS_SCENARIO_SCRIPT:-scenarios/catalog.js}"
    warp_message " executor:           ${STRESS_EXECUTOR:-constant-arrival-rate}"
    warp_message " rate:               ${STRESS_RATE:-}"
    warp_message " duration:           ${STRESS_DURATION:-}"
    warp_message " time unit:          ${STRESS_TIME_UNIT:-}"
    warp_message " preAllocatedVUs:    ${STRESS_PRE_ALLOCATED_VUS:-}"
    warp_message " maxVUs:             ${STRESS_MAX_VUS:-}"
    warp_message " stages:             ${STRESS_STAGES:-}"
    warp_message " mix:                ${STRESS_SCENARIOS:-catalog=100}"
    warp_message " url revisit rate:   ${STRESS_URL_REVISIT_RATE:-1}"
    warp_message " search path:        ${STRESS_SEARCH_PATH:-/catalogsearch/result/?q=}"
    warp_message " dataset:            ${STRESS_DATASET_FILE:-}"
    warp_message " section load:       ${STRESS_CUSTOMER_SECTION_LOAD_MODE:-$([ "${STRESS_CUSTOMER_SECTION_LOAD:-0}" != "0" ] && printf '%s' always || printf '%s' never)}"
    [ -n "${STRESS_CUSTOMER_SECTION_LOAD_RATIO:-}" ] && warp_message " section load ratio: ${STRESS_CUSTOMER_SECTION_LOAD_RATIO}"
    case "${STRESS_CUSTOMER_SECTION_LOAD_MODE:-}" in
        always|sampled)
            warp_message " section load path:  ${STRESS_CUSTOMER_SECTION_LOAD_PATH:-/customer/section/load}"
            ;;
        *)
            [ "${STRESS_CUSTOMER_SECTION_LOAD:-0}" != "0" ] && warp_message " section load path:  ${STRESS_CUSTOMER_SECTION_LOAD_PATH:-/customer/section/load}"
            ;;
    esac
    [ -n "${STRESS_GA4_SESSION_SECONDS:-}" ] && warp_message " ga4 session sec:    ${STRESS_GA4_SESSION_SECONDS}"
    [ -n "${STRESS_GA4_PAGEVIEWS_PER_SESSION:-}" ] && warp_message " ga4 pages/session:  ${STRESS_GA4_PAGEVIEWS_PER_SESSION}"
    warp_message ""
}

stress_parse_run_flags() {
    STRESS_SELECTED_PROFILE="${STRESS_PROFILE:-catalog-load}"
    STRESS_OVERRIDE_RATE=""
    STRESS_OVERRIDE_DURATION=""
    STRESS_OVERRIDE_VUS=""
    STRESS_OVERRIDE_MAX_VUS=""
    STRESS_OVERRIDE_STAGES=""

    while [ $# -gt 0 ]; do
        case "$1" in
            --profile)
                STRESS_SELECTED_PROFILE="${2:-}"
                shift 2
                ;;
            --rate)
                STRESS_OVERRIDE_RATE="${2:-}"
                shift 2
                ;;
            --duration)
                STRESS_OVERRIDE_DURATION="${2:-}"
                shift 2
                ;;
            --vus)
                STRESS_OVERRIDE_VUS="${2:-}"
                shift 2
                ;;
            --max-vus)
                STRESS_OVERRIDE_MAX_VUS="${2:-}"
                shift 2
                ;;
            --stage)
                STRESS_OVERRIDE_STAGES="${2:-}"
                shift 2
                ;;
            --yes)
                STRESS_ASSUME_YES=1
                shift 1
                ;;
            --dry-run)
                STRESS_DRY_RUN=1
                shift 1
                ;;
            -h|--help)
                stress_help_usage
                return 1
                ;;
            *)
                warp_message_warn "unknown stress option: $1"
                return 1
                ;;
        esac
    done

    [ -n "$STRESS_SELECTED_PROFILE" ] || {
        warp_message_error "stress profile is required"
        return 1
    }
}

stress_apply_run_overrides() {
    [ -n "$STRESS_OVERRIDE_RATE" ] && STRESS_RATE="$STRESS_OVERRIDE_RATE"
    [ -n "$STRESS_OVERRIDE_DURATION" ] && STRESS_DURATION="$STRESS_OVERRIDE_DURATION"
    [ -n "$STRESS_OVERRIDE_VUS" ] && STRESS_PRE_ALLOCATED_VUS="$STRESS_OVERRIDE_VUS"
    [ -n "$STRESS_OVERRIDE_MAX_VUS" ] && STRESS_MAX_VUS="$STRESS_OVERRIDE_MAX_VUS"
    [ -n "$STRESS_OVERRIDE_STAGES" ] && STRESS_STAGES="$STRESS_OVERRIDE_STAGES"
}

stress_parse_profile_flag() {
    STRESS_SELECTED_PROFILE="${STRESS_PROFILE:-catalog-load}"

    while [ $# -gt 0 ]; do
        case "$1" in
            --profile)
                STRESS_SELECTED_PROFILE="${2:-}"
                shift 2
                ;;
            -h|--help)
                stress_help_usage
                return 1
                ;;
            *)
                warp_message_warn "unknown stress option: $1"
                return 1
                ;;
        esac
    done

    [ -n "$STRESS_SELECTED_PROFILE" ] || {
        warp_message_error "stress profile is required"
        return 1
    }
}

stress_summary_hint() {
    local _run_dir="$1"

    warp_message ""
    warp_message_info "Stress artifacts:"
    warp_message " $_run_dir"
    [ -f "$_run_dir/summary.json" ] && warp_message " summary: $_run_dir/summary.json"
    [ -f "$_run_dir/stdout.txt" ] && warp_message " stdout:  $_run_dir/stdout.txt"
    [ -f "$_run_dir/effective-script.js" ] && warp_message " script:  $_run_dir/effective-script.js"
    [ -f "$_run_dir/effective-profile.env" ] && warp_message " profile: $_run_dir/effective-profile.env"
    [ -f "$_run_dir/effective-dataset.txt" ] && warp_message " dataset: $_run_dir/effective-dataset.txt"
    [ -f "$_run_dir/effective-search-terms.txt" ] && warp_message " terms:   $_run_dir/effective-search-terms.txt"
    warp_message ""
}

stress_json_line() {
    local _file="$1"
    tr -d '\n' < "$_file" 2>/dev/null
}

stress_summary_metric_value() {
    local _file="$1"
    local _metric="$2"
    local _field="$3"
    local _value=""

    [ -f "$_file" ] || return 1
    _value=$(awk -v metric="\"${_metric}\"" -v field="\"${_field}\"" '
        index($0, metric ":") { inmetric=1; next }
        inmetric && /^        },?$/ { exit }
        inmetric && index($0, field ":") {
            value=$0
            sub(/^.*:[[:space:]]*/, "", value)
            sub(/[[:space:]]*,?[[:space:]]*$/, "", value)
            print value
            exit
        }
    ' "$_file")

    [ -n "$_value" ] || return 1
    printf '%s\n' "$_value"
}

stress_summary_thresholds_failed() {
    local _file="$1"

    [ -f "$_file" ] || return 1
    awk '
        /"thresholds":[[:space:]]*{/ {inblock=1; next}
        inblock && /}/ {inblock=0}
        inblock && /:[[:space:]]*true/ {count++}
        END {print count+0}
    ' "$_file"
}

stress_report_print() {
    local _run_dir="$1"
    local _summary_file="$_run_dir/summary.json"
    local _metadata_file="$_run_dir/metadata.json"
    local _profile=""
    local _type=""
    local _base_url=""
    local _executor=""
    local _rate=""
    local _duration=""
    local _scenarios=""
    local _dataset_count=""
    local _search_terms_count=""
    local _url_revisit_rate=""
    local _customer_section_load_mode=""
    local _customer_section_load_ratio=""
    local _customer_section_load_path=""
    local _ga4_session_seconds=""
    local _ga4_pageviews_per_session=""
    local _iterations=""
    local _iterations_rate=""
    local _http_reqs_count=""
    local _http_reqs_rate=""
    local _error_rate=""
    local _avg=""
    local _p90=""
    local _p95=""
    local _max=""
    local _failed_thresholds=""
    local _ga4_sessions_per_second=""
    local _ga4_pageviews_per_minute=""
    local _ga4_pages_per_user_per_minute=""
    local _ga4_users_per_minute=""
    local _ga4_backend_rpm=""

    [ -f "$_summary_file" ] || {
        warp_message_error "summary not found: $_summary_file"
        return 1
    }

    if [ -f "$_metadata_file" ]; then
        _profile=$(sed -n 's/.*"profile":[[:space:]]*"\([^"]*\)".*/\1/p' "$_metadata_file" | head -n 1)
        _type=$(sed -n 's/.*"type":[[:space:]]*"\([^"]*\)".*/\1/p' "$_metadata_file" | head -n 1)
        _base_url=$(sed -n 's/.*"baseUrl":[[:space:]]*"\([^"]*\)".*/\1/p' "$_metadata_file" | head -n 1)
        _executor=$(sed -n 's/.*"executor":[[:space:]]*"\([^"]*\)".*/\1/p' "$_metadata_file" | head -n 1)
        _rate=$(sed -n 's/.*"rate":[[:space:]]*"\([^"]*\)".*/\1/p' "$_metadata_file" | head -n 1)
        _duration=$(sed -n 's/.*"duration":[[:space:]]*"\([^"]*\)".*/\1/p' "$_metadata_file" | head -n 1)
        _scenarios=$(sed -n 's/.*"scenarios":[[:space:]]*"\([^"]*\)".*/\1/p' "$_metadata_file" | head -n 1)
        _dataset_count=$(sed -n 's/.*"datasetCount":[[:space:]]*"\([^"]*\)".*/\1/p' "$_metadata_file" | head -n 1)
        _search_terms_count=$(sed -n 's/.*"searchTermsCount":[[:space:]]*"\([^"]*\)".*/\1/p' "$_metadata_file" | head -n 1)
        _url_revisit_rate=$(sed -n 's/.*"urlRevisitRate":[[:space:]]*"\([^"]*\)".*/\1/p' "$_metadata_file" | head -n 1)
        _customer_section_load_mode=$(sed -n 's/.*"customerSectionLoadMode":[[:space:]]*"\([^"]*\)".*/\1/p' "$_metadata_file" | head -n 1)
        _customer_section_load_ratio=$(sed -n 's/.*"customerSectionLoadRatio":[[:space:]]*"\([^"]*\)".*/\1/p' "$_metadata_file" | head -n 1)
        _customer_section_load_path=$(sed -n 's/.*"customerSectionLoadPath":[[:space:]]*"\([^"]*\)".*/\1/p' "$_metadata_file" | head -n 1)
        _ga4_session_seconds=$(sed -n 's/.*"ga4SessionSeconds":[[:space:]]*"\([^"]*\)".*/\1/p' "$_metadata_file" | head -n 1)
        _ga4_pageviews_per_session=$(sed -n 's/.*"ga4PageviewsPerSession":[[:space:]]*"\([^"]*\)".*/\1/p' "$_metadata_file" | head -n 1)
    fi

    _iterations=$(stress_summary_metric_value "$_summary_file" "iterations" "count")
    _iterations_rate=$(stress_summary_metric_value "$_summary_file" "iterations" "rate")
    _http_reqs_count=$(stress_summary_metric_value "$_summary_file" "http_reqs" "count")
    _http_reqs_rate=$(stress_summary_metric_value "$_summary_file" "http_reqs" "rate")
    _error_rate=$(stress_summary_metric_value "$_summary_file" "http_req_failed" "value")
    _avg=$(stress_summary_metric_value "$_summary_file" "http_req_duration" "avg")
    _p90=$(stress_summary_metric_value "$_summary_file" "http_req_duration" "p(90)")
    _p95=$(stress_summary_metric_value "$_summary_file" "http_req_duration" "p(95)")
    _max=$(stress_summary_metric_value "$_summary_file" "http_req_duration" "max")
    _failed_thresholds=$(stress_summary_thresholds_failed "$_summary_file")

    if stress_is_positive_number "${_ga4_session_seconds:-}" && stress_is_positive_number "${_ga4_pageviews_per_session:-}" && stress_is_positive_number "${_iterations_rate:-}"; then
        _ga4_sessions_per_second=$(stress_ga4_sessions_per_second "$_iterations_rate" "$_ga4_pageviews_per_session")
        _ga4_pageviews_per_minute=$(stress_ga4_pageviews_per_minute "$_iterations_rate")
        _ga4_pages_per_user_per_minute=$(stress_ga4_pages_per_user_per_minute "$_ga4_session_seconds" "$_ga4_pageviews_per_session")
        _ga4_users_per_minute=$(stress_ga4_users_per_minute "$_ga4_pageviews_per_minute" "$_ga4_pages_per_user_per_minute")
        _ga4_backend_rpm=$(stress_ga4_backend_rpm "$_ga4_users_per_minute" "${_customer_section_load_mode:-}" "${_customer_section_load_ratio:-}")
    fi

    warp_message ""
    warp_message "Resultado:"
    [ -n "$_profile" ] && stress_print_report_kv "profile" "$_profile"
    [ -n "$_duration" ] && stress_print_report_kv "duration" "$_duration"
    [ -n "$_rate" ] && stress_print_report_kv "rate" "$_rate"
    [ -n "$_url_revisit_rate" ] && stress_print_report_kv "url revisit rate" "$_url_revisit_rate"
    case "$_customer_section_load_mode" in
        sampled)
            stress_print_report_kv "section load" "${_customer_section_load_mode} ${_customer_section_load_ratio}"
            ;;
        always|never)
            stress_print_report_kv "section load" "${_customer_section_load_mode}"
            ;;
        *)
            [ -n "$_customer_section_load_mode" ] && stress_print_report_kv "section load" "$_customer_section_load_mode"
            ;;
    esac

    warp_message ""
    warp_message "Métricas principales:"
    [ -n "$_iterations" ] && stress_print_report_kv "iterations" "$_iterations"
    [ -n "$_http_reqs_count" ] && stress_print_report_kv "dropped_iterations" "$(stress_summary_metric_value "$_summary_file" "dropped_iterations" "count")"
    [ -n "$_http_reqs_count" ] && stress_print_report_kv "http_reqs" "$_http_reqs_count"
    [ -n "$_error_rate" ] && stress_print_report_kv "http_req_failed" "$(stress_format_percent "$_error_rate")"
    [ -n "$_avg" ] && stress_print_report_kv "avg" "$(stress_format_ms_seconds "$_avg")s"
    [ -n "$_p90" ] && stress_print_report_kv "p90" "$(stress_format_ms_seconds "$_p90")s"
    [ -n "$_p95" ] && stress_print_report_kv "p95" "$(stress_format_ms_seconds "$_p95")s"
    stress_print_report_kv "thresholds failed" "${_failed_thresholds:-0}"

    warp_message ""
    warp_message "Equivalencia GA4 de esta corrida:"
    [ -n "$_ga4_users_per_minute" ] && stress_print_report_kv "ga4 users/min" "$_ga4_users_per_minute"
    [ -n "$_ga4_backend_rpm" ] && stress_print_report_kv "backend rpm est" "$_ga4_backend_rpm"
    warp_message ""
    stress_print_kv "artifacts" "$_run_dir"
    warp_message ""
}

stress_latest_run_dir() {
    find "$STRESS_RUNS_DIR" -mindepth 3 -maxdepth 3 -type d 2>/dev/null | sort | tail -n 1
}

stress_copy_effective_inputs() {
    local _run_host_dir="$1"
    local _script_host="$STRESS_CONFIG_DIR/${STRESS_SCENARIO_SCRIPT:-scenarios/catalog.js}"
    local _profile_host=""

    [ -f "$_script_host" ] && cp "$_script_host" "$_run_host_dir/effective-script.js" >/dev/null 2>&1 || true
    [ -f "${STRESS_DATASET_FILE_RESOLVED:-${STRESS_DATASET_FILE:-}}" ] && cp "${STRESS_DATASET_FILE_RESOLVED:-${STRESS_DATASET_FILE:-}}" "$_run_host_dir/effective-dataset.txt" >/dev/null 2>&1 || true
    [ -f "${STRESS_SEARCH_TERMS_FILE_RESOLVED:-}" ] && cp "${STRESS_SEARCH_TERMS_FILE_RESOLVED}" "$_run_host_dir/effective-search-terms.txt" >/dev/null 2>&1 || true
    _profile_host=$(stress_profile_file "${STRESS_SELECTED_PROFILE:-}")
    [ -f "$_profile_host" ] && cp "$_profile_host" "$_run_host_dir/effective-profile.env" >/dev/null 2>&1 || true
}

stress_validate_profile() {
    local _profile="$1"
    local _script_host=""
    local _status=0

    stress_prepare_files || return 1
    stress_load_env_file "$STRESS_CONFIG_FILE"
    stress_profile_load "$_profile" || return 1

    warp_message ""
    warp_message_info "Stress validation"

    if [ -z "${STRESS_BASE_URL:-}" ]; then
        stress_print_kv "base url" "[missing]"
        _status=1
    elif [ "${STRESS_BASE_URL#*example.com}" != "$STRESS_BASE_URL" ]; then
        stress_print_kv "base url" "[placeholder] $STRESS_BASE_URL"
        _status=1
    else
        stress_print_kv "base url" "$STRESS_BASE_URL"
    fi

    stress_print_kv "profile" "${STRESS_PROFILE_NAME:-$_profile}"
    stress_print_kv "type" "${STRESS_TYPE:-unknown}"
    stress_print_kv "executor" "${STRESS_EXECUTOR:-constant-arrival-rate}"

    _script_host="$STRESS_CONFIG_DIR/${STRESS_SCENARIO_SCRIPT:-scenarios/catalog.js}"
    if [ -f "$_script_host" ]; then
        stress_print_kv "script" "$_script_host"
    else
        stress_print_kv "script" "[missing] $_script_host"
        _status=1
    fi

    if [ -n "${STRESS_ALLOWED_HOSTS:-}" ] && [ -n "${STRESS_BASE_URL:-}" ]; then
        if stress_allowed_host "$(stress_extract_host "$STRESS_BASE_URL")"; then
            stress_print_kv "allowed hosts" "ok"
        else
            stress_print_kv "allowed hosts" "[blocked]"
            _status=1
        fi
    else
        stress_print_kv "allowed hosts" "[not set]"
    fi

    if [ -n "${STRESS_DATASET_FILE:-}" ]; then
        if [ -f "$STRESS_DATASET_FILE" ] && [ -s "$STRESS_DATASET_FILE" ]; then
            stress_print_kv "dataset" "$STRESS_DATASET_FILE"
        else
            stress_print_kv "dataset" "[missing] $STRESS_DATASET_FILE"
        fi
    else
        stress_print_kv "dataset" "[auto] sitemap-urls.txt"
    fi

    stress_print_kv "mix" "${STRESS_SCENARIOS:-catalog=100}"
    stress_print_kv "url revisit rate" "${STRESS_URL_REVISIT_RATE:-1}"
    stress_print_kv "section load" "${STRESS_CUSTOMER_SECTION_LOAD_MODE:-$([ "${STRESS_CUSTOMER_SECTION_LOAD:-0}" != "0" ] && printf '%s' always || printf '%s' never)}"
    [ -n "${STRESS_CUSTOMER_SECTION_LOAD_RATIO:-}" ] && stress_print_kv "section load ratio" "${STRESS_CUSTOMER_SECTION_LOAD_RATIO}"
    case "${STRESS_CUSTOMER_SECTION_LOAD_MODE:-}" in
        always|sampled)
            stress_print_kv "section load path" "${STRESS_CUSTOMER_SECTION_LOAD_PATH:-/customer/section/load}"
            ;;
        *)
            [ "${STRESS_CUSTOMER_SECTION_LOAD:-0}" != "0" ] && stress_print_kv "section load path" "${STRESS_CUSTOMER_SECTION_LOAD_PATH:-/customer/section/load}"
            ;;
    esac
    if [ -n "${STRESS_GA4_SESSION_SECONDS:-}" ]; then
        stress_print_kv "ga4 session sec" "${STRESS_GA4_SESSION_SECONDS}"
    fi
    if [ -n "${STRESS_GA4_PAGEVIEWS_PER_SESSION:-}" ]; then
        stress_print_kv "ga4 pages/session" "${STRESS_GA4_PAGEVIEWS_PER_SESSION}"
    fi
    if [ "${STRESS_SCENARIO_SCRIPT:-}" = "scenarios/catalog-search.js" ]; then
        if [ -n "${STRESS_SEARCH_TERMS_FILE:-}" ] && [ -f "$STRESS_SEARCH_TERMS_FILE" ] && [ -s "$STRESS_SEARCH_TERMS_FILE" ]; then
            stress_print_kv "search terms file" "${STRESS_SEARCH_TERMS_FILE}"
        elif [ -n "${STRESS_SEARCH_TERMS:-}" ]; then
            stress_print_kv "search terms" "${STRESS_SEARCH_TERMS}"
        else
            stress_print_kv "search terms" "[missing]"
            _status=1
        fi
        stress_print_kv "search path" "${STRESS_SEARCH_PATH:-/catalogsearch/result/?q=}"
    fi

    [ "$_status" -eq 0 ] && warp_message_ok "stress validation passed"
    [ "$_status" -ne 0 ] && warp_message_error "stress validation failed"
    warp_message ""
    return "$_status"
}

stress_start() {
    stress_prepare_runtime_only || return 1
    stress_require_compose || return 1

    stress_compose up -d || return 1
    warp_message_ok "stress runtime started"
}

stress_stop() {
    local _mode="${1:-}"

    [ -f "$STRESS_COMPOSE_FILE" ] || {
        warp_message_warn "stress runtime is not configured yet"
        return 0
    }

    stress_require_compose || return 1

    if [ "$_mode" = "--hard" ]; then
        stress_compose rm -f -s "$STRESS_SERVICE_NAME"
    else
        stress_compose stop
    fi
}

stress_stop_managed_quiet() {
    [ -f "$STRESS_COMPOSE_FILE" ] || return 0
    stress_require_compose || return 0
    stress_runtime_is_running || return 0

    if [ "$1" = "--hard" ]; then
        stress_compose rm -f -s "$STRESS_SERVICE_NAME" >/dev/null 2>&1 || true
    else
        stress_compose stop >/dev/null 2>&1 || true
    fi
}

stress_status() {
    [ -f "$STRESS_COMPOSE_FILE" ] || {
        warp_message_warn "stress runtime not configured. Run: warp stress start"
        return 1
    }

    stress_require_compose || return 1
    stress_compose ps
}

stress_logs() {
    stress_require_compose || return 1
    [ -f "$STRESS_COMPOSE_FILE" ] || {
        warp_message_warn "stress runtime not configured. Run: warp stress start"
        return 1
    }

    if [ "$1" = "-f" ]; then
        stress_compose logs -f "$STRESS_SERVICE_NAME"
    else
        stress_compose logs "$STRESS_SERVICE_NAME"
    fi
}

stress_sitemap_url() {
    if [ -n "${STRESS_SITEMAP_URL:-}" ]; then
        printf '%s\n' "$STRESS_SITEMAP_URL"
        return 0
    fi

    [ -n "${STRESS_BASE_URL:-}" ] || return 1
    printf '%s/sitemap.xml\n' "${STRESS_BASE_URL%/}"
}

stress_url_to_target_host() {
    local _url="$1"
    local _base="${STRESS_BASE_URL%/}"
    local _path=""

    case "$_url" in
        http://*|https://*)
            _path=$(printf '%s\n' "$_url" | sed -E 's#^[a-zA-Z]+://[^/]+##')
            printf '%s%s\n' "$_base" "$_path"
            ;;
        /*)
            printf '%s%s\n' "$_base" "$_url"
            ;;
        *)
            printf '%s/%s\n' "$_base" "$_url"
            ;;
    esac
}

stress_fetch_url_to_file() {
    local _url="$1"
    local _output="$2"

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$_url" -o "$_output" || return 1
        return 0
    fi

    if command -v wget >/dev/null 2>&1; then
        wget -qO "$_output" "$_url" || return 1
        return 0
    fi

    warp_message_error "curl or wget is required to download the sitemap"
    return 1
}

stress_sitemap_extract_locs() {
    local _xml_file="$1"
    sed -n 's#.*<loc>\(.*\)</loc>.*#\1#p' "$_xml_file"
}

stress_sitemap_download() {
    local _target_url=""
    local _target_xml="$STRESS_SITEMAP_DIR/sitemap.xml"
    local _target_txt="$STRESS_DATASETS_DIR/sitemap-urls.txt"
    local _max_age_days="${STRESS_SITEMAP_CACHE_DAYS:-7}"
    local _child_url=""
    local _child_fetch_url=""
    local _child_index=0
    local _child_xml=""
    local _tmp_urls="$STRESS_DATASETS_DIR/sitemap-urls.raw.txt"

    _target_url=$(stress_sitemap_url) || {
        warp_message_error "STRESS_SITEMAP_URL or STRESS_BASE_URL is required"
        return 1
    }

    if [ "$1" != "--refresh" ] && [ -f "$_target_xml" ]; then
        if find "$_target_xml" -mtime "-${_max_age_days}" -print -quit 2>/dev/null | grep -q .; then
            warp_message "using cached sitemap: var/warp-stress/sitemaps/sitemap.xml"
        else
            rm -f "$_target_xml"
        fi
    fi

    if [ ! -f "$_target_xml" ]; then
        warp_message "fetching sitemap: $_target_url"
        stress_fetch_url_to_file "$_target_url" "$_target_xml" || {
            warp_message_error "could not download sitemap: $_target_url"
            return 1
        }
    fi

    : > "$_tmp_urls" || {
        warp_message_error "could not initialize sitemap dataset"
        return 1
    }

    if grep -q '<sitemapindex' "$_target_xml" 2>/dev/null; then
        while IFS= read -r _child_url; do
            [ -n "$_child_url" ] || continue
            _child_index=$((_child_index + 1))
            _child_fetch_url=$(stress_url_to_target_host "$_child_url")
            _child_xml="$STRESS_SITEMAP_DIR/sitemap-child-${_child_index}.xml"
            stress_fetch_url_to_file "$_child_fetch_url" "$_child_xml" || {
                warp_message_error "could not download child sitemap: $_child_fetch_url"
                return 1
            }
            stress_sitemap_extract_locs "$_child_xml" >> "$_tmp_urls" || return 1
        done < <(stress_sitemap_extract_locs "$_target_xml")
    else
        stress_sitemap_extract_locs "$_target_xml" > "$_tmp_urls" || {
            warp_message_error "could not parse sitemap XML"
            return 1
        }
    fi

    sed '/^[[:space:]]*$/d' "$_tmp_urls" | while IFS= read -r _child_url; do
        stress_url_to_target_host "$_child_url"
    done > "$_target_txt" || {
        warp_message_error "could not normalize sitemap URLs"
        return 1
    }

    if [ ! -s "$_target_txt" ]; then
        warp_message_error "sitemap dataset is empty"
        return 1
    fi

    warp_message_ok "sitemap dataset ready: var/warp-stress/datasets/sitemap-urls.txt"
}

stress_run_prepare_dataset() {
    local _dataset_host=""
    local _resolved_file="$STRESS_DATASETS_DIR/sitemap-urls.resolved.txt"

    _dataset_host="${STRESS_DATASET_FILE:-$STRESS_DATASETS_DIR/sitemap-urls.txt}"
    STRESS_DATASET_FILE="$_dataset_host"

    if [ ! -f "$_dataset_host" ] || [ ! -s "$_dataset_host" ]; then
        stress_sitemap_download || return 1
    fi

    cp "$_dataset_host" "$_resolved_file" || {
        warp_message_error "could not prepare sitemap dataset"
        return 1
    }

    STRESS_DATASET_FILE_RESOLVED="$_resolved_file"
    STRESS_DATASET_FILE_CONTAINER="/opt/warp-stress/var/datasets/$(basename "$_resolved_file")"

    if [ "${STRESS_SCENARIO_SCRIPT:-}" = "scenarios/catalog-search.js" ]; then
        local _search_terms_resolved="$STRESS_DATASETS_DIR/search-terms.resolved.txt"

        if [ -n "${STRESS_SEARCH_TERMS_FILE:-}" ] && [ -f "$STRESS_SEARCH_TERMS_FILE" ]; then
            cp "$STRESS_SEARCH_TERMS_FILE" "$_search_terms_resolved" || {
                warp_message_error "could not prepare search terms dataset"
                return 1
            }
        elif [ -n "${STRESS_SEARCH_TERMS:-}" ]; then
            printf '%s\n' "$STRESS_SEARCH_TERMS" | tr ',' '\n' | sed '/^[[:space:]]*$/d' > "$_search_terms_resolved" || {
                warp_message_error "could not write search terms dataset"
                return 1
            }
        else
            warp_message_error "search profile requires STRESS_SEARCH_TERMS or STRESS_SEARCH_TERMS_FILE"
            return 1
        fi

        STRESS_SEARCH_TERMS_FILE_RESOLVED="$_search_terms_resolved"
        STRESS_SEARCH_TERMS_FILE_CONTAINER="/opt/warp-stress/var/datasets/$(basename "$_search_terms_resolved")"
    fi
}

stress_datasets_status() {
    local _sitemap_file="$STRESS_DATASETS_DIR/sitemap-urls.txt"
    local _search_terms_file=""
    local _profile_name=""

    stress_prepare_runtime_only || return 1
    stress_load_env_file "$STRESS_CONFIG_FILE"
    _profile_name="${STRESS_PROFILE:-}"
    if [ -n "$_profile_name" ] && [ -f "$(stress_profile_file "$_profile_name")" ]; then
        stress_profile_load "$_profile_name" || return 1
    fi
    _search_terms_file="${STRESS_SEARCH_TERMS_FILE:-$STRESS_DATASETS_DIR/search-terms.txt}"

    warp_message ""
    warp_message_info "Stress datasets"
    stress_print_kv "sitemap urls" "$_sitemap_file ($(stress_count_lines "$_sitemap_file") lines)"
    if [ -n "${STRESS_SEARCH_TERMS_FILE:-}" ] && [ -f "$_search_terms_file" ]; then
        stress_print_kv "search terms" "$_search_terms_file ($(stress_count_lines "$_search_terms_file") lines)"
    else
        stress_print_kv "search terms" "inline ($(stress_count_csv_items "${STRESS_SEARCH_TERMS:-}") items)"
    fi
    warp_message ""
}

stress_execute_profile() {
    local _profile="$1"
    local _run_relative=""
    local _run_host_dir=""
    local _run_container_dir=""
    local _script_container=""
    local _status=0
    local _stdout_file=""

    stress_prepare_files || return 1
    stress_load_env_file "$STRESS_CONFIG_FILE"
    stress_profile_load "$_profile" || return 1
    stress_apply_run_overrides
    stress_confirm_target || return 1
    stress_run_prepare_dataset || return 1

    if ! stress_runtime_is_running; then
        warp_message_error "stress runtime is not running. Run: warp stress start"
        return 1
    fi

    stress_show_resolved_config
    if [ "$STRESS_DRY_RUN" = "1" ]; then
        warp_message_info "dry-run requested, nothing executed"
        return 0
    fi

    _run_relative=$(stress_build_run_dir "${STRESS_PROFILE_NAME:-$_profile}") || {
        warp_message_error "could not create stress run directory"
        return 1
    }

    _run_host_dir="$STRESS_VAR_DIR/$_run_relative"
    _run_container_dir="/opt/warp-stress/var/$_run_relative"
    _stdout_file="$_run_host_dir/stdout.txt"
    _script_container="/opt/warp-stress/config/${STRESS_SCENARIO_SCRIPT:-scenarios/catalog.js}"

    stress_write_runtime_env "$_run_host_dir" "$_run_container_dir"
    stress_write_metadata "$_run_host_dir" "$_run_container_dir"
    stress_copy_effective_inputs "$_run_host_dir"

    stress_compose exec -T "$STRESS_SERVICE_NAME" sh -lc \
        "set -a; . '$_run_container_dir/runtime.env'; set +a; k6 run --summary-export '$_run_container_dir/summary.json' '$_script_container'" \
        >"$_stdout_file" 2>&1
    _status=$?

    cat "$_stdout_file"
    if [ -f "$_run_host_dir/summary.json" ]; then
        stress_report_print "$_run_host_dir"
    fi
    stress_summary_hint "$_run_host_dir"
    return "$_status"
}

stress_warmup() {
    STRESS_SELECTED_PROFILE="catalog-warm"
    stress_parse_run_flags "$@" || return 1
    stress_execute_profile "$STRESS_SELECTED_PROFILE"
}

stress_run() {
    stress_parse_run_flags "$@" || return 1
    stress_execute_profile "$STRESS_SELECTED_PROFILE"
}

stress_profiles() {
    stress_prepare_runtime_only || return 1
    warp_message ""
    warp_message_info "Available stress profiles"
    stress_profiles_list
    warp_message ""
}

stress_validate() {
    stress_parse_profile_flag "$@" || return 1
    stress_validate_profile "$STRESS_SELECTED_PROFILE"
}

stress_report() {
    local _target="${1:-latest}"
    local _run_dir=""

    if [ "$_target" = "latest" ]; then
        _run_dir=$(stress_latest_run_dir)
        [ -n "$_run_dir" ] || {
            warp_message_error "no stress runs found in var/warp-stress/runs"
            return 1
        }
    else
        _run_dir="$_target"
        case "$_run_dir" in
            /*) ;;
            *) _run_dir="$PROJECTPATH/${_run_dir#./}" ;;
        esac
    fi

    stress_report_print "$_run_dir"
}

stress_main() {
    local _action="${1:-}"

    case "$_action" in
        start)
            shift 1
            stress_start "$@"
            ;;
        stop)
            shift 1
            stress_stop "$@"
            ;;
        status)
            shift 1
            stress_status "$@"
            ;;
        logs)
            shift 1
            stress_logs "$@"
            ;;
        sitemap)
            shift 1
            stress_prepare_files || return 1
            stress_load_env_file "$STRESS_CONFIG_FILE"
            stress_sitemap_download "$@"
            ;;
        datasets)
            shift 1
            stress_datasets_status "$@"
            ;;
        profiles)
            shift 1
            stress_profiles "$@"
            ;;
        validate)
            shift 1
            stress_validate "$@"
            ;;
        warmup)
            shift 1
            stress_warmup "$@"
            ;;
        run)
            shift 1
            stress_run "$@"
            ;;
        report)
            shift 1
            stress_report "$@"
            ;;
        -h|--help|help|"")
            stress_help_usage
            ;;
        *)
            warp_message_warn "unknown stress action: $_action"
            stress_help_usage
            return 1
            ;;
    esac
}
