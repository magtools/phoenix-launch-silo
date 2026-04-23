#!/bin/bash

warp_php_container_id() {
    local _php_container=""

    command -v docker >/dev/null 2>&1 || return 1
    declare -F warp_compose_bootstrap >/dev/null 2>&1 && warp_compose_bootstrap
    command -v docker-compose >/dev/null 2>&1 || return 1
    [ -f "$DOCKERCOMPOSEFILE" ] || return 1
    docker info >/dev/null 2>&1 || return 1

    _php_container=$(docker-compose -f "$DOCKERCOMPOSEFILE" ps -q php 2>/dev/null)
    [ -n "$_php_container" ] || return 1
    [ "$(docker inspect --format '{{.State.Running}}' "$_php_container" 2>/dev/null)" = "true" ] || return 1

    printf '%s\n' "$_php_container"
}

warp_php_fpm_reload_or_restart() {
    local _reason="$1"
    local _php_container=""

    _php_container=$(warp_php_container_id) || {
        warp_message "PHP container is not running; web runtime will apply ${_reason} on next start."
        return 0
    }

    if docker exec "$_php_container" sh -c 'kill -USR2 1' >/dev/null 2>&1; then
        warp_message "PHP-FPM was reloaded to apply ${_reason}."
        return 0
    fi

    warp_message_warn "PHP-FPM reload failed; restarting php container to apply ${_reason}."
    docker-compose -f "$DOCKERCOMPOSEFILE" restart php >/dev/null 2>&1 || {
        warp_message_error "could not restart php container; run: warp docker restart php"
        return 1
    }

    warp_message "PHP container was restarted to apply ${_reason}."
}
