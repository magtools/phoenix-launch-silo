#!/bin/bash

    # IMPORT HELP

. "$PROJECTPATH/.warp/bin/mysql_help.sh"
[ -f "$PROJECTPATH/.warp/bin/mysql_devdump.sh" ] && . "$PROJECTPATH/.warp/bin/mysql_devdump.sh"

function mysql_info()
{

    if ! warp_check_env_file ; then
        warp_message_error "file not found $(basename $ENVIRONMENTVARIABLESFILE)"
        exit
    fi; 

    DATABASE_NAME=$(warp_env_read_var DATABASE_NAME)
    DATABASE_USER=$(warp_env_read_var DATABASE_USER)
    DATABASE_PASSWORD=$(warp_env_read_var DATABASE_PASSWORD)
    DATABASE_ROOT_PASSWORD=$(warp_env_read_var DATABASE_ROOT_PASSWORD)
    DATABASE_BINDED_PORT=$(warp_env_read_var DATABASE_BINDED_PORT)
    MYSQL_CONFIG_FILE=$(warp_env_read_var MYSQL_CONFIG_FILE)
    MYSQL_VERSION=$(warp_env_read_var MYSQL_VERSION)
    MODE_SANDBOX=$(warp_env_read_var MODE_SANDBOX)

    if [ "$MODE_SANDBOX" = "Y" ] || [ "$MODE_SANDBOX" = "y" ] ; then 
        DATABASE_USER=null
        DATABASE_PASSWORD=null
    fi

    if [ ! -z "$DATABASE_ROOT_PASSWORD" ]
    then
        warp_message ""
        warp_message_info "* MySQL"
        warp_message "Database Name:              $(warp_message_info $DATABASE_NAME)"
        warp_message "Host: (container)           $(warp_message_info mysql)"
        warp_message "Username:                   $(warp_message_info $DATABASE_USER)"
        warp_message "Password:                   $(warp_message_info $DATABASE_PASSWORD)"
        warp_message "Root user:                  $(warp_message_info root)"
        warp_message "Root password:              $(warp_message_info $DATABASE_ROOT_PASSWORD)"
        warp_message "Binded port (host):         $(warp_message_info $DATABASE_BINDED_PORT)"
        warp_message "MySQL version:              $(warp_message_info $MYSQL_VERSION)"
        warp_message "my.cnf location:            $(warp_message_info $PROJECTPATH/.warp/docker/config/mysql/my.cnf)"
        warp_message "Other config files:         $(warp_message_info $MYSQL_CONFIG_FILE)"
        warp_message "Dumps folder (host):        $(warp_message_info $PROJECTPATH/.warp/docker/dumps)" 
        warp_message "Dumps folder (container):   $(warp_message_info /dumps)"
        warp_message ""
        warp_message_warn " - prevent to use 127.0.0.1 or localhost as database host.  Instead of 127.0.0.1 use: $(warp_message_bold 'mysql')"
        warp_message ""
    fi
}

warp_mysql_flavor() {
    MYSQL_DOCKER_IMAGE=$(warp_env_read_var MYSQL_DOCKER_IMAGE)
    case "$MYSQL_DOCKER_IMAGE" in
        mariadb:*|*/mariadb:*|*mariadb*)
            echo "mariadb"
            ;;
        *)
            echo "mysql"
            ;;
    esac
}

warp_mysql_client_bin() {
    if [ "$(warp_mysql_flavor)" = "mariadb" ]; then
        echo "mariadb"
    else
        echo "mysql"
    fi
}

warp_mysql_dump_bin() {
    if [ "$(warp_mysql_flavor)" = "mariadb" ]; then
        echo "mariadb-dump"
    else
        echo "mysqldump"
    fi
}

mysql_compose_has_mysql_service() {
    if [ ! -f "$DOCKERCOMPOSEFILE" ]; then
        echo false
        return 0
    fi

    if docker-compose -f "$DOCKERCOMPOSEFILE" config --services 2>/dev/null | grep -qx "mysql"; then
        echo true
        return 0
    fi

    if grep -Eq '^[[:space:]]*mysql:[[:space:]]*$' "$DOCKERCOMPOSEFILE"; then
        echo true
    else
        echo false
    fi
}

mysql_env_set_var() {
    _key="$1"
    _value="$2"
    _tmp="$ENVIRONMENTVARIABLESFILE.warp_tmp"
    _safe=$(printf '%s' "$_value" | sed -e 's/[\/&#]/\\&/g')

    if grep -q "^${_key}=" "$ENVIRONMENTVARIABLESFILE" 2>/dev/null; then
        sed -e "s#^${_key}=.*#${_key}=${_safe}#g" "$ENVIRONMENTVARIABLESFILE" > "$_tmp"
        mv "$_tmp" "$ENVIRONMENTVARIABLESFILE"
    else
        echo "${_key}=${_value}" >> "$ENVIRONMENTVARIABLESFILE"
    fi
}

mysql_read_envphp_db_default_field() {
    _file="$1"
    _field="$2"

    awk -v field="$_field" '
        function line_delta(text,    opens, closes, tmp) {
            tmp = text
            opens = gsub(/\[/, "[", tmp)
            tmp = text
            closes = gsub(/\]/, "]", tmp)
            return opens - closes
        }

        {
            delta = line_delta($0)

            if (!in_db && $0 ~ /'\''db'\''[[:space:]]*=>[[:space:]]*\[/) {
                in_db = 1
                db_depth = depth + delta
            } else if (in_db && !in_connection && $0 ~ /'\''connection'\''[[:space:]]*=>[[:space:]]*\[/) {
                in_connection = 1
                connection_depth = depth + delta
            } else if (in_connection && !in_default && $0 ~ /'\''default'\''[[:space:]]*=>[[:space:]]*\[/) {
                in_default = 1
                default_depth = depth + delta
            }

            if (in_default) {
                pattern = "'"'"'" field "'\''[[:space:]]*=>[[:space:]]*'\''([^'\'']*)'\''"
                if (match($0, pattern)) {
                    value = substr($0, RSTART, RLENGTH)
                    sub(/^.*=>[[:space:]]*'\''/, "", value)
                    sub(/'\''$/, "", value)
                    print value
                    exit
                }
            }

            depth += delta

            if (in_default && depth < default_depth) {
                in_default = 0
            }
            if (in_connection && depth < connection_depth) {
                in_connection = 0
            }
            if (in_db && depth < db_depth) {
                in_db = 0
            }
        }
    ' "$_file" 2>/dev/null
}

mysql_external_collect_from_envphp() {
    _envphp="$PROJECTPATH/app/etc/env.php"
    [ -f "$_envphp" ] || return 1

    _host=$(mysql_read_envphp_db_default_field "$_envphp" "host")
    _port=$(mysql_read_envphp_db_default_field "$_envphp" "port")
    _dbname=$(mysql_read_envphp_db_default_field "$_envphp" "dbname")
    _user=$(mysql_read_envphp_db_default_field "$_envphp" "username")
    _password=$(mysql_read_envphp_db_default_field "$_envphp" "password")

    if [ -z "$_port" ] && [[ "$_host" == *:* ]]; then
        _host_port="${_host##*:}"
        _host_only="${_host%:*}"
        if [[ "$_host_port" =~ ^[0-9]+$ ]]; then
            _port="$_host_port"
            _host="$_host_only"
        fi
    fi

    [ -z "$_port" ] && _port="3306"

    if [ -n "$_host" ] && [ -n "$_dbname" ] && [ -n "$_user" ] && [ -n "$_password" ]; then
        echo "host=$_host"
        echo "port=$_port"
        echo "dbname=$_dbname"
        echo "user=$_user"
        echo "password=$_password"
        return 0
    fi

    return 1
}

mysql_prompt_required() {
    _label="$1"
    _default="$2"
    _v=""
    while :; do
        _v=$(warp_question_ask_default "$_label " "$_default")
        _v=$(echo "$_v" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        [ -n "$_v" ] && { echo "$_v"; return 0; }
        warp_message_warn "Value required."
    done
}

mysql_external_bootstrap_if_needed() {
    MYSQL_VERSION_CURRENT=$(warp_env_read_var MYSQL_VERSION)
    MYSQL_HAS_SERVICE=$(mysql_compose_has_mysql_service)

    if [ "$MYSQL_VERSION_CURRENT" = "rds" ]; then
        return 0
    fi

    if [ "$MYSQL_HAS_SERVICE" = "true" ]; then
        return 0
    fi

    _answer=$(warp_question_ask_default "MySQL service not found in docker-compose. Is the database external? $(warp_message_info [Y/n]) " "Y")
    if [ "$_answer" != "Y" ] && [ "$_answer" != "y" ]; then
        warp_message_error "MySQL service is not configured and external mode was not confirmed."
        return 1
    fi

    _host=""
    _port=""
    _dbname=""
    _user=""
    _password=""

    if _data=$(mysql_external_collect_from_envphp); then
        _host=$(echo "$_data" | awk -F= '/^host=/{print substr($0,6)}')
        _port=$(echo "$_data" | awk -F= '/^port=/{print substr($0,6)}')
        _dbname=$(echo "$_data" | awk -F= '/^dbname=/{print substr($0,8)}')
        _user=$(echo "$_data" | awk -F= '/^user=/{print substr($0,6)}')
        _password=$(echo "$_data" | awk -F= '/^password=/{print substr($0,10)}')

        if [ "$_host" = "mysql" ]; then
            _keep_mysql_host=$(warp_question_ask_default "env.php reports host=mysql but mysql service is missing. Keep this host? $(warp_message_info [y/N]) " "N")
            if [ "$_keep_mysql_host" != "y" ] && [ "$_keep_mysql_host" != "Y" ]; then
                _host=""
            fi
        fi
    fi

    [ -z "$_host" ] && _host=$(mysql_prompt_required "DATABASE_HOST (external host/IP):" "")
    [ -z "$_port" ] && _port=$(mysql_prompt_required "DATABASE_BINDED_PORT:" "3306")
    [ -z "$_dbname" ] && _dbname=$(mysql_prompt_required "DATABASE_NAME:" "")
    [ -z "$_user" ] && _user=$(mysql_prompt_required "DATABASE_USER:" "")
    [ -z "$_password" ] && _password=$(mysql_prompt_required "DATABASE_PASSWORD:" "")

    mysql_env_set_var "MYSQL_VERSION" "rds"
    mysql_env_set_var "DATABASE_HOST" "$_host"
    mysql_env_set_var "DATABASE_BINDED_PORT" "$_port"
    mysql_env_set_var "DATABASE_NAME" "$_dbname"
    mysql_env_set_var "DATABASE_USER" "$_user"
    mysql_env_set_var "DATABASE_PASSWORD" "$_password"

    warp_message_ok "External DB settings updated in $(basename "$ENVIRONMENTVARIABLESFILE")"
    return 0
}

mysql_external_mode_enabled() {
    [ "$(warp_env_read_var MYSQL_VERSION)" = "rds" ] && echo true || echo false
}

mysql_detect_distro_id() {
    if [ -r /etc/os-release ]; then
        awk -F= '/^ID=/{gsub(/"/,"",$2); print tolower($2)}' /etc/os-release
        return 0
    fi
    echo ""
}

mysql_pick_external_client_bin() {
    if command -v mariadb >/dev/null 2>&1; then
        echo "mariadb"
        return 0
    fi
    if command -v mysql >/dev/null 2>&1; then
        echo "mysql"
        return 0
    fi
    echo ""
}

mysql_pick_external_dump_bin() {
    if command -v mariadb-dump >/dev/null 2>&1; then
        echo "mariadb-dump"
        return 0
    fi
    if command -v mysqldump >/dev/null 2>&1; then
        echo "mysqldump"
        return 0
    fi
    echo ""
}

mysql_try_install_sql_client() {
    MYSQL_FLAVOR=$(warp_mysql_flavor)
    DISTRO_ID=$(mysql_detect_distro_id)

    case "$DISTRO_ID" in
        debian|ubuntu)
            if [ "$MYSQL_FLAVOR" = "mariadb" ]; then
                _pkg="mariadb-client"
            else
                _pkg="mysql-client"
            fi
            sudo apt-get install -y "$_pkg" 2>/dev/null || apt-get install -y "$_pkg"
        ;;
        amzn|amazon|rhel|centos|fedora|rocky|almalinux)
            if [ "$MYSQL_FLAVOR" = "mariadb" ]; then
                _pkg="mariadb"
            else
                _pkg="mysql"
            fi
            if command -v dnf >/dev/null 2>&1; then
                sudo dnf install -y "$_pkg" 2>/dev/null || dnf install -y "$_pkg"
            else
                sudo yum install -y "$_pkg" 2>/dev/null || yum install -y "$_pkg"
            fi
        ;;
        opensuse*|sles|suse)
            if [ "$MYSQL_FLAVOR" = "mariadb" ]; then
                _pkg="mariadb-client"
            else
                _pkg="mysql-client"
            fi
            sudo zypper --non-interactive install "$_pkg" 2>/dev/null || zypper --non-interactive install "$_pkg"
        ;;
        *)
            return 1
        ;;
    esac
}

mysql_ensure_external_clients() {
    _client=$(mysql_pick_external_client_bin)
    _dump=$(mysql_pick_external_dump_bin)
    if [ -n "$_client" ] && [ -n "$_dump" ]; then
        return 0
    fi

    _answer=$(warp_question_ask_default "MySQL/MariaDB client tools not found. Install now? $(warp_message_info [Y/n]) " "Y")
    if [ "$_answer" != "Y" ] && [ "$_answer" != "y" ]; then
        return 1
    fi

    if ! mysql_try_install_sql_client; then
        MYSQL_FLAVOR=$(warp_mysql_flavor)
        DISTRO_ID=$(mysql_detect_distro_id)
        warp_message_warn "Could not auto-install SQL client tools."
        warp_message_warn "Detected distro: ${DISTRO_ID:-unknown}"
        if [ "$MYSQL_FLAVOR" = "mariadb" ]; then
            warp_message_warn "Try manually: mariadb-client (Debian/openSUSE) or mariadb (Amazon/RHEL)"
        else
            warp_message_warn "Try manually: mysql-client (Debian/openSUSE) or mysql (Amazon/RHEL)"
        fi
        return 1
    fi

    _client=$(mysql_pick_external_client_bin)
    _dump=$(mysql_pick_external_dump_bin)
    [ -n "$_client" ] && [ -n "$_dump" ]
}

mysql_load_external_conn_values() {
    DB_HOST=$(warp_env_read_var DATABASE_HOST)
    DB_PORT=$(warp_env_read_var DATABASE_BINDED_PORT)
    DB_NAME=$(warp_env_read_var DATABASE_NAME)
    DB_USER=$(warp_env_read_var DATABASE_USER)
    DB_PASSWORD=$(warp_env_read_var DATABASE_PASSWORD)
    [ -z "$DB_PORT" ] && DB_PORT=3306
}

mysql_print_external_connection_details() {
    _reason="$1"

    warp_message ""
    warp_message_warn "External DB connection failed."
    [ -n "$_reason" ] && warp_message_warn "Reason: $_reason"
    warp_message "Host:                       $(warp_message_info ${DB_HOST:-[not set]})"
    warp_message "Port:                       $(warp_message_info ${DB_PORT:-3306})"
    warp_message "Database:                   $(warp_message_info ${DB_NAME:-[not set]})"
    [ -n "$DB_USER" ] && warp_message "User:                       $(warp_message_info ${DB_USER})" || warp_message "User:                       $(warp_message_warn [not set])"
    [ -n "$DB_PASSWORD" ] && warp_message "Password:                   $(warp_message_info ********)" || warp_message "Password:                   $(warp_message_warn [not set])"
    warp_message_warn "Review the DB connection settings in $(basename "$ENVIRONMENTVARIABLESFILE")."
    warp_message ""
}

mysql_load_context() {
    mysql_external_bootstrap_if_needed || true
    warp_fallback_bootstrap_if_needed db >/dev/null 2>&1 || true
    warp_service_context_load db >/dev/null 2>&1 || true
}

mysql_exec_local_query() {
    local _sql="$1"
    local _root_password=""
    local _client_bin=""

    _root_password=$(warp_env_read_var DATABASE_ROOT_PASSWORD)
    _client_bin=$(warp_mysql_client_bin)

    docker-compose -f "$DOCKERCOMPOSEFILE" exec -T mysql "$_client_bin" \
        -uroot \
        "--password=$_root_password" \
        --batch \
        --skip-column-names \
        -e "$_sql"
}

mysql_exec_external_query() {
    local _sql="$1"
    local _client_bin=""

    mysql_load_external_conn_values
    _client_bin=$(mysql_pick_external_client_bin)

    [ -n "$_client_bin" ] || {
        warp_message_error "SQL client tools are required for external DB health checks."
        warp_message_warn "Install mysql or mariadb client tools and retry."
        return 1
    }
    [ -n "$DB_HOST" ] || {
        warp_message_error "DATABASE_HOST is empty in .env"
        return 1
    }
    [ -n "$DB_USER" ] || {
        warp_message_error "DATABASE_USER is empty in .env"
        return 1
    }
    [ -n "$DB_PASSWORD" ] || {
        warp_message_error "DATABASE_PASSWORD is empty in .env"
        return 1
    }

    "$_client_bin" \
        -h"$DB_HOST" \
        -P"$DB_PORT" \
        -u"$DB_USER" \
        "--password=$DB_PASSWORD" \
        --batch \
        --skip-column-names \
        -e "$_sql"
}

mysql_system_schema() {
    case "$1" in
        information_schema|mysql|performance_schema|sys)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

mysql_health() {
    local _mode=""
    local _engine=""
    local _version=""
    local _query=""
    local _rows=""
    local _rc=0
    local _overall="ok"
    local _app_schema_count=0
    local _line=""
    local _schema=""
    local _tables=""
    local _selected_marker=""
    local _system_note=""

    if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
        mysql_health_help
        return 0
    fi

    if ! warp_check_env_file; then
        warp_message_error "file not found $(basename "$ENVIRONMENTVARIABLESFILE")"
        return 1
    fi

    mysql_load_context
    _mode="${WARP_CTX_MODE:-unknown}"
    _engine="${WARP_CTX_ENGINE:-$(warp_mysql_flavor)}"

    if [ "$_mode" = "local" ]; then
        if [ "$(warp_check_is_running)" = "false" ]; then
            warp_message_error "The containers are not running"
            warp_message_error "please, first run warp start"
            return 1
        fi
        _version=$(mysql_exec_local_query "SELECT VERSION();" 2>/dev/null | head -n1 | tr -d '\r')
        _rc=$?
        if [ "$_rc" -ne 0 ] || [ -z "$_version" ]; then
            warp_message_error "DB health check failed."
            warp_message_error "Could not query the local mysql service."
            return 1
        fi
        _query='SELECT s.SCHEMA_NAME, COUNT(t.TABLE_NAME) AS table_count FROM information_schema.SCHEMATA s LEFT JOIN information_schema.TABLES t ON t.TABLE_SCHEMA = s.SCHEMA_NAME GROUP BY s.SCHEMA_NAME ORDER BY s.SCHEMA_NAME;'
        _rows=$(mysql_exec_local_query "$_query" 2>/dev/null)
        _rc=$?
    else
        _version=$(mysql_exec_external_query "SELECT VERSION();" 2>/dev/null | head -n1 | tr -d '\r')
        _rc=$?
        if [ "$_rc" -ne 0 ] || [ -z "$_version" ]; then
            mysql_print_external_connection_details "SQL client could not reach the external endpoint."
            return 1
        fi
        _query='SELECT s.SCHEMA_NAME, COUNT(t.TABLE_NAME) AS table_count FROM information_schema.SCHEMATA s LEFT JOIN information_schema.TABLES t ON t.TABLE_SCHEMA = s.SCHEMA_NAME GROUP BY s.SCHEMA_NAME ORDER BY s.SCHEMA_NAME;'
        _rows=$(mysql_exec_external_query "$_query" 2>/dev/null)
        _rc=$?
        if [ "$_rc" -ne 0 ]; then
            mysql_print_external_connection_details "Could not enumerate schemas on the external DB."
            return 1
        fi
    fi

    [ "$_rc" -ne 0 ] && return "$_rc"

    while IFS=$'\t' read -r _schema _tables; do
        [ -z "$_schema" ] && continue
        if ! mysql_system_schema "$_schema"; then
            _app_schema_count=$((_app_schema_count + 1))
        fi
    done <<EOF
$_rows
EOF

    if [ "$_app_schema_count" -eq 0 ]; then
        _overall="warn"
    fi

    warp_message ""
    warp_message_info "DB health: ${_overall}"
    warp_message "Engine:                     $(warp_message_info "$_engine")"
    warp_message "Version:                    $(warp_message_info "$_version")"
    warp_message "Mode:                       $(warp_message_info "${_mode}")"
    warp_message "Endpoint:                   $(warp_message_info "${WARP_CTX_HOST:-mysql}:${WARP_CTX_PORT:-3306}")"
    [ -n "$WARP_CTX_DBNAME" ] && warp_message "Selected database:          $(warp_message_info "$WARP_CTX_DBNAME")"
    warp_message ""
    warp_message_info "Databases:"

    while IFS=$'\t' read -r _schema _tables; do
        [ -z "$_schema" ] && continue
        _selected_marker=""
        _system_note=""
        [ -z "$_tables" ] && _tables="0"
        if [ -n "$WARP_CTX_DBNAME" ] && [ "$_schema" = "$WARP_CTX_DBNAME" ]; then
            _selected_marker=" (selected)"
        fi
        if mysql_system_schema "$_schema"; then
            _system_note=" system"
            warp_message " - ${_schema}:${_selected_marker}$(warp_message_info "${_system_note}")"
        else
            warp_message " - ${_schema}: $(warp_message_info "${_tables} tables")${_selected_marker}"
        fi
    done <<EOF
$_rows
EOF

    warp_message ""
    return 0
}

function mysql_connect()
{

    if [ "$1" = "-h" ] || [ "$1" = "--help" ]
    then
        mysql_connect_help
        exit 1
    fi;

    if ! warp_check_env_file ; then
        warp_message_error "file not found $(basename $ENVIRONMENTVARIABLESFILE)"
        exit 1
    fi

    mysql_external_bootstrap_if_needed || exit 1

    if [ "$(mysql_external_mode_enabled)" = "true" ]; then
        mysql_ensure_external_clients || { warp_message_error "SQL client tools are required."; exit 1; }
        mysql_load_external_conn_values
        MYSQL_CLIENT_BIN=$(mysql_pick_external_client_bin)
        [ -z "$DB_HOST" ] && warp_message_error "DATABASE_HOST is empty in .env" && exit 1
        [ -z "$DB_USER" ] && warp_message_error "DATABASE_USER is empty in .env" && exit 1
        [ -z "$DB_PASSWORD" ] && warp_message_error "DATABASE_PASSWORD is empty in .env" && exit 1
        "$MYSQL_CLIENT_BIN" -h"$DB_HOST" -P"$DB_PORT" -u"$DB_USER" -p"$DB_PASSWORD" "$DB_NAME"
        _rc=$?
        if [ "$_rc" -ne 0 ]; then
            mysql_print_external_connection_details "$MYSQL_CLIENT_BIN returned exit code ${_rc}."
        fi
        return "$_rc"
    fi

    if [ $(warp_check_is_running) = false ]; then
        warp_message_error "The containers are not running"
        warp_message_error "please, first run warp start"
        exit 1;
    fi

    DATABASE_ROOT_PASSWORD=$(warp_env_read_var DATABASE_ROOT_PASSWORD)
    MYSQL_CLIENT_BIN=$(warp_mysql_client_bin)
    docker-compose -f $DOCKERCOMPOSEFILE exec mysql bash -c "CMD=\"$MYSQL_CLIENT_BIN\"; command -v \"\$CMD\" >/dev/null 2>&1 || CMD=\"mysql\"; \"\$CMD\" -uroot -p$DATABASE_ROOT_PASSWORD"
}

function mysql_update_db()
{

    DOCKER_PRIVATE_REGISTRY=$(warp_env_read_var DOCKER_PRIVATE_REGISTRY)

    if [ -z "$DOCKER_PRIVATE_REGISTRY" ] ; then
        warp_message_error "this command only work with private db registry"

        exit 1;
    fi

    warp_message "This command will do:"
    warp_message "* stop containers"
    warp_message "* pull new images"
    warp_message "* remove volume db"
    warp_message "* start containers"

    respuesta_update_db=$( warp_question_ask_default "Do you want to continue? $(warp_message_info [Y/n]) " "Y" )

    if [ "$respuesta_update_db" = "Y" ] || [ "$respuesta_update_db" = "y" ]
    then

        if [ $(warp_check_is_running) = true ]; then
            warp stop --hard
        fi

        #  CHECK IF GITIGNOREFILE CONTAINS FILES WARP TO IGNORE
        [ -f "$HOME/.aws/credentials" ] && cat "$HOME/.aws/credentials" | grep --quiet -w "^[summa-docker]"

        # Exit status 0 means string was found
        # Exit status 1 means string was not found
        if [ $? = 0 ] || [ -f "$HOME/.aws/credentials" ]
        then

            # there are two versions of the AWS client in our infrastructure,
            # this get-login help command only works on the old version, so if it works, run the old one.
            echo "Logging into ECR"
            if aws ecr get-login help &> /dev/null
            then
              $(aws ecr get-login --region us-east-1 --no-include-email --profile summa-docker)
            else
              aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin $DOCKER_PRIVATE_REGISTRY
            fi

            # check if login Succeeded
            if [ $? = 0 ]
            then
                warp docker pull
                warp volume --rm mysql 2> /dev/null
                warp start
            fi
        fi
    else
        warp_message_warn "* aborting update database"
    fi
}

function mysql_connect_ssh()
{

    if [ "$1" = "-h" ] || [ "$1" = "--help" ]
    then
        mysql_ssh_help
        exit 1
    fi;

    if [ $(warp_check_is_running) = false ]; then
        warp_message_error "The containers are not running"
        warp_message_error "please, first run warp start"

        exit 1;
    fi

    docker-compose -f $DOCKERCOMPOSEFILE exec mysql bash -c "export COLUMNS=`tput cols`; export LINES=`tput lines`; exec bash"
}

function mysql_switch()
{
    local mysql_version_requested
    local mysql_version_current

    if [ "$1" = "-h" ] || [ "$1" = "--help" ] || [ -z "$1" ]
    then
        mysql_switch_help
        exit 1
    fi;

    if [ $(warp_check_is_running) = true ]; then
        warp_message_error "The containers are running"
        warp_message_error "please, first run warp stop --hard"

        exit 1;
    fi

    mysql_version_requested="$1"
    mysql_version_current=$(warp_env_read_var MYSQL_VERSION)
    warp_message_info2 "You current MySQL version is: $mysql_version_current"

    if [ "$mysql_version_current" = "$mysql_version_requested" ]
    then
        warp_message_info2 "the selected version is the same as the previous one, no changes will be made"
        warp_message_warn "for help run: $(warp_message_bold './warp db switch --help')"
        return 0
    else
        warp_message_warn "Automatic mysql version switching is disabled."
        warp_message_warn "This flow destroys local MySQL data and must be executed manually by the operator."
        warp_message ""
        warp_message_info "Requested change:"
        warp_message " from: $(warp_message_info "$mysql_version_current")"
        warp_message " to:   $(warp_message_info "$mysql_version_requested")"
        warp_message ""
        warp_message_info "Manual procedure:"
        warp_message " 1. Create a backup if needed: $(warp_message_bold './warp db dump <database_name> > backup.sql')"
        warp_message " 2. Update MYSQL_VERSION in:"
        warp_message "    - $(warp_message_info "$ENVIRONMENTVARIABLESFILE")"
        warp_message "    - $(warp_message_info "$ENVIRONMENTVARIABLESFILESAMPLE")"
        warp_message " 3. Remove local MySQL config/cache artifacts if the operator confirms it is safe:"
        warp_message "    - $(warp_message_info "$PROJECTPATH/.warp/docker/config/mysql/")"
        warp_message "    - $(warp_message_info "$PROJECTPATH/.warp/docker/volumes/mysql/*")"
        warp_message " 4. Remove the docker volume if required: $(warp_message_bold 'warp volume --rm mysql')"
        warp_message " 5. Restore base MySQL config from setup:"
        warp_message "    - $(warp_message_info 'cp -R .warp/setup/mysql/config/ .warp/docker/config/mysql/')"
        warp_message " 6. If the project uses a private DB registry, refresh/tag the image manually before restart."
        warp_message " 7. Rebuild/restart the environment:"
        warp_message "    - $(warp_message_bold './warp reset')"
        warp_message "    - $(warp_message_bold './warp db --update')"
        warp_message ""
        warp_message_warn "No files were changed by ./warp db switch."
        return 2
    fi
}

function mysql_dump()
{
    local db
    local strip_definers=0
    local -a db_args=()
    local _status

    if [ "$1" = "-h" ] || [ "$1" = "--help" ]
    then
        mysql_dump_help
        exit 1
    fi;

    while [ $# -gt 0 ]; do
        case "$1" in
            -s|--strip-definers)
                strip_definers=1
                ;;
            --)
                shift
                while [ $# -gt 0 ]; do
                    db_args+=("$1")
                    shift
                done
                break
                ;;
            -*)
                warp_message_error "unknown option for dump: $1"
                exit 1
                ;;
            *)
                db_args+=("$1")
                ;;
        esac
        shift
    done

    db="${db_args[*]}"

    [ -z "$db" ] && warp_message_error "Database name is required" && exit 1

    if ! warp_check_env_file ; then
        warp_message_error "file not found $(basename $ENVIRONMENTVARIABLESFILE)"
        exit 1
    fi

    mysql_external_bootstrap_if_needed || exit 1

    if [ "$(mysql_external_mode_enabled)" = "true" ]; then
        mysql_ensure_external_clients || { warp_message_error "SQL client tools are required."; exit 1; }
        mysql_load_external_conn_values
        MYSQL_DUMP_BIN=$(mysql_pick_external_dump_bin)
        [ -z "$DB_HOST" ] && warp_message_error "DATABASE_HOST is empty in .env" && exit 1
        [ -z "$DB_USER" ] && warp_message_error "DATABASE_USER is empty in .env" && exit 1
        [ -z "$DB_PASSWORD" ] && warp_message_error "DATABASE_PASSWORD is empty in .env" && exit 1
        if [ "$strip_definers" -eq 1 ]; then
            "$MYSQL_DUMP_BIN" -h"$DB_HOST" -P"$DB_PORT" -u"$DB_USER" -p"$DB_PASSWORD" "$db" 2> /dev/null | sed -e 's/DEFINER[[:space:]]*=[[:space:]]*[^*]*\*/\*/g'
            _status=${PIPESTATUS[0]}
            return $_status
        fi

        "$MYSQL_DUMP_BIN" -h"$DB_HOST" -P"$DB_PORT" -u"$DB_USER" -p"$DB_PASSWORD" "$db" 2> /dev/null
        return $?
    fi

    if [ $(warp_check_is_running) = false ]; then
        warp_message_error "The containers are not running"
        warp_message_error "please, first run warp start"
        exit 1;
    fi

    DATABASE_ROOT_PASSWORD=$(warp_env_read_var DATABASE_ROOT_PASSWORD)
    MYSQL_DUMP_BIN=$(warp_mysql_dump_bin)
    if [ "$strip_definers" -eq 1 ]; then
        docker-compose -f "$DOCKERCOMPOSEFILE" exec -T mysql bash -c "CMD=\"$MYSQL_DUMP_BIN\"; command -v \"\$CMD\" >/dev/null 2>&1 || CMD=\"mysqldump\"; \"\$CMD\" -uroot -p$DATABASE_ROOT_PASSWORD $db 2> /dev/null" | sed -e 's/DEFINER[[:space:]]*=[[:space:]]*[^*]*\*/\*/g'
        _status=${PIPESTATUS[0]}
        return $_status
    fi

    docker-compose -f "$DOCKERCOMPOSEFILE" exec -T mysql bash -c "CMD=\"$MYSQL_DUMP_BIN\"; command -v \"\$CMD\" >/dev/null 2>&1 || CMD=\"mysqldump\"; \"\$CMD\" -uroot -p$DATABASE_ROOT_PASSWORD $db 2> /dev/null"
}

function mysql_import()
{

    if [ "$1" = "-h" ] || [ "$1" = "--help" ]
    then
        mysql_import_help
        exit 1
    fi;

    db=$1

    [ -z "$db" ] && warp_message_error "Database name is required" && exit 1

    if ! warp_check_env_file ; then
        warp_message_error "file not found $(basename $ENVIRONMENTVARIABLESFILE)"
        exit 1
    fi

    mysql_external_bootstrap_if_needed || exit 1

    if [ "$(mysql_external_mode_enabled)" = "true" ]; then
        mysql_load_external_conn_values
        MYSQL_CLIENT_BIN=$(mysql_pick_external_client_bin)
        [ -z "$MYSQL_CLIENT_BIN" ] && MYSQL_CLIENT_BIN="mysql"
        warp_message_warn "External database mode detected (MYSQL_VERSION=rds)."
        warp_message_warn "warp db import does not execute against external servers."
        warp_message ""
        warp_message_info "Run manually:"
        warp_message " $MYSQL_CLIENT_BIN -h$DB_HOST -P$DB_PORT -u$DB_USER -p $db < /path/to/file.sql"
        warp_message ""
        warp_message_info "Password:"
        warp_message " $DB_PASSWORD"
        warp_message ""
        return 0
    fi

    if [ $(warp_check_is_running) = false ]; then
        warp_message_error "The containers are not running"
        warp_message_error "please, first run warp start"
        exit 1;
    fi

    DATABASE_ROOT_PASSWORD=$(warp_env_read_var DATABASE_ROOT_PASSWORD)

    MYSQL_CLIENT_BIN=$(warp_mysql_client_bin)
    docker-compose -f $DOCKERCOMPOSEFILE exec -T mysql bash -c "CMD=\"$MYSQL_CLIENT_BIN\"; command -v \"\$CMD\" >/dev/null 2>&1 || CMD=\"mysql\"; \"\$CMD\" -uroot -p$DATABASE_ROOT_PASSWORD $db 2> /dev/null"

}

mysql_tuner_url() {
    echo "https://raw.githubusercontent.com/major/MySQLTuner-perl/refs/heads/master/mysqltuner.pl"
}

mysql_tuner_target_file() {
    if [ -d "$PROJECTPATH/var" ]; then
        echo "$PROJECTPATH/var/mysqltuner.pl"
    else
        echo "/tmp/mysqltuner.pl"
    fi
}

mysql_tuner_download() {
    _target="$1"
    _url=$(mysql_tuner_url)

    [ -f "$_target" ] && [ -s "$_target" ] && return 0

    warp_message_info2 "Downloading MySQLTuner: $(basename "$_target")"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$_url" -o "$_target" || return 1
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$_target" "$_url" || return 1
    else
        warp_message_error "curl/wget not found. Install one of them and retry."
        return 1
    fi

    chmod +x "$_target" 2>/dev/null || true
}

mysql_tuner_install_perl() {
    command -v perl >/dev/null 2>&1 && return 0

    warp_message_warn "Perl is required to run MySQLTuner and is not installed."
    _install=$(warp_question_ask_default "Install perl now? $(warp_message_info [Y/n]) " "Y")
    if [ "$_install" != "Y" ] && [ "$_install" != "y" ]; then
        warp_message_warn "Skipping perl installation."
        return 1
    fi

    _distro=""
    if [ -r /etc/os-release ]; then
        _distro=$(awk -F= '/^ID=/{gsub(/"/,"",$2); print tolower($2)}' /etc/os-release)
    fi

    case "$_distro" in
        debian|ubuntu)
            if command -v apt-get >/dev/null 2>&1; then
                sudo apt-get install -y perl 2>/dev/null || apt-get install -y perl
            else
                return 1
            fi
        ;;
        amzn|amazon|rhel|centos|fedora|rocky|almalinux)
            if command -v dnf >/dev/null 2>&1; then
                sudo dnf install -y perl 2>/dev/null || dnf install -y perl
            elif command -v yum >/dev/null 2>&1; then
                sudo yum install -y perl 2>/dev/null || yum install -y perl
            else
                return 1
            fi
        ;;
        opensuse*|sles|suse)
            if command -v zypper >/dev/null 2>&1; then
                sudo zypper --non-interactive install perl 2>/dev/null || zypper --non-interactive install perl
            else
                return 1
            fi
        ;;
        *)
            warp_message_warn "Unknown distro. Install perl manually and retry:"
            warp_message_warn " - Debian/Ubuntu: apt-get install perl"
            warp_message_warn " - Amazon/RHEL: dnf install perl (or yum install perl)"
            warp_message_warn " - openSUSE: zypper install perl"
            return 1
        ;;
    esac

    command -v perl >/dev/null 2>&1
}

mysql_local_mapped_port() {
    _p=$(warp_env_read_var DATABASE_BINDED_PORT)
    if [[ "$_p" =~ ^[0-9]+$ ]]; then
        echo "$_p"
        return 0
    fi

    _map=$(docker-compose -f "$DOCKERCOMPOSEFILE" port mysql 3306 2>/dev/null | head -n1)
    if [ -n "$_map" ]; then
        _port=$(echo "$_map" | awk -F: '{print $NF}')
        if [[ "$_port" =~ ^[0-9]+$ ]]; then
            echo "$_port"
            return 0
        fi
    fi

    echo "3306"
}

mysql_tuner_load_connection() {
    mysql_external_bootstrap_if_needed || return 1

    if [ "$(mysql_external_mode_enabled)" = "true" ]; then
        mysql_load_external_conn_values
        TUNER_HOST="$DB_HOST"
        TUNER_PORT="${DB_PORT:-3306}"
        TUNER_USER="$DB_USER"
        TUNER_PASS="$DB_PASSWORD"
        TUNER_MODE="external"
        return 0
    fi

    if [ "$(warp_check_is_running)" = false ]; then
        warp_message_error "The containers are not running"
        warp_message_error "please, first run warp start"
        return 1
    fi

    TUNER_HOST="localhost"
    TUNER_PORT="$(mysql_local_mapped_port)"
    TUNER_USER="root"
    TUNER_PASS="$(warp_env_read_var DATABASE_ROOT_PASSWORD)"
    if [ -z "$TUNER_PASS" ]; then
        TUNER_USER="$(warp_env_read_var DATABASE_USER)"
        TUNER_PASS="$(warp_env_read_var DATABASE_PASSWORD)"
    fi
    TUNER_MODE="local"
    return 0
}

function mysql_tuner()
{
    if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
        mysql_tuner_help
        exit 1
    fi

    if ! warp_check_env_file ; then
        warp_message_error "file not found $(basename $ENVIRONMENTVARIABLESFILE)"
        exit 1
    fi

    mysql_tuner_load_connection || exit 1
    [ -z "$TUNER_HOST" ] && warp_message_error "DATABASE_HOST is empty in .env" && exit 1
    [ -z "$TUNER_USER" ] && warp_message_error "DATABASE_USER is empty in .env" && exit 1
    [ -z "$TUNER_PASS" ] && warp_message_error "Database password is empty in .env" && exit 1

    if ! mysql_tuner_install_perl; then
        warp_message_error "Perl is required. Aborting mysql tuner."
        exit 1
    fi

    _target=$(mysql_tuner_target_file)
    if ! mysql_tuner_download "$_target"; then
        warp_message_error "Unable to download MySQLTuner from $(mysql_tuner_url)"
        exit 1
    fi

    _tuner_show_logs=0
    _tuner_has_server_log=0
    _tuner_has_nocolor=0
    _tuner_has_color=0
    for _arg in "$@"; do
        case "$_arg" in
            --server-log|--server-log=*)
                _tuner_has_server_log=1
            ;;
            --nocolor)
                _tuner_has_nocolor=1
            ;;
            --color)
                _tuner_has_color=1
            ;;
        esac

        if [[ "$_arg" =~ ^-v{3,}$ ]] || [ "$_arg" = "--verbose" ]; then
            _tuner_show_logs=1
        fi
    done

    if [ "$_tuner_has_color" -eq 0 ] && [ "$_tuner_has_nocolor" -eq 0 ]; then
        set -- --color "$@"
    fi

    if [ "$_tuner_show_logs" -eq 0 ] && [ "$_tuner_has_server_log" -eq 0 ]; then
        set -- --server-log=/dev/null "$@"
    fi

    _tmp_out=$(mktemp /tmp/warp-mysqltuner.XXXXXX 2>/dev/null || echo "/tmp/warp-mysqltuner.$$.out")

    if [ "$TUNER_MODE" = "local" ] && [ "$TUNER_PORT" = "3306" ]; then
        warp_message_info2 "Running MySQLTuner against localhost (port 3306)"
        perl "$_target" --host localhost --user "$TUNER_USER" --pass "$TUNER_PASS" "$@" >"$_tmp_out" 2>&1
    else
        warp_message_info2 "Running MySQLTuner against $TUNER_HOST:$TUNER_PORT"
        perl "$_target" --host "$TUNER_HOST" --port "$TUNER_PORT" --user "$TUNER_USER" --pass "$TUNER_PASS" "$@" >"$_tmp_out" 2>&1
    fi
    _rc=$?

    if [ "$_tuner_show_logs" -eq 0 ]; then
        sed -E '/^[0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]].*\[(Note|Warning|Warn|Error)\]/d; /^create_uring failed:/d' "$_tmp_out"
    else
        cat "$_tmp_out"
    fi

    rm -f "$_tmp_out" 2>/dev/null || true
    return "$_rc"
}

function mysql_main()
{
    case "$1" in
        devdump)
            shift 1
            mysql_devdump_main "$@"
        ;;

        devdump:*)
            mysql_devdump_main "$@"
        ;;

        dump)
            shift 1
            mysql_dump "$@"
        ;;

        info)
            mysql_info
        ;;

        health)
            shift 1
            mysql_health "$@"
        ;;

        import)
            shift 1
            mysql_import "$@"
        ;;

        connect)
            shift 1
            mysql_connect "$@"
        ;;

        ssh)
            shift 1
            mysql_connect_ssh "$@"
        ;;

        switch)
            shift 1
            mysql_switch "$@"
        ;;

        tuner)
            shift 1
            mysql_tuner "$@"
        ;;

        --update)
            mysql_update_db
        ;;

        -h | --help)
            mysql_help_usage
        ;;

        *)            
            mysql_help_usage
        ;;
    esac
}
