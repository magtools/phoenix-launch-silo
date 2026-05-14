#!/bin/bash

    # IMPORT HELP

    . "$PROJECTPATH/.warp/bin/restart_help.sh"

#######################################
# Stop the server
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   None

##-c ####################-c #################
function restart_command() {
  local _mode="${1:-}"
  local _service="${2:-}"

  if [ "$1" = "-h" ] || [ "$1" = "--help" ] ; then
      restart_help_usage
  elif [ "$_mode" = "service" ] || [ "$_mode" = "-s" ] ; then
    if [ -z "$_service" ]; then
      warp_message_error "compose service name is required"
      restart_help_usage
      exit 1
    fi

    if [ ! -f "$DOCKERCOMPOSEFILE" ]; then
      warp_message_error "$DOCKERCOMPOSEFILE not found"
      exit 1
    fi

    docker-compose -f "$DOCKERCOMPOSEFILE" restart "$_service"
  else
    stop_main stop
    start_main start
  fi;

}

function restart_main()
{
    case "$1" in
        restart)
          shift 1
          restart_command "$@"
        ;;

        *)
          restart_help_usage
        ;;
    esac
}
