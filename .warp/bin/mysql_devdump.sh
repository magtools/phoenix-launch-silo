#!/bin/bash

mysql_devdump_profiles_dir() {
    echo "$PROJECTPATH/.warp/bin/mysql/devdump/profiles"
}

mysql_devdump_list_apps() {
    _dir=$(mysql_devdump_profiles_dir)
    [ -d "$_dir" ] || return 0
    ls "$_dir"/*.tables.txt 2>/dev/null | xargs -n1 basename 2>/dev/null | awk -F. '{print $1}' | sort -u
}

mysql_devdump_list_profiles_for_app() {
    _app="$1"
    _dir=$(mysql_devdump_profiles_dir)
    ls "$_dir/${_app}."*.tables.txt 2>/dev/null | sort
}

mysql_devdump_help() {
    warp_message ""
    warp_message_info "Usage:"
    warp_message " warp db devdump"
    warp_message " warp db devdump:<app>"
    warp_message ""
    warp_message_info "Help:"
    warp_message " Generate lightweight development dumps using exclusion profiles."
    warp_message " Uses database settings from .env (local container or MYSQL_VERSION=rds)."
    warp_message ""
    warp_message_info "Available apps:"
    _apps=$(mysql_devdump_list_apps)
    if [ -z "$_apps" ]; then
        warp_message_warn " no apps configured (profiles folder empty)."
    else
        echo "$_apps" | while IFS= read -r _a; do
            [ -z "$_a" ] && continue
            warp_message " - $_a"
        done
    fi
    warp_message ""
    warp_message_info "Examples:"
    warp_message " warp db devdump"
    warp_message " warp db devdump:magento"
    warp_message ""
}

mysql_devdump_output_dir_for_app() {
    _app="$1"
    if [ "$_app" = "magento" ]; then
        mkdir -p "$PROJECTPATH/var" 2>/dev/null || true
        if [ -d "$PROJECTPATH/var" ]; then
            echo "$PROJECTPATH/var"
            return 0
        fi
    fi
    pwd
}

mysql_devdump_prepare_context() {
    _app="$1"
    if ! warp_check_env_file ; then
        warp_message_error "file not found $(basename "$ENVIRONMENTVARIABLESFILE")"
        return 1
    fi

    DB_NAME=$(warp_env_read_var DATABASE_NAME)
    [ -z "$DB_NAME" ] && warp_message_error "DATABASE_NAME is empty in .env" && return 1

    mysql_external_bootstrap_if_needed || return 1

    if [ "$(mysql_external_mode_enabled)" = "true" ]; then
        mysql_ensure_external_clients || { warp_message_error "SQL client tools are required."; return 1; }
        mysql_load_external_conn_values
        DUMP_BIN=$(mysql_pick_external_dump_bin)
        [ -z "$DUMP_BIN" ] && warp_message_error "mysqldump/mariadb-dump not found" && return 1
        [ -z "$DB_HOST" ] && warp_message_error "DATABASE_HOST is empty in .env" && return 1
        [ -z "$DB_USER" ] && warp_message_error "DATABASE_USER is empty in .env" && return 1
        [ -z "$DB_PASSWORD" ] && warp_message_error "DATABASE_PASSWORD is empty in .env" && return 1
        MODE="external"
    else
        if [ "$(warp_check_is_running)" = false ]; then
            warp_message_error "The containers are not running"
            warp_message_error "please, first run warp start"
            return 1
        fi
        DATABASE_ROOT_PASSWORD=$(warp_env_read_var DATABASE_ROOT_PASSWORD)
        [ -z "$DATABASE_ROOT_PASSWORD" ] && warp_message_error "DATABASE_ROOT_PASSWORD is empty in .env" && return 1
        DUMP_BIN=$(warp_mysql_dump_bin)
        MODE="container"
    fi

    OUT_DIR=$(mysql_devdump_output_dir_for_app "$_app")
    TS=$(date +"%Y%m%d_%H%M")
    SQL_FILE="$OUT_DIR/${DB_NAME}_devdump_${TS}.sql"
    GZ_FILE="${SQL_FILE}.gz"
    IGNORE_FILE="$OUT_DIR/.${DB_NAME}_devdump_ignore_${TS}.tmp"
}

mysql_devdump_render_ignore_args() {
    _source_file="$1"
    _db="$2"
    _output_file="$3"
    > "$_output_file"
    awk '
        /^[[:space:]]*#/ { next }
        /^[[:space:]]*$/ { next }
        { gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0); print $0 }
    ' "$_source_file" | sort -u | while IFS= read -r _table; do
        [ -z "$_table" ] && continue
        echo "--ignore-table=${_db}.${_table}" >> "$_output_file"
    done
}

mysql_devdump_pick_profile_file() {
    _app="$1"
    _files="$2"
    MYSQL_DEVDUMP_PICKED_PROFILE=""
    _count=$(echo "$_files" | sed '/^$/d' | wc -l | awk '{print $1}')

    if [ "$_count" -le 1 ]; then
        MYSQL_DEVDUMP_PICKED_PROFILE=$(echo "$_files" | sed '/^$/d' | head -n1)
        return 0
    fi

    warp_message ""
    warp_message_info "Profiles for app '${_app}':"
    _i=1
    echo "$_files" | sed '/^$/d' | while IFS= read -r _f; do
        _profile=$(basename "$_f")
        _profile="${_profile#${_app}.}"
        _profile="${_profile%.tables.txt}"
        warp_message " ${_i}) ${_profile}"
        _i=$((_i + 1))
    done
    warp_message ""
    warp_message " 0) all profiles together"
    warp_message ""

    _default="1"
    _pick=$(warp_question_ask_default "Select profile number (0 for all): " "$_default")
    if [ "$_pick" = "0" ]; then
        MYSQL_DEVDUMP_PICKED_PROFILE="__ALL__"
        return 0
    fi

    if ! [[ "$_pick" =~ ^[0-9]+$ ]]; then
        warp_message_warn "Invalid option. Using profile 1."
        _pick=1
    fi

    _sel=$(echo "$_files" | sed '/^$/d' | sed -n "${_pick}p")
    if [ -z "$_sel" ]; then
        warp_message_warn "Invalid option. Using profile 1."
        _sel=$(echo "$_files" | sed '/^$/d' | head -n1)
    fi
    MYSQL_DEVDUMP_PICKED_PROFILE="$_sel"
}

mysql_devdump_dump_structure() {
    if [ "$MODE" = "external" ]; then
        "$DUMP_BIN" -h"$DB_HOST" -P"$DB_PORT" -u"$DB_USER" -p"$DB_PASSWORD" --single-transaction --no-data "$DB_NAME" > "$SQL_FILE"
    else
        docker-compose -f "$DOCKERCOMPOSEFILE" exec -T mysql bash -lc "CMD=\"$DUMP_BIN\"; command -v \"\$CMD\" >/dev/null 2>&1 || CMD=\"mysqldump\"; \"\$CMD\" -uroot -p$DATABASE_ROOT_PASSWORD --single-transaction --no-data \"$DB_NAME\"" > "$SQL_FILE"
    fi
}

mysql_devdump_dump_data() {
    _ignore_args=$(cat "$IGNORE_FILE" | tr '\n' ' ')
    if [ "$MODE" = "external" ]; then
        "$DUMP_BIN" -h"$DB_HOST" -P"$DB_PORT" -u"$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" $_ignore_args >> "$SQL_FILE"
    else
        docker-compose -f "$DOCKERCOMPOSEFILE" exec -T mysql bash -lc "CMD=\"$DUMP_BIN\"; command -v \"\$CMD\" >/dev/null 2>&1 || CMD=\"mysqldump\"; \"\$CMD\" -uroot -p$DATABASE_ROOT_PASSWORD \"$DB_NAME\" $_ignore_args" >> "$SQL_FILE"
    fi
}

mysql_devdump_cleanup_definers() {
    sed -E 's/DEFINER=[^*]*\*/\*/g' "$SQL_FILE" > "${SQL_FILE}.tmp" && mv "${SQL_FILE}.tmp" "$SQL_FILE"
}

mysql_devdump_run() {
    _app="$1"
    _profiles_dir=$(mysql_devdump_profiles_dir)
    _files=$(mysql_devdump_list_profiles_for_app "$_app")
    if [ -z "$_files" ]; then
        warp_message_error "No profile files found for app '${_app}' in ${_profiles_dir}"
        return 1
    fi

    mysql_devdump_prepare_context "$_app" || return 1

    mysql_devdump_pick_profile_file "$_app" "$_files" || return 1
    _picked="$MYSQL_DEVDUMP_PICKED_PROFILE"
    if [ "$_picked" = "__ALL__" ]; then
        _combined="$OUT_DIR/.${_app}_all_profiles_${TS}.tmp"
        > "$_combined"
        echo "$_files" | sed '/^$/d' | while IFS= read -r _f; do
            cat "$_f" >> "$_combined"
            echo "" >> "$_combined"
        done
        mysql_devdump_render_ignore_args "$_combined" "$DB_NAME" "$IGNORE_FILE"
        rm -f "$_combined" 2>/dev/null || true
    else
        mysql_devdump_render_ignore_args "$_picked" "$DB_NAME" "$IGNORE_FILE"
    fi

    warp_message_info2 "Creating devdump for app '${_app}'"
    warp_message "Output SQL: $(warp_message_info "$SQL_FILE")"
    warp_message "Output GZ:  $(warp_message_info "$GZ_FILE")"
    warp_message "Mode:       $(warp_message_info "$MODE")"

    mysql_devdump_dump_structure || return 1
    mysql_devdump_dump_data || return 1
    mysql_devdump_cleanup_definers || return 1
    gzip -c "$SQL_FILE" > "$GZ_FILE" || return 1

    rm -f "$IGNORE_FILE" 2>/dev/null || true
    warp_message_ok "devdump generated"
    return 0
}

mysql_devdump_main() {
    _cmd="$1"
    if [ -z "$_cmd" ] || [ "$_cmd" = "-h" ] || [ "$_cmd" = "--help" ]; then
        mysql_devdump_help
        return 0
    fi

    case "$_cmd" in
        devdump:*)
            _app="${_cmd#devdump:}"
            [ -z "$_app" ] && mysql_devdump_help && return 1
            mysql_devdump_run "$_app"
        ;;
        *)
            mysql_devdump_help
            return 1
        ;;
    esac
}
