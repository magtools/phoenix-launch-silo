#!/bin/bash

##
# Perform a question and grab the user answer 
# Use:
#    warp_banner
#
# Globals:
#   WARP_VERSION
# Arguments:
#   None
# Returns:
#   None
##
function warp_question_ask() {
    read -p "$1" response

    echo "$response"
}

function warp_question_ask_tty() {
    local _prompt="$1"
    local response=""

    if [ ! -r /dev/tty ]; then
        return 1
    fi

    read -r -p "$_prompt" response < /dev/tty
    echo "$response"
}


function warp_question_ask_default() {

    if [ "$2" = "" ]; then
        echo "Error Default value is missing"
        exit;
    fi;

    read -p "$1" response

    if [ "$response" = "" ]; then
        echo "$2"
    else
        echo "$response"
    fi;
}

function warp_question_ask_default_tty() {
    local _prompt="$1"
    local _default="$2"
    local response=""

    if [ "$_default" = "" ]; then
        echo "Error Default value is missing"
        exit
    fi

    if [ ! -r /dev/tty ]; then
        return 1
    fi

    read -r -p "$_prompt" response < /dev/tty

    if [ "$response" = "" ]; then
        echo "$_default"
    else
        echo "$response"
    fi
}
