#!/bin/bash

    # IMPORT HELP

    . "$PROJECTPATH/.warp/bin/stop_help.sh"

#######################################
# Stop the server
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   None

##-c ####################-c #################
function stop() {
  local _stress_mode="$1"
  local _stopped_main=0

  MODE_SANDBOX=$(warp_env_read_var MODE_SANDBOX)
  if [ ! -z "$MODE_SANDBOX" ]
  then
      if [ "$MODE_SANDBOX" = "Y" ] || [ "$MODE_SANDBOX" = "y" ] ; then
        warp_message_warn "warp mode sandbox must be stopped run: $(warp_message_info2 'warp sandbox stop')";
        exit 1;
      fi;
  fi

  if [ "$1" = "-h" ] || [ "$1" = "--help" ] ; then
        
      stop_help_usage
      exit 1;
  else
    if [ "$(warp_check_is_running)" = true ]; then

      if [ "$1" = "--hard" ] ; then
        DOCKERACTION="down --remove-orphans"
      else
        DOCKERACTION=stop
      fi;

      case "$(uname -s)" in
        Darwin)
          if [ "$USE_DOCKER_SYNC" = "Y" ] || [ "$USE_DOCKER_SYNC" = "y" ] ; then 
            docker stop $(basename $(pwd))-volume-sync
            docker-sync stop
          fi

          # stop docker containers in macOS
          docker-compose -f $DOCKERCOMPOSEFILE $DOCKERACTION
        ;;
        Linux)
          # stop docker containers in linux
          docker-compose -f $DOCKERCOMPOSEFILE $DOCKERACTION
        ;;
      esac
      _stopped_main=1
    else
      warp_message_warn "the containers are not running";
    fi
  fi;

  if declare -F stress_stop_managed_quiet >/dev/null 2>&1; then
    stress_stop_managed_quiet "$_stress_mode"
  fi

  if [ "$_stopped_main" -eq 0 ]; then
    warp_message_warn "for start, please run: warp start";
    exit 1;
  fi

}

function stop_main()
{
    case "$1" in
        stop)
          shift 1
          stop "$@"
        ;;

        *)
          stop_help_usage
        ;;
    esac
}
