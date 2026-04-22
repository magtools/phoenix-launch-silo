#!/bin/bash

    # IMPORT HELP
    . "$PROJECTPATH/.warp/bin/start_help.sh"

    # IMPORT .env
    if [[ -e "$PROJECTPATH/.env" ]]; then
      . "$PROJECTPATH/.env"
    fi

    # INCLUDE VARIABLES
    . "$PROJECTPATH/.warp/variables.sh"

#######################################
# Start the server and all of its
# components
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   None
#######################################
function start() {

  if [ "$(warp_check_is_running)" = true ]; then
    warp_message_warn "the containers are running";
    warp_message_warn "for stop, please run: warp stop";
    exit 1;
  fi

  MODE_SANDBOX=$(warp_env_read_var MODE_SANDBOX)
  if [ ! -z "$MODE_SANDBOX" ]
  then
      if [ "$MODE_SANDBOX" = "Y" ] || [ "$MODE_SANDBOX" = "y" ] ; then
        warp_message_warn "warp mode sandbox must be started run: $(warp_message_info2 'warp sandbox start')";
        exit 1;
      fi;
  fi

  if [ "$1" = "-h" ] || [ "$1" = "--help" ] ; then

      start_help_usage
      exit 1;
  else

    # Check
    warp_check_files
    warp_php_config_ensure_xdebug_file || exit 1
    warp_php_config_ensure_opcache_file || exit 1

    if [ "$1" = "-f" ] || [ "$1" = "-F" ] ; then
      [ ! -f "$2" ] && warp_message_error "Custom yml file $2 not exist" && exit 1;

      CUSTOM_YML_FILE=$2;
    fi

    if [ "$1" = "--selenium" ] ; then
      CUSTOM_YML_FILE=$DOCKERCOMPOSEFILESELENIUM;
    fi

    if ! start_preflight_configured_images; then
      exit 1
    fi

    case "$(uname -s)" in
      Darwin)
        USE_DOCKER_SYNC=$(warp_env_read_var USE_DOCKER_SYNC)
        if [ "$USE_DOCKER_SYNC" = "Y" ] || [ "$USE_DOCKER_SYNC" = "y" ] ; then
          # start data sync
          docker-sync start
        fi

        if [ ! -z "$CUSTOM_YML_FILE" ] ; then
          check_ES_version
          # start docker with custom yml file
          start_compose_up -f "$DOCKERCOMPOSEFILE" -f "$DOCKERCOMPOSEFILEMAC" -f "$CUSTOM_YML_FILE" up --remove-orphans -d || exit $?
          check_PHP_Image
        else
          check_ES_version
          # start docker containers in macOS
          start_compose_up -f "$DOCKERCOMPOSEFILE" -f "$DOCKERCOMPOSEFILEMAC" up --remove-orphans -d || exit $?
          check_PHP_Image
        fi
      ;;
      Linux)
        if [ ! -z "$CUSTOM_YML_FILE" ] ; then
          check_ES_version
          # start docker with custom yml file
          start_compose_up -f "$DOCKERCOMPOSEFILE" -f "$CUSTOM_YML_FILE" up --remove-orphans -d || exit $?
          check_PHP_Image
        else
          check_ES_version
          # start docker containers in linux
          start_compose_up -f "$DOCKERCOMPOSEFILE" up --remove-orphans -d || exit $?
          check_PHP_Image
        fi
      ;;
    esac

    if [ "$(warp_check_php_is_running)" = true ]
    then
      # COPY ID_RSA ./ssh
      copy_ssh_id
      # Initialize Cron Job
      crontab_run

      # Starting Supervisor service
      # docker-compose -f $DOCKERCOMPOSEFILE exec -d --user=root php bash -c "service supervisor start 2> /dev/null"

    else
      warp_message_warn "Please Run ./warp composer --credential to copy the credentials"
    fi
  fi;
}

start_compose_up() {
  local _output_file=""
  local _status=0

  _output_file=$(mktemp "${TMPDIR:-/tmp}/warp-start.XXXXXX") || {
    docker-compose "$@"
    return $?
  }

  docker-compose "$@" >"$_output_file" 2>&1
  _status=$?
  cat "$_output_file"

  if [ "$_status" -ne 0 ]; then
    start_mount_error_hint "$_output_file"
  fi

  rm -f "$_output_file"
  return "$_status"
}

start_mount_error_hint() {
  local _output_file="$1"
  local _mount_path=""

  grep -Eq 'not a directory|Are you trying to mount a directory onto a file' "$_output_file" 2>/dev/null || return 0

  _mount_path=$(sed -n 's/.*error mounting "\([^"]*\)".*/\1/p; s/.*mount src=\([^,]*\),.*/\1/p' "$_output_file" | head -n 1)

  if [ -n "$_mount_path" ] && [ -f "$_mount_path" ]; then
    warp_message_warn ""
    warp_message_warn "Docker reported a stale bind mount state, but the host path is a file:"
    warp_message_warn "$_mount_path"
    warp_message_warn "Recommended recovery:"
    warp_message_warn "warp stop --hard && warp start"
    return 0
  fi

  warp_message_warn ""
  warp_message_warn "Docker reported a file/directory bind mount mismatch."
  warp_message_warn "If the host path is a file, recover with:"
  warp_message_warn "warp stop --hard && warp start"
}

function start_main()
{
    case "$1" in
        start)
          shift 1
          start "$@"
        ;;

        *)
          start_help_usage
        ;;
    esac
}

start_preflight_configured_images() {
  local _status=0
  local _php_repo=""
  local _php_version=""
  local _appdata_repo=""
  local _appdata_version=""

  _php_repo=$(warp_env_read_var PHP_IMAGE_REPO)
  [ -n "$_php_repo" ] || _php_repo="magtools"
  _php_version=$(warp_env_read_var PHP_VERSION)

  _appdata_repo=$(warp_env_read_var APPDATA_IMAGE_REPO)
  [ -n "$_appdata_repo" ] || _appdata_repo="magtools"
  _appdata_version=$(warp_env_read_var APPDATA_VERSION)
  [ -n "$_appdata_version" ] || _appdata_version="bookworm"

  if ! start_check_configured_image "php" "${_php_repo}/php:${_php_version}" "warp/php:${_php_version}"; then
    _status=1
  fi

  if ! start_check_configured_image "appdata" "${_appdata_repo}/appdata:${_appdata_version}" "warp/appdata:${_appdata_version}"; then
    _status=1
  fi

  return "$_status"
}

start_check_configured_image() {
  local _service="$1"
  local _image="$2"
  local _source_image="$3"

  if docker image inspect "$_image" >/dev/null 2>&1; then
    return 0
  fi

  case "$_image" in
    *:*-poc-*|*:poc-*|*:*-poc|*:poc)
      ;;
    *)
      return 0
      ;;
  esac

  warp_message_warn ""
  warp_message_warn "    Local PoC image not found for ${_service}: ${_image}"
  warp_message_warn "    This tag is intended for local testing before DockerHub publish."
  warp_message_warn "    If the image exists with the old local namespace, run:"
  warp_message_warn "    docker tag ${_source_image} ${_image}"
  return 1
}

check_PHP_Image() {
  local PHP_IMAGE_REPOS=("magtools" "66ecommerce" "summasolutions")
  local PHP_IMAGE_REPO=""
  local PHP_IMAGE=""
  local PHP_IMAGE_CREATION_TAG=""
  local PHP_IMAGE_CONFIGURED_REPO=""
  local PHP_IMAGE_CONFIGURED=""

  PHP_IMAGE_CONFIGURED_REPO=$(warp_env_read_var PHP_IMAGE_REPO)
  if [ -n "$PHP_IMAGE_CONFIGURED_REPO" ]; then
    PHP_IMAGE_CONFIGURED="${PHP_IMAGE_CONFIGURED_REPO}/php:${PHP_VERSION}"
    if docker image inspect "$PHP_IMAGE_CONFIGURED" --format '{{.Created}}' >/dev/null 2>&1; then
      PHP_IMAGE="$PHP_IMAGE_CONFIGURED"
    fi
  fi

  if [ -z "$PHP_IMAGE" ]; then
    for PHP_IMAGE_REPO in "${PHP_IMAGE_REPOS[@]}"; do
      PHP_IMAGE="${PHP_IMAGE_REPO}/php:${PHP_VERSION}"
      if docker image inspect "$PHP_IMAGE" --format '{{.Created}}' >/dev/null 2>&1; then
        break
      fi
      PHP_IMAGE=""
    done
  fi

  if [ -z "$PHP_IMAGE" ]; then
    warp_message_warn ""
    if [ -n "$PHP_IMAGE_CONFIGURED" ]; then
      warp_message_warn "    PHP image not found: ${PHP_IMAGE_CONFIGURED}"
    else
      warp_message_warn "    PHP image not found: magtools/php:${PHP_VERSION}, 66ecommerce/php:${PHP_VERSION} or summasolutions/php:${PHP_VERSION}"
    fi
    return
  fi

  PHP_IMAGE_CREATION_TAG=$(docker image inspect "$PHP_IMAGE" --format '{{.Created}}' 2>/dev/null)

  PHP_IMAGE_CREATION_TAG=$(echo $PHP_IMAGE_CREATION_TAG | sed 's/\-/ /g')
  PHP_IMAGE_CREATION_TAG=($PHP_IMAGE_CREATION_TAG)
  if [[ ${PHP_IMAGE_CREATION_TAG[0]} -lt 2021 ]]; then
    warp_message_warn ""
    warp_message_warn "    Please update your PHP Image."
  fi
}

check_ES_version() {
  ES_VER=($(grep "ES_VERSION" $PROJECTPATH/.env | sed 's/=/ /g'))
  ES_VER=${ES_VER[1]}

  if [[ ${ES_VER:0:1} -eq '6' ]]; then
    warp_message_warn "If Elasticsearch doesn't work, maybe you have to use the following cmd:"
    warp_message_warn "    sudo sysctl -w vm.max_map_count = 262144"
  fi

  unset ES_VER
}
