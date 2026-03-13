#!/bin/bash

    # IMPORT HELP

    . "$PROJECTPATH/.warp/bin/update_help.sh"

function update_command() {

  if [ "$1" = "-h" ] || [ "$1" = "--help" ] ; then
        
      update_help_usage
      exit 1;
  elif [ "$1" = "--images" ] ; then

      warp_message_warn "checking if there are images available to update"
      docker-compose -f "$DOCKERCOMPOSEFILE" pull
  else
      # Delegate to the safe updater implemented in warp.sh.
      # This avoids legacy setup-based update paths that may overwrite config.
      warp_update "$@"
  fi;
}

function update_main()
{
    case "$1" in
        update)
          shift 1
          update_command "$@"
        ;;

        *)
          update_help_usage
        ;;
    esac
}
