#!/bin/bash

    # IMPORT HELP

    . "$PROJECTPATH/.warp/bin/crontab_help.sh"

# Initialize Cron Job
function crontab_run() {
    local _status=0

    docker-compose -f "$DOCKERCOMPOSEFILE" exec -T --user=root php bash -lc '
        cron_bin=""

        cron_is_running() {
            if command -v pgrep >/dev/null 2>&1; then
                pgrep -x cron >/dev/null 2>&1 || pgrep -x crond >/dev/null 2>&1
                return $?
            fi

            ps -eo comm= 2>/dev/null | grep -Eq "^(cron|crond)$"
        }

        cron_find_bin() {
            local _candidate=""

            for _candidate in \
                "$(command -v cron 2>/dev/null)" \
                "$(command -v crond 2>/dev/null)" \
                /usr/sbin/cron \
                /usr/sbin/crond \
                /usr/bin/cron \
                /usr/bin/crond \
                /sbin/cron \
                /sbin/crond
            do
                [ -n "$_candidate" ] || continue
                [ -x "$_candidate" ] || continue
                printf "%s" "$_candidate"
                return 0
            done

            return 1
        }

        cron_stop() {
            if command -v pkill >/dev/null 2>&1; then
                pkill -x cron >/dev/null 2>&1 || true
                pkill -x crond >/dev/null 2>&1 || true
                sleep 1
                return 0
            fi

            ps -eo pid=,comm= 2>/dev/null | awk "
                \$2 == \"cron\" || \$2 == \"crond\" { print \$1 }
            " | while read -r _pid; do
                [ -n "$_pid" ] || continue
                kill "$_pid" >/dev/null 2>&1 || true
            done

            sleep 1
        }

        chown root:root /etc/cron.d/* 2>/dev/null || true
        chmod 0644 /etc/cron.d/* 2>/dev/null || true

        cron_bin="$(cron_find_bin)" || {
            echo "warp: cron daemon not found inside php container" >&2
            exit 127
        }

        cron_stop
        cron_is_running && {
            echo "warp: cron daemon is still running after stop attempt" >&2
            exit 1
        }

        "$cron_bin"
        _start_status=$?
        [ "$_start_status" -eq 0 ] || exit "$_start_status"

        cron_is_running || {
            echo "warp: cron daemon did not stay running after restart" >&2
            exit 1
        }

        exit 0
    '
    _status=$?

    if [ "$_status" -ne 0 ]; then
        warp_message_warn "cron daemon could not be started inside the php container"
        warp_message_warn "check whether the image provides cron or crond"
    fi

    return "$_status"
}

function crontab() {

  if [ "$1" = "-h" ] || [ "$1" = "--help" ] ; then      

      crontab_help_usage
      exit 0;
  fi

  if [ "$(warp_check_is_running)" = false ]; then
    warp_message_error "The containers are not running"
    warp_message_error "please, first run warp start"

    exit 1;
  fi

  
  if [ "$1" = "-e" ] ; then

    docker-compose -f "$DOCKERCOMPOSEFILE" exec --user=root php bash -c "vim /etc/cron.d/cronfile"
  elif [ "$1" = "-l" ] ; then

    docker-compose -f "$DOCKERCOMPOSEFILE" exec php bash -c "cat /etc/cron.d/cronfile"
  else

    crontab_help_usage
  fi;

}

function crontab_main()
{
    case "$1" in
        crontab)
          shift 1
          crontab "$@"
        ;;

        -h | --help)
            crontab_help_usage
        ;;

        *)
		      crontab_help_usage
        ;;
    esac
}
