#!/bin/bash


##
# Read a variable from .env file located in root folder
# Use:
#    my_var=$(warp_env_read_var REDIS_CACHE_VERSION)
#    echo $my_var
#
# Globals:
#   PROJECTPATH
# Arguments:
#   $1 Var to read. Ex. REDIS_CACHE_VERSION
# Returns:
#   string
##
function warp_env_read_var()
{
    local _VAR=""
    [ -f "$ENVIRONMENTVARIABLESFILE" ] && _VAR=$(grep "^$1=" "$ENVIRONMENTVARIABLESFILE" | cut -d '=' -f2-)
    echo "$_VAR"
}

function warp_env_file_set_var()
{
    local _file="$1"
    local _key="$2"
    local _value="$3"
    local _tmp=""
    local _safe=""

    [ -n "$_file" ] || return 1
    [ -n "$_key" ] || return 1

    _tmp="${_file}.warp_tmp"
    _safe=$(printf '%s' "$_value" | sed 's/[\/&]/\\&/g')

    if [ -f "$_file" ] && grep -q "^${_key}=" "$_file" 2>/dev/null; then
        sed -e "s#^${_key}=.*#${_key}=${_safe}#g" "$_file" > "$_tmp" || return 1
        mv "$_tmp" "$_file" || return 1
    else
        [ -f "$_file" ] || : > "$_file" || return 1
        {
            echo ""
            echo "${_key}=${_value}"
        } >> "$_file" || return 1
    fi
}

function warp_env_ensure_var()
{
    local _key="$1"
    local _default="$2"

    [ -f "$ENVIRONMENTVARIABLESFILE" ] || return 1
    grep -q "^${_key}=" "$ENVIRONMENTVARIABLESFILE" 2>/dev/null && return 0
    warp_env_file_set_var "$ENVIRONMENTVARIABLESFILE" "$_key" "$_default"
}

# Generate RANDOM Password
# Globals:
#   PROJECTPATH
# Arguments:
#   $1 number long password to generate.
# Returns:
#   string
function warp_env_random_password()
{
    set="abcdefghijklmonpqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789=+"
    n=$1
    rand=""
    for i in $(seq 1 "$n"); do
        char=${set:$RANDOM % ${#set}:1}
        rand+=$char
    done
    echo "$rand"
}

function warp_env_random_name()
{
    set="abcdefghijklmonpqrstuvwxyz"
    n=$1
    rand=""
    for i in $(seq 1 "$n"); do
        char=${set:$RANDOM % ${#set}:1}
        rand+=$char
    done
    echo "$rand"
}

function warp_env_change_version_sample_file()
{
    WARP_ENV_VERSION=$(grep "^WARP_VERSION" "$ENVIRONMENTVARIABLESFILESAMPLE" | cut -d '=' -f2)
    _WARP_ENV_VERSION=$(echo "$WARP_ENV_VERSION" | tr -d ".")

    . "$PROJECTPATH/.warp/lib/version.sh"
    _WARP_VERSION=$(echo "$WARP_VERSION" | tr -d ".")

    if [ ! -z "$WARP_ENV_VERSION" ]
    then        
        # SAVE OPTION VERSION
        WARP_VERSION_OLD="WARP_VERSION=$WARP_ENV_VERSION"
        WARP_VERSION_NEW="WARP_VERSION=$WARP_VERSION"

        if [[ "$_WARP_ENV_VERSION" =~ ^[0-9]+$ ]] && [[ "$_WARP_VERSION" =~ ^[0-9]+$ ]] && [ "$_WARP_ENV_VERSION" -lt "$_WARP_VERSION" ] && [ ! "$_WARP_ENV_VERSION" -eq "$_WARP_VERSION" ]
        then
            sed -e "s/$WARP_VERSION_OLD/$WARP_VERSION_NEW/" "$ENVIRONMENTVARIABLESFILESAMPLE" > "$ENVIRONMENTVARIABLESFILESAMPLE.tmp"
            mv "$ENVIRONMENTVARIABLESFILESAMPLE.tmp" "$ENVIRONMENTVARIABLESFILESAMPLE"
        fi
    fi
}
