#!/bin/bash

warp_source_required() {
    local _warp_source_file="$1"

    [ -f "$_warp_source_file" ] || {
        echo >&2 "warp framework missing required file: $_warp_source_file"
        return 1
    }

    . "$_warp_source_file"
}

warp_source_optional() {
    local _warp_source_file="$1"

    [ -f "$_warp_source_file" ] || return 0
    . "$_warp_source_file"
}

warp_mark_loaded() {
    local _warp_loaded_file="$1"

    WARP_LOADED_FILES["$_warp_loaded_file"]=1
}

warp_source_required_marked() {
    local _warp_source_file="$1"

    warp_source_required "$_warp_source_file" || return 1
    warp_mark_loaded "$_warp_source_file"
}

warp_source_optional_marked() {
    local _warp_source_file="$1"

    [ -f "$_warp_source_file" ] || return 0
    warp_source_optional "$_warp_source_file" || return 1
    warp_mark_loaded "$_warp_source_file"
}

warp_source_optional_glob() {
    local _warp_glob_dir="$1"
    local _warp_glob_pattern="$2"
    local _warp_glob_file=""

    for _warp_glob_file in "$_warp_glob_dir"/$_warp_glob_pattern; do
        [ -e "$_warp_glob_file" ] || continue
        [ "${WARP_LOADED_FILES["$_warp_glob_file"]+set}" = "set" ] && continue
        warp_source_optional_marked "$_warp_glob_file" || return 1
    done
}

declare -A WARP_LOADED_FILES=()

# Minimal core required to consider .warp installed.
warp_source_required_marked "$WARPFOLDER/lib/env.sh" || return 1
warp_source_required_marked "$WARPFOLDER/lib/message.sh" || return 1
warp_source_required_marked "$WARPFOLDER/lib/net.sh" || return 1
warp_source_required_marked "$WARPFOLDER/lib/question.sh" || return 1
warp_source_required_marked "$WARPFOLDER/lib/check.sh" || return 1
warp_source_required_marked "$WARPFOLDER/lib/banner.sh" || return 1

# Optional libs can evolve between Warp versions. Keep priority order only where
# there are known dependencies, then autoload the rest tolerantly.
warp_source_optional_marked "$WARPFOLDER/lib/version.sh" || return 1
warp_source_optional_marked "$WARPFOLDER/lib/commit.sh" || return 1
warp_source_optional_marked "$WARPFOLDER/lib/host.sh" || return 1
warp_source_optional_marked "$WARPFOLDER/lib/fallback.sh" || return 1
warp_source_optional_marked "$WARPFOLDER/lib/service_version.sh" || return 1
warp_source_optional_marked "$WARPFOLDER/lib/app_context.sh" || return 1
warp_source_optional_marked "$WARPFOLDER/lib/service_context.sh" || return 1
warp_source_optional_glob "$WARPFOLDER/lib" "*.sh" || return 1

# Commands are loaded tolerantly so a newer binary can self-repair an older
# installed framework via `warp update` / `warp update --self`.
warp_source_optional_glob "$WARPFOLDER/bin" "*.sh" || return 1
