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

function warp_env_file_read_var()
{
    local _file="$1"
    local _key="$2"
    local _var=""

    [ -f "$_file" ] && _var=$(grep "^${_key}=" "$_file" | cut -d '=' -f2-)
    echo "$_var"
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

function warp_env_read_mail_binded_port()
{
    local _mail_binded_port=""

    _mail_binded_port=$(warp_env_read_var MAIL_BINDED_PORT)
    [ -n "$_mail_binded_port" ] || _mail_binded_port=$(warp_env_read_var MAILHOG_BINDED_PORT)

    echo "$_mail_binded_port"
}

function warp_env_file_sync_mail_binded_port()
{
    local _file="$1"
    local _default="${2:-}"
    local _canonical=""
    local _legacy=""
    local _resolved=""

    [ -n "$_file" ] || return 1
    [ -f "$_file" ] || return 0

    _canonical=$(warp_env_file_read_var "$_file" MAIL_BINDED_PORT)
    _legacy=$(warp_env_file_read_var "$_file" MAILHOG_BINDED_PORT)

    if [ -n "$_canonical" ]; then
        _resolved="$_canonical"
    elif [ -n "$_legacy" ]; then
        _resolved="$_legacy"
    else
        _resolved="$_default"
    fi

    [ -n "$_resolved" ] || return 0

    warp_env_file_set_var "$_file" MAIL_BINDED_PORT "$_resolved" || return 1

    if [ -n "$_legacy" ]; then
        warp_env_file_set_var "$_file" MAILHOG_BINDED_PORT "$_resolved" || return 1
    fi
}

function warp_mail_is_configured_in_file()
{
    local _file="$1"
    local _mail_engine=""
    local _mail_port=""
    local _mail_port_legacy=""

    [ -f "$_file" ] || return 1

    _mail_engine=$(warp_env_file_read_var "$_file" MAIL_ENGINE)
    _mail_port=$(warp_env_file_read_var "$_file" MAIL_BINDED_PORT)
    _mail_port_legacy=$(warp_env_file_read_var "$_file" MAILHOG_BINDED_PORT)

    [ -n "$_mail_engine" ] || [ -n "$_mail_port" ] || [ -n "$_mail_port_legacy" ]
}

function warp_mail_ensure_auth_files()
{
    local _env_file="${1:-$ENVIRONMENTVARIABLESFILE}"
    local _config_dir="$PROJECTPATH/.warp/docker/config/mail"
    local _setup_dir="$PROJECTPATH/.warp/setup/mailhog/config/mail"
    local _target_auth="$_config_dir/ui-auth.txt"
    local _target_sample="$_config_dir/ui-auth.txt.sample"
    local _source_auth="$_setup_dir/ui-auth.txt"
    local _source_sample="$_setup_dir/ui-auth.txt.sample"

    warp_mail_is_configured_in_file "$_env_file" || return 0

    mkdir -p "$_config_dir" || {
        warp_message_error "unable to create mail config directory: $_config_dir"
        return 1
    }

    [ -f "$_source_auth" ] || {
        warp_message_error "mail auth template not found: $_source_auth"
        return 1
    }

    [ -f "$_source_sample" ] || {
        warp_message_error "mail auth sample template not found: $_source_sample"
        return 1
    }

    [ -f "$_target_auth" ] || cp "$_source_auth" "$_target_auth" || {
        warp_message_error "unable to create mail auth file: $_target_auth"
        return 1
    }

    [ -f "$_target_sample" ] || cp "$_source_sample" "$_target_sample" || {
        warp_message_error "unable to create mail auth sample file: $_target_sample"
        return 1
    }
}

function warp_mail_ensure_env_defaults()
{
    local _file="$1"

    warp_mail_is_configured_in_file "$_file" || return 0

    warp_env_file_set_var "$_file" MAIL_ENGINE "${MAIL_ENGINE_DEFAULT:-mailpit}" || return 1
    warp_env_file_set_var "$_file" MAIL_VERSION "${MAIL_VERSION_DEFAULT:-v1.29}" || return 1
    warp_env_file_set_var "$_file" MAIL_MAX_MESSAGES "${MAIL_MAX_MESSAGES_DEFAULT:-100}" || return 1
    warp_env_file_sync_mail_binded_port "$_file" "${MAIL_BINDED_PORT_DEFAULT:-8025}" || return 1
}

function warp_mail_ensure_storage_dir()
{
    local _storage_dir="$PROJECTPATH/.warp/docker/volumes/mail"

    mkdir -p "$_storage_dir" || {
        warp_message_error "unable to create mail storage directory: $_storage_dir"
        return 1
    }
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
