#!/bin/bash

# IMPORT HELP
. "$PROJECTPATH/.warp/bin/webserver_help.sh"

function webserver_info()
{

    NGINX_CONFIG_FILE=$(warp_env_read_var NGINX_CONFIG_FILE)
    HTTP_BINDED_PORT=$(warp_env_read_var HTTP_BINDED_PORT)
    HTTPS_BINDED_PORT=$(warp_env_read_var HTTPS_BINDED_PORT)
    HTTP_HOST_IP=$(warp_env_read_var HTTP_HOST_IP)
    VIRTUAL_HOST=$(warp_env_read_var VIRTUAL_HOST)
    NGINX_CONFIG_FILE=$(warp_env_read_var NGINX_CONFIG_FILE)

    if [ ! -z "$NGINX_CONFIG_FILE" ]
    then
        warp_message ""
        warp_message_info "* Nginx"
        warp_message "Virtual host:               $(warp_message_info $VIRTUAL_HOST)"
    

        ETC_HOSTS_IP='127.0.0.1'
        if [ "$HTTP_HOST_IP" = "0.0.0.0" ] ; then
            warp_message "Server IP:                  $(warp_message_info '127.0.0.1')"
            warp_message "HTTP binded port (host):    $(warp_message_info $HTTP_BINDED_PORT)"
            warp_message "HTTPS binded port (host):   $(warp_message_info $HTTPS_BINDED_PORT)"
        else
            warp_message "Server IP:                  $(warp_message_info $HTTP_HOST_IP)"
            ETC_HOSTS_IP=$HTTP_HOST_IP
        fi;
        warp_message "Logs:                       $(warp_message_info $PROJECTPATH/.warp/docker/volumes/nginx/logs)" 
        warp_message "Nginx configuration file:   $(warp_message_info $NGINX_CONFIG_FILE)" 
        warp_message ""
        warp_message_warn " - Configure your hosts file (/etc/hosts) with: $(warp_message_bold $ETC_HOSTS_IP'  '$VIRTUAL_HOST)"
        warp_message ""
    fi
}

function webserver_main() {
    case "$1" in
 
        info)
            webserver_info
        ;;

        version|--version)
            shift
            webserver_version "$@"
        ;;

        check)
            shift
            webserver_check "$@"
        ;;

        -t | --test | test)
            shift
            webserver_test "$@"
        ;;

        -r | --reload | reload)
            shift
            webserver_reload "$@"
        ;;

        ssh)
            shift
            webserver_simil_ssh "$@"
        ;;

        -h | --help)
            webserver_help_usage
        ;;

        *)
            if [ -n "$1" ]; then
                warp_message_error "Unknown nginx command: $1"
            fi
            webserver_help_usage
            exit 1
        ;;
    esac    
}

webserver_ensure_running() {
    if [ "$(warp_check_is_running)" = false ]; then
        warp_message_error "The containers are not running"
        warp_message_error "please, first run warp start"
        exit 1
    fi
}

webserver_version_container_id() {
    local _container_id=""

    [ -f "$DOCKERCOMPOSEFILE" ] || return 1

    _container_id=$(docker-compose -f "$DOCKERCOMPOSEFILE" ps -q web 2>/dev/null | head -n1)
    [ -n "$_container_id" ] || return 1
    [ "$(docker inspect --format '{{.State.Running}}' "$_container_id" 2>/dev/null)" = "true" ] || return 1

    printf '%s\n' "$_container_id"
}

webserver_version_resolve_image() {
    local _image=""

    if [ -f "$DOCKERCOMPOSEFILE" ]; then
        _image=$(docker-compose -f "$DOCKERCOMPOSEFILE" config 2>/dev/null | awk '
            $1 == "web:" { in_web=1; next }
            in_web && /^[^[:space:]]/ { in_web=0 }
            in_web && $1 == "image:" { print $2; exit }
        ')
    fi

    [ -n "$_image" ] || _image="nginx:latest"
    printf '%s\n' "$_image"
}

webserver_version_extract_line() {
    local _output="$1"
    local _version_line=""

    _version_line=$(printf '%s\n' "$_output" | awk '/nginx version: / { line=$0 } END { print line }')
    [ -n "$_version_line" ] || return 1

    printf '%s\n' "$_version_line"
}

webserver_version_number_from_line() {
    local _line="$1"
    local _version=""

    _version=$(printf '%s\n' "$_line" | sed -n 's/.*nginx\/\([0-9][0-9.]*\).*/\1/p')
    [ -n "$_version" ] || return 1

    printf '%s\n' "$_version"
}

webserver_version_to_int() {
    local _version="$1"
    local _major=0
    local _minor=0
    local _patch=0

    IFS='.' read -r _major _minor _patch <<EOF
$_version
EOF

    _major=${_major:-0}
    _minor=${_minor:-0}
    _patch=${_patch:-0}

    printf '%03d%03d%03d\n' "$_major" "$_minor" "$_patch"
}

webserver_version_warn_if_outdated() {
    local _version="$1"
    local _current_int=""
    local _minimum_int=""

    _current_int=$(webserver_version_to_int "$_version") || return 1
    _minimum_int=$(webserver_version_to_int "1.25.1") || return 1

    if [ "$_current_int" -lt "$_minimum_int" ]; then
        warp_message_error "Nginx must be updated. Minimum recommended version: 1.25.1"
        warp_message_error "Suggested action: docker pull nginx:latest"
    fi
}

webserver_nginx_check_hub_repo() {
    local _image_ref="$1"
    local _repo=""
    local _first_segment=""

    [ -n "$_image_ref" ] || return 1

    _repo=${_image_ref%@*}

    case "$_repo" in
        */*)
            _first_segment=${_repo%%/*}
            case "$_first_segment" in
                docker.io|index.docker.io|registry-1.docker.io)
                    _repo=${_repo#*/}
                ;;
                *.*|*:*|localhost)
                    return 1
                ;;
            esac
        ;;
        *)
            _repo="library/${_repo}"
        ;;
    esac

    _repo=${_repo%:*}
    [ -n "$_repo" ] || return 1

    printf '%s\n' "$_repo"
}

webserver_nginx_check_remote_versions() {
    local _hub_repo="$1"
    local _local_version="$2"

    [ -n "$_hub_repo" ] || return 1
    [ -n "$_local_version" ] || return 1
    command -v python3 >/dev/null 2>&1 || return 1

    HUB_REPO="$_hub_repo" LOCAL_VERSION="$_local_version" python3 <<'PY'
import json
import os
import re
import sys
import urllib.error
import urllib.request

hub_repo = os.environ["HUB_REPO"]
local_version = os.environ["LOCAL_VERSION"]
local_tuple = tuple(map(int, local_version.split(".")))
url = f"https://hub.docker.com/v2/repositories/{hub_repo}/tags?page_size=100"
versions = set()

try:
    while url:
        with urllib.request.urlopen(url) as response:
            payload = json.load(response)

        for item in payload.get("results", []):
            tag = item.get("name", "")
            if re.fullmatch(r"\d+\.\d+\.\d+", tag):
                versions.add(tag)

        url = payload.get("next")
except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError):
    print("REMOTE_ERROR=1")
    sys.exit(0)

sorted_versions = sorted(versions, key=lambda value: tuple(map(int, value.split("."))))

if not sorted_versions:
    print("REMOTE_ERROR=1")
    sys.exit(0)

remote_latest = sorted_versions[-1]
newer_versions = [
    value for value in sorted_versions
    if tuple(map(int, value.split("."))) > local_tuple
]

print(f"REMOTE_LATEST={remote_latest}")
print(f"BEHIND_COUNT={len(newer_versions)}")
print(f"NEWER_VERSIONS={','.join(newer_versions)}")
PY
}

webserver_version() {
    local _output=""
    local _status=0
    local _container_id=""
    local _image=""
    local _version_line=""
    local _version_number=""

    if [[ $# -eq 1 && ( $1 == "-h" || $1 == "--help" ) ]]; then
        webserver_version_help
        exit 0
    fi

    if [[ $# -gt 0 ]]; then
        webserver_version_help
        exit 1
    fi

    _container_id=$(webserver_version_container_id)
    if [ -n "$_container_id" ]; then
        _output=$(docker exec -i "$_container_id" nginx -v 2>&1)
        _status=$?
    else
        _image=$(webserver_version_resolve_image)
        _output=$(docker run --rm "$_image" nginx -v 2>&1)
        _status=$?
    fi

    if [ "$_status" -ne 0 ]; then
        webserver_print_command_output "$_output"
        return "$_status"
    fi

    _version_line=$(webserver_version_extract_line "$_output") || {
        warp_message_error "unable to detect nginx version"
        webserver_print_command_output "$_output"
        return 1
    }

    warp_message "$_version_line"

    _version_number=$(webserver_version_number_from_line "$_version_line") || return 0
    webserver_version_warn_if_outdated "$_version_number"
}

webserver_check() {
    local _output=""
    local _status=0
    local _container_id=""
    local _image=""
    local _version_line=""
    local _version_number=""
    local _current_int=""
    local _minimum_int=""
    local _hub_repo=""
    local _compare_output=""
    local _remote_latest=""
    local _behind_count=""
    local _newer_versions=""

    if [[ $# -eq 1 && ( $1 == "-h" || $1 == "--help" ) ]]; then
        webserver_check_help
        exit 0
    fi

    if [[ $# -gt 0 ]]; then
        webserver_check_help
        exit 1
    fi

    _image=$(webserver_version_resolve_image)
    _container_id=$(webserver_version_container_id)
    if [ -n "$_container_id" ]; then
        _output=$(docker exec -i "$_container_id" nginx -v 2>&1)
        _status=$?
    else
        _output=$(docker run --rm "$_image" nginx -v 2>&1)
        _status=$?
    fi

    if [ "$_status" -ne 0 ]; then
        webserver_print_command_output "$_output"
        return "$_status"
    fi

    _version_line=$(webserver_version_extract_line "$_output") || {
        warp_message_error "unable to detect nginx version"
        webserver_print_command_output "$_output"
        return 1
    }

    _version_number=$(webserver_version_number_from_line "$_version_line") || {
        warp_message_error "unable to parse nginx version number"
        return 1
    }

    _hub_repo=$(webserver_nginx_check_hub_repo "$_image") || {
        warp_message_error "Could not compare remote versions for image: $_image"
        warp_message_warn "Supported image references for this check must resolve to Docker Hub repositories."
        return 2
    }

    _compare_output=$(webserver_nginx_check_remote_versions "$_hub_repo" "$_version_number") || {
        warp_message_error "Could not query remote nginx versions from Docker Hub."
        return 2
    }

    printf '%s\n' "$_compare_output" | grep -q '^REMOTE_ERROR=1$' && {
        warp_message_error "Could not query remote nginx versions from Docker Hub."
        return 2
    }

    _remote_latest=$(printf '%s\n' "$_compare_output" | sed -n 's/^REMOTE_LATEST=//p')
    _behind_count=$(printf '%s\n' "$_compare_output" | sed -n 's/^BEHIND_COUNT=//p')
    _newer_versions=$(printf '%s\n' "$_compare_output" | sed -n 's/^NEWER_VERSIONS=//p')

    if [ -z "$_remote_latest" ] || [ -z "$_behind_count" ]; then
        warp_message_error "Could not parse remote nginx version data."
        return 2
    fi

    warp_message "Image reference: $_image"
    warp_message "Local nginx version: $_version_number"
    warp_message "Latest remote version: $_remote_latest"
    warp_message "Released versions behind: $_behind_count"

    if [ "$_behind_count" -gt 0 ] && [ -n "$_newer_versions" ]; then
        warp_message "Newer versions: ${_newer_versions//,/ , }"
    fi

    _current_int=$(webserver_version_to_int "$_version_number") || return 1
    _minimum_int=$(webserver_version_to_int "1.25.1") || return 1

    if [ "$_behind_count" -eq 0 ]; then
        warp_message_ok "Status: up to date"
        return 0
    fi

    if [ "$_current_int" -lt "$_minimum_int" ]; then
        warp_message_error "Status: must be updated"
        warp_message_error "Minimum recommended version: 1.25.1"
        warp_message_error "Suggested action: docker pull nginx:latest"
        return 1
    fi

    if [ "$_behind_count" -le 10 ]; then
        warp_message_ok "Status: still a valid version"
        return 0
    fi

    warp_message_warn "Status: outdated"
    warp_message_warn "Recommendation: update nginx to a newer released version."
    warp_message_warn "Suggested action: docker pull nginx:latest"
    return 1
}

webserver_test() {
    if [[ $# -eq 1 && ( $1 == "-h" || $1 == "--help" ) ]]; then
        webserver_test_help
        exit 0
    fi

    if [[ $# -gt 0 ]]; then
        webserver_test_help
        exit 1
    fi

    webserver_ensure_running
    webserver_run_command docker-compose -f "$DOCKERCOMPOSEFILE" exec -u root web nginx -t
}

webserver_host_config_path() {
    local _config_file=""

    _config_file=$(warp_env_read_var NGINX_CONFIG_FILE)
    [ -n "$_config_file" ] || return 1

    case "$_config_file" in
        /*)
            printf '%s\n' "$_config_file"
        ;;
        ./*)
            printf '%s/%s\n' "$PROJECTPATH" "${_config_file#./}"
        ;;
        *)
            printf '%s/%s\n' "$PROJECTPATH" "$_config_file"
        ;;
    esac
}

webserver_file_signature() {
    local _file="$1"
    local _signature=""

    [ -f "$_file" ] || return 1
    _signature=$(cksum "$_file" 2>/dev/null) || return 1
    set -- $_signature
    printf '%s:%s\n' "$1" "$2"
}

webserver_container_config_signature() {
    local _file="$1"
    local _signature=""

    [ -n "$_file" ] || return 1
    _signature=$(docker-compose -f "$DOCKERCOMPOSEFILE" exec -T -u root web cksum "$_file" </dev/null 2>/dev/null) || return 1
    set -- $_signature
    printf '%s:%s\n' "$1" "$2"
}

webserver_known_config_mounts() {
    local _host_config=""
    local _relative_config=""
    local _container_config=""

    _host_config=$(webserver_host_config_path) && printf '%s|%s\n' "$_host_config" "/etc/nginx/sites-enabled/default.conf"

    for _relative_config in \
        ".warp/docker/config/nginx/nginx.conf|/etc/nginx/nginx.conf" \
        ".warp/docker/config/nginx/m2-cors.conf|/etc/nginx/m2-cors.conf" \
        ".warp/docker/config/nginx/bad-bot-blocker/globalblacklist.conf|/etc/nginx/conf.d/globalblacklist.conf"
    do
        _host_config="$PROJECTPATH/${_relative_config%%|*}"
        _container_config="${_relative_config#*|}"
        [ -f "$_host_config" ] && printf '%s|%s\n' "$_host_config" "$_container_config"
    done
}

# Set by webserver_config_is_stale when a stale single-file bind mount is found.
WEBSERVER_STALE_CONFIG_PATH=""

webserver_config_is_stale() {
    local _host_config=""
    local _container_config=""
    local _host_signature=""
    local _container_signature=""

    WEBSERVER_STALE_CONFIG_PATH=""

    while IFS='|' read -r _host_config _container_config; do
        [ -n "$_host_config" ] || continue
        _host_signature=$(webserver_file_signature "$_host_config") || return 2
        _container_signature=$(webserver_container_config_signature "$_container_config") || return 2

        if [ "$_host_signature" != "$_container_signature" ]; then
            WEBSERVER_STALE_CONFIG_PATH="$_host_config"
            return 0
        fi
    done < <(webserver_known_config_mounts)

    return 1
}

webserver_copy_host_config_to_container() {
    local _host_config="$1"
    local _container_config="$2"

    [ -f "$_host_config" ] || return 1
    [ -n "$_container_config" ] || return 1

    docker-compose -f "$DOCKERCOMPOSEFILE" exec -T -u root web sh -c 'cat > "$1"' sh "$_container_config" < "$_host_config"
}

webserver_validate_host_config_in_container() {
    local _host_config=""
    local _nginx_config=""
    local _globalblacklist_config=""
    local _m2_cors_config=""
    local _status=0

    _host_config=$(webserver_host_config_path) || return 1
    _nginx_config="$PROJECTPATH/.warp/docker/config/nginx/nginx.conf"
    _globalblacklist_config="$PROJECTPATH/.warp/docker/config/nginx/bad-bot-blocker/globalblacklist.conf"
    _m2_cors_config="$PROJECTPATH/.warp/docker/config/nginx/m2-cors.conf"

    webserver_copy_host_config_to_container "$_host_config" "/etc/nginx/sites-enabled/warp-vhost-test.conf" || return 1

    if [ -f "$_nginx_config" ]; then
        webserver_copy_host_config_to_container "$_nginx_config" "/etc/nginx/warp-nginx-test.conf" || return 1
    else
        docker-compose -f "$DOCKERCOMPOSEFILE" exec -T -u root web cp /etc/nginx/nginx.conf /etc/nginx/warp-nginx-test.conf || return 1
    fi

    if [ -f "$_globalblacklist_config" ]; then
        webserver_copy_host_config_to_container "$_globalblacklist_config" "/etc/nginx/conf.d/warp-globalblacklist-test.conf" || return 1
    fi

    if [ -f "$_m2_cors_config" ]; then
        webserver_copy_host_config_to_container "$_m2_cors_config" "/etc/nginx/warp-m2-cors-test.conf" || return 1
    fi

    docker-compose -f "$DOCKERCOMPOSEFILE" exec -T -u root web sh -c '
sed -i "s#include[[:space:]]*/etc/nginx/sites-enabled/\*;#include /etc/nginx/sites-enabled/warp-vhost-test.conf;#" /etc/nginx/warp-nginx-test.conf || exit 1
[ ! -f /etc/nginx/conf.d/warp-globalblacklist-test.conf ] || sed -i "s#/etc/nginx/conf.d/globalblacklist.conf#/etc/nginx/conf.d/warp-globalblacklist-test.conf#g" /etc/nginx/warp-nginx-test.conf || exit 1
[ ! -f /etc/nginx/warp-m2-cors-test.conf ] || sed -i "s#/etc/nginx/m2-cors.conf#/etc/nginx/warp-m2-cors-test.conf#g" /etc/nginx/sites-enabled/warp-vhost-test.conf || exit 1
grep -q "/etc/nginx/sites-enabled/warp-vhost-test.conf" /etc/nginx/warp-nginx-test.conf || exit 1
nginx -t -c /etc/nginx/warp-nginx-test.conf
'
    _status=$?
    docker-compose -f "$DOCKERCOMPOSEFILE" exec -T -u root web rm -f \
        /etc/nginx/sites-enabled/warp-vhost-test.conf \
        /etc/nginx/warp-nginx-test.conf \
        /etc/nginx/conf.d/warp-globalblacklist-test.conf \
        /etc/nginx/warp-m2-cors-test.conf >/dev/null 2>&1
    return "$_status"
}

webserver_restart_web() {
    docker-compose -f "$DOCKERCOMPOSEFILE" restart web
}

webserver_reload_status_message() {
    local _color="$1"
    local _message="$2"

    case "$_color" in
        success)
            warp_message_ok "============================================================"
            warp_message_ok "$_message"
            warp_message_ok "============================================================"
        ;;
        warn)
            warp_message_warn "============================================================"
            warp_message_warn "$_message"
            warp_message_warn "============================================================"
        ;;
        error)
            warp_message_error "============================================================"
            warp_message_error "$_message"
            warp_message_error "============================================================"
        ;;
        *)
            warp_message "============================================================"
            warp_message "$_message"
            warp_message "============================================================"
        ;;
    esac
}

webserver_print_command_output() {
    local _output="$1"
    local _line=""
    local _status_value=""

    [ -n "$_output" ] || return 0

    while IFS= read -r _line || [ -n "$_line" ]; do
        case "$_line" in
            "exit status "*)
                _status_value="${_line#exit status }"
                if [[ "$_status_value" =~ ^[0-9]+$ ]] && [ "$_status_value" -ne 0 ]; then
                    warp_message_error "$_line"
                else
                    warp_message "$_line"
                fi
            ;;
            *)
                warp_message "$_line"
            ;;
        esac
    done <<< "$_output"
}

webserver_run_command() {
    local _output=""
    local _status=0

    _output=$("$@" 2>&1)
    _status=$?
    webserver_print_command_output "$_output"
    return "$_status"
}

webserver_reload() {
    local _config_file=""
    local _test_status=0
    local _stale_status=0
    local _reload_status=0
    local _restart_status=0
    local _host_test_status=0

    if [[ $# -eq 1 && ( $1 == "-h" || $1 == "--help" ) ]]; then
        webserver_reload_help
        exit 0
    fi

    if [[ $# -gt 0 ]]; then
        webserver_reload_help
        exit 1
    fi

    webserver_ensure_running
    webserver_run_command docker-compose -f "$DOCKERCOMPOSEFILE" exec -u root web nginx -t
    _test_status=$?
    [ "$_test_status" -eq 0 ] || exit "$_test_status"

    webserver_config_is_stale
    _stale_status=$?
    if [ "$_stale_status" -eq 0 ]; then
        _config_file=$(warp_env_read_var NGINX_CONFIG_FILE)
        [ -n "$WEBSERVER_STALE_CONFIG_PATH" ] && _config_file="$WEBSERVER_STALE_CONFIG_PATH"
        webserver_reload_status_message "warn" "Nginx config bind mount is stale: ${_config_file}"
        warp_message_warn "Restarting web container to apply the current host file."
        warp_message "Testing current host vhost before restarting web."
        webserver_validate_host_config_in_container
        _host_test_status=$?
        if [ "$_host_test_status" -ne 0 ]; then
            webserver_reload_status_message "error" "Current host nginx configuration did not pass validation; web was not restarted."
            exit "$_host_test_status"
        fi
        webserver_restart_web || exit $?
        webserver_config_is_stale
        _stale_status=$?
        if [ "$_stale_status" -eq 0 ]; then
            webserver_reload_status_message "error" "Nginx vhost is still stale after restarting web."
            warp_message_error "Recreate the web service so Docker remounts ${_config_file}."
            exit 1
        fi
        exit 0
    elif [ "$_stale_status" -eq 2 ]; then
        warp_message_warn "Could not verify host/container vhost signatures; continuing with nginx reload."
    fi

    webserver_run_command docker-compose -f "$DOCKERCOMPOSEFILE" exec -u root web nginx -s reload
    _reload_status=$?
    if [ "$_reload_status" -eq 0 ]; then
        webserver_reload_status_message "success" "Nginx was reloaded."
        exit 0
    fi

    webserver_reload_status_message "warn" "Nginx reload failed; restarting web container as fallback."
    webserver_restart_web
    _restart_status=$?
    exit "$_restart_status"
}

webserver_simil_ssh() {
    : '
    This function provides a bash pipe as root or nginx user.
    It is called as SSH in order to make it better for developers ack
    but it does not use Secure Shell anywhere.
    '

    # Check for wrong input:
    if [[ $# -gt 1 ]]; then
        webserver_ssh_wrong_input
        exit 1
    else
        if [[ $1 == "--root" ]]; then
            webserver_ensure_running
            docker-compose -f "$DOCKERCOMPOSEFILE" exec -u root web bash
        elif [[ -z $1 || $1 == "--nginx" ]]; then
            webserver_ensure_running
            # It is better if defines nginx user as default ######################
            docker-compose -f "$DOCKERCOMPOSEFILE" exec -u nginx web bash
        elif [[ $1 == "-h" || $1 == "--help" ]]; then
            webserver_ssh_help
            exit 0
        else
            webserver_ssh_wrong_input
            exit 1
        fi
    fi
}

webserver_ssh_wrong_input() {
    warp_message_error "Wrong input."
    webserver_ssh_help
    exit 1
}
