#!/bin/bash

function mysql_help_usage()
{

    warp_message ""
    warp_message_info "Usage:"
    warp_message      " warp db command [options] [arguments]"
    warp_message ""

    warp_message ""
    warp_message_info "Options:"
    warp_message_info   " -h, --help         $(warp_message 'display this help message')"
    warp_message_info   " --update           $(warp_message 'update db from private registry')"
    warp_message ""

    warp_message_info "Available commands:"

    warp_message_info   " info               $(warp_message 'display info available')"
    warp_message_info   " dump               $(warp_message 'allows to make a database dump')"
    warp_message_info   " devdump            $(warp_message 'helper for lightweight development dumps by app profile')"
    warp_message_info   " devdump:<app>      $(warp_message 'run lightweight development dump for app profile (example: devdump:magento)')"
    warp_message_info   " connect            $(warp_message 'connect to mysql command line (shell)')"
    warp_message_info   " import             $(warp_message 'allows to restore a database')"
    warp_message_info   " ssh                $(warp_message 'connect to mysql by ssh')"
    warp_message_info   " switch             $(warp_message 'allows to change the MySQL version')"
    warp_message_info   " tuner              $(warp_message 'download/run MySQLTuner against the current db service')"

    warp_message ""
    warp_message_info "Help:"
    warp_message " warp db dump --help"

    warp_message ""

}

function mysql_tuner_help()
{
    warp_message ""
    warp_message_info "Usage:"
    warp_message      " warp db tuner [mysqltuner options]"
    warp_message ""

    warp_message ""
    warp_message_info "Help:"
    warp_message " Download mysqltuner.pl to ./var (or /tmp) if needed, ensure perl is available,"
    warp_message " and run MySQLTuner using current project database connection."
    warp_message " By default log scan output is hidden. Use -vvv to include log details."
    warp_message ""

    warp_message_info "Examples:"
    warp_message " warp db tuner"
    warp_message " warp db tuner --skipsize --nocolor"
    warp_message " warp db tuner -vvv"
    warp_message ""
}

function mysql_import_help()
{

    warp_message ""
    warp_message_info "Usage:"
    warp_message      " warp db import [db_name] < [file]"
    warp_message ""

    warp_message ""
    warp_message_info "Help:"
    warp_message " Allow to recover a database inside the container, indicating a path of your local machine"
    warp_message ""

    warp_message_info "Example:"
    warp_message " warp db import warp_db < /path/to/restore/backup/warp_db.sql"
    warp_message " gunzip < /path/to/restore/backup/warp_db.sql.gz | warp db import warp_db"
    warp_message " gunzip < /path/to/restore/backup/warp_db.sql.gz | pv | warp db import warp_db"

    warp_message ""

}

function mysql_dump_help()
{

    warp_message ""
    warp_message_info "Usage:"
    warp_message      " warp db dump [options] [db_name] > [file]"
    warp_message ""

    warp_message ""
    warp_message_info "Options:"
    warp_message_info   " -h, --help         $(warp_message 'display this help message')"
    warp_message_info   " -s, --strip-definers $(warp_message 'remove DEFINER clauses from the streamed dump output')"
    warp_message ""

    warp_message ""
    warp_message_info "Help:"
    warp_message " Create a backup of a database and save it local machine"
    warp_message " if needed, use -s / --strip-definers to remove DEFINER clauses from the streamed dump output"
    warp_message ""

    warp_message_info "Example:"
    warp_message " warp db dump warp_db | gzip > /path/to/save/backup/warp_db.sql.gz"
    warp_message " warp db dump -s warp_db | gzip > /path/to/save/backup/warp_db.sql.gz"
    warp_message " warp db dump --strip-definers warp_db | gzip > /path/to/save/backup/warp_db.sql.gz"
    warp_message " warp db dump warp_db | gzip | pv > /path/to/save/backup/warp_db.sql.gz"
    warp_message " warp db dump warp_db > /path/to/save/backup/warp_db.sql"
    warp_message ""

}

function mysql_connect_help()
{

    warp_message ""
    warp_message_info "Usage:"
    warp_message      " warp db connect"
    warp_message ""

    warp_message ""
    warp_message_info "Help:"
    warp_message " Connect to mysql command line "
    warp_message ""

    warp_message_info "Example:"
    warp_message " warp db connect"
    warp_message " mysql >> show databases;"
    warp_message ""
}

function mysql_ssh_help()
{

    warp_message ""
    warp_message_info "Usage:"
    warp_message      " warp db ssh"
    warp_message ""

    warp_message ""
    warp_message_info "Help:"
    warp_message " Connect to mysql by ssh "
    warp_message ""

    warp_message_info "Example:"
    warp_message " warp db ssh"
    warp_message ""
}

function mysql_switch_help()
{
    warp_message ""
    warp_message_info "Usage:"
    warp_message      " warp db switch [options]"
    warp_message ""

    warp_message ""
    warp_message_info "Options:"
    warp_message_info   " -h, --help         $(warp_message 'display this help message')"
    warp_message ""

    warp_message ""
    warp_message_info "Help:"
    warp_message " this command prints the manual guide to change the MySQL version safely"
    warp_message " it does not edit files or remove volumes automatically"
    warp_message " you can check the available versions of MySQL here: $(warp_message_info '[ https://hub.docker.com/r/library/mysql/tags/ ]')"
    warp_message ""

    warp_message_info "Example:"
    warp_message " warp db switch 8.0"
    warp_message ""    
}

function mysql_help()
{
    warp_message_info   " db                 $(warp_message 'utility for connect with mysql/mariadb databases')"
    warp_message_info   " mysql              $(warp_message 'alias of db (legacy compatibility)')"

}
