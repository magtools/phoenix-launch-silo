#!/bin/bash

function db_help_usage()
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
    warp_message_info   " info               $(warp_message 'display db info available')"
    warp_message_info   " dump               $(warp_message 'allows to make a database dump')"
    warp_message_info   " devdump            $(warp_message 'helper for lightweight development dumps by app profile')"
    warp_message_info   " devdump:<app>      $(warp_message 'run lightweight development dump for app profile (example: devdump:magento)')"
    warp_message_info   " connect            $(warp_message 'connect to database command line (shell)')"
    warp_message_info   " import             $(warp_message 'allows to restore a database')"
    warp_message_info   " ssh                $(warp_message 'connect to db container by shell')"
    warp_message_info   " switch             $(warp_message 'allows to change the DB engine version')"
    warp_message_info   " tuner              $(warp_message 'download/run MySQLTuner against the current db service')"

    warp_message ""
    warp_message_info "Help:"
    warp_message " if mysql service is missing in docker-compose, Warp can switch the project to external DB mode"
    warp_message " after confirmation. It tries app/etc/env.php first and then persists MYSQL_VERSION=rds plus DATABASE_*"
    warp_message " values in .env for subsequent runs."
    warp_message " in external mode, connect / dump / tuner use the external host and import only prints the manual command."
    warp_message ""
    warp_message " warp db dump --help"
    warp_message ""
}

function db_help()
{
    warp_message_info   " db                 $(warp_message 'utility for connect with databases (mysql/mariadb)')"
}
