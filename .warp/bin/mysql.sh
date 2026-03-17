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

mysql_read_envphp_field() {
    _file="$1"
    _field="$2"
    grep -m1 -E "'${_field}'[[:space:]]*=>[[:space:]]*'" "$_file" 2>/dev/null | sed -E "s/.*'${_field}'[[:space:]]*=>[[:space:]]*'([^']*)'.*/\1/"
}

mysql_external_collect_from_envphp() {
    _envphp="$PROJECTPATH/app/etc/env.php"
    [ -f "$_envphp" ] || return 1

    _host=$(mysql_read_envphp_field "$_envphp" "host")
    _port=$(mysql_read_envphp_field "$_envphp" "port")
    _dbname=$(mysql_read_envphp_field "$_envphp" "dbname")
    _user=$(mysql_read_envphp_field "$_envphp" "username")
    _password=$(mysql_read_envphp_field "$_envphp" "password")

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
    if command -v mysql >/dev/null 2>&1; then
        echo "mysql"
        return 0
    fi
    if command -v mariadb >/dev/null 2>&1; then
        echo "mariadb"
        return 0
    fi
    echo ""
}

mysql_pick_external_dump_bin() {
    if command -v mysqldump >/dev/null 2>&1; then
        echo "mysqldump"
        return 0
    fi
    if command -v mariadb-dump >/dev/null 2>&1; then
        echo "mariadb-dump"
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
        return 0
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

    MYSQL_VERSION_CURRENT=$(warp_env_read_var MYSQL_VERSION)
    warp_message_info2 "You current MySQL version is: $MYSQL_VERSION_CURRENT"

    if [ $MYSQL_VERSION_CURRENT = $1 ]
    then
        warp_message_info2 "the selected version is the same as the previous one, no changes will be made"
        warp_message_warn "for help run: $(warp_message_bold './warp db switch --help')"
    else
        warp_message_warn "This command will destroy MySQL database"
        warp_message "you can create a backup running: $(warp_message_bold './warp db dump --help')"
        respuesta_switch_version_db=$( warp_question_ask_default "Do you want to continue? $(warp_message_info [Y/n]) " "Y" )

        if [ "$respuesta_switch_version_db" = "Y" ] || [ "$respuesta_switch_version_db" = "y" ]
        then
            mysql_version=$1
            warp_message_info2 "change version to: $mysql_version"

            MYSQL_VERSION_OLD="MYSQL_VERSION=$MYSQL_VERSION_CURRENT"
            MYSQL_VERSION_NEW="MYSQL_VERSION=$mysql_version"

            cat $ENVIRONMENTVARIABLESFILE | sed -e "s/$MYSQL_VERSION_OLD/$MYSQL_VERSION_NEW/" > "$ENVIRONMENTVARIABLESFILE.warp_tmp"
            mv "$ENVIRONMENTVARIABLESFILE.warp_tmp" $ENVIRONMENTVARIABLESFILE

            cat $ENVIRONMENTVARIABLESFILESAMPLE | sed -e "s/$MYSQL_VERSION_OLD/$MYSQL_VERSION_NEW/" > "$ENVIRONMENTVARIABLESFILESAMPLE.warp_tmp"
            mv "$ENVIRONMENTVARIABLESFILESAMPLE.warp_tmp" $ENVIRONMENTVARIABLESFILESAMPLE

            # delete old files
            rm  -rf $PROJECTPATH/.warp/docker/config/mysql/ 2> /dev/null
            if [ -d $PROJECTPATH/.warp/docker/volumes/mysql ]
            then
                sudo rm -rf $PROJECTPATH/.warp/docker/volumes/mysql/* 2> /dev/null
            fi

            # delete volume database
            warp volume --rm mysql 2> /dev/null

            DOCKER_PRIVATE_REGISTRY=$(warp_env_read_var DOCKER_PRIVATE_REGISTRY)

            if [ ! -z "$DOCKER_PRIVATE_REGISTRY" ] ; then
                NAMESPACE=$(warp_env_read_var NAMESPACE)
                PROJECT=$(warp_env_read_var PROJECT)
                mysql_docker_image="${NAMESPACE}-${PROJECT}-dbs"

                CREATE_MYSQL_IMAGE_FROM="mysql:${mysql_version} ${DOCKER_PRIVATE_REGISTRY}/${mysql_docker_image}:latest"

                # clear custom image
                docker pull "mysql:$mysql_version"
                docker rmi "${DOCKER_PRIVATE_REGISTRY}/${mysql_docker_image}"
                docker tag $CREATE_MYSQL_IMAGE_FROM 2> /dev/null
            fi

            # check files for mysql version
            #warp_mysql_check_files_yaml

            # copy base files
            cp -R $PROJECTPATH/.warp/setup/mysql/config/ $PROJECTPATH/.warp/docker/config/mysql/

            warp_message_warn "* commit new changes"
            warp_message_warn "* at each environment run: $(warp_message_bold './warp reset')"
            warp_message_warn "* after that run: $(warp_message_bold './warp db --update')"
        else
            warp_message_warn "* aborting switch database"
        fi
    fi
}

function mysql_dump()
{

    if [ "$1" = "-h" ] || [ "$1" = "--help" ]
    then
        mysql_dump_help
        exit 1
    fi;

    db="$@"

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
        "$MYSQL_DUMP_BIN" -h"$DB_HOST" -P"$DB_PORT" -u"$DB_USER" -p"$DB_PASSWORD" "$db" 2> /dev/null
        return 0
    fi

    if [ $(warp_check_is_running) = false ]; then
        warp_message_error "The containers are not running"
        warp_message_error "please, first run warp start"
        exit 1;
    fi

    DATABASE_ROOT_PASSWORD=$(warp_env_read_var DATABASE_ROOT_PASSWORD)
    MYSQL_DUMP_BIN=$(warp_mysql_dump_bin)
    docker-compose -f $DOCKERCOMPOSEFILE exec mysql bash -c "CMD=\"$MYSQL_DUMP_BIN\"; command -v \"\$CMD\" >/dev/null 2>&1 || CMD=\"mysqldump\"; \"\$CMD\" -uroot -p$DATABASE_ROOT_PASSWORD $db 2> /dev/null"
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
