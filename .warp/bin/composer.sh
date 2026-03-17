#!/bin/bash

    # IMPORT HELP

    . "$PROJECTPATH/.warp/bin/composer_help.sh"

function copy_ssh_id() {
  if [ "$2" ] ; then
      if [ ! -f "$2" ] ; then
        warp_message_error "something was wrong reading the file: $2"
        exit 0;
      else
        PATH_KEY_PAIR=$2
        sudo chown "$(whoami)" "$PATH_KEY_PAIR"
        sudo chmod 400 "$PATH_KEY_PAIR"
      fi;
  else
      PATH_KEY_PAIR=$HOME/.ssh/id_rsa
  fi;

  if [ -f "$PATH_KEY_PAIR" ] ; then
    docker-compose -f "$DOCKERCOMPOSEFILE" exec php bash -c "mkdir -p /var/www/.ssh/"
    docker cp "$PATH_KEY_PAIR" "$(docker-compose -f "$DOCKERCOMPOSEFILE" ps -q php)":/var/www/.ssh/id_rsa
    docker-compose -f "$DOCKERCOMPOSEFILE" exec --user=root php bash -c "chown -R www-data:www-data /var/www/.ssh/id_rsa"
    docker-compose -f "$DOCKERCOMPOSEFILE" exec --user=root php bash -c "chmod 400 /var/www/.ssh/id_rsa"
  fi;
}

function composer() {

  if [ "$1" = "-h" ] || [ "$1" = "--help" ] ; then      
      composer_help_usage
      exit 0;
  fi

  if [ "$(warp_check_is_running)" = false ]; then
    warp_message_error "The containers are not running"
    warp_message_error "please, first run warp start"

    exit 1;
  fi

  
  if [ "$1" = "--credential" ] ; then
      warp_message "copying credentials"
      copy_ssh_id "$@"
      warp_message "Done!"
  else

    if [ "$1" = "-T" ]; then
      shift 1
      # Pass args as positional parameters to avoid shell splitting issues.
      docker-compose -f "$DOCKERCOMPOSEFILE" exec -T php bash -lc 'COMPOSER_BIN=""; \
        [ -x /usr/local/bin/composer ] && COMPOSER_BIN="/usr/local/bin/composer"; \
        [ -z "$COMPOSER_BIN" ] && [ -x /usr/bin/composer ] && COMPOSER_BIN="/usr/bin/composer"; \
        [ -z "$COMPOSER_BIN" ] && echo "composer not found in /usr/local/bin or /usr/bin" && exit 1; \
        php -dmemory_limit=-1 "$COMPOSER_BIN" "$@"' bash "$@"
    else
      docker-compose -f "$DOCKERCOMPOSEFILE" exec php bash -lc 'COMPOSER_BIN=""; \
        [ -x /usr/local/bin/composer ] && COMPOSER_BIN="/usr/local/bin/composer"; \
        [ -z "$COMPOSER_BIN" ] && [ -x /usr/bin/composer ] && COMPOSER_BIN="/usr/bin/composer"; \
        [ -z "$COMPOSER_BIN" ] && echo "composer not found in /usr/local/bin or /usr/bin" && exit 1; \
        php -dmemory_limit=-1 "$COMPOSER_BIN" "$@"' bash "$@"
    fi;
  fi;
}

function composer_main()
{
    case "$1" in
        composer)
		      shift 1
          composer "$@"
        ;;

        *)
		      composer_help_usage
        ;;
    esac
}
