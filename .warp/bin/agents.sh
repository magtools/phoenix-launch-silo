#!/bin/bash

. "$PROJECTPATH/.warp/bin/agents_help.sh"

WARP_AGENTS_CONFIG_TEMPLATE="$PROJECTPATH/.warp/setup/init/config/agents/config.ini"
WARP_AGENTS_CONFIG_FILE="$PROJECTPATH/.warp/docker/config/agents/config.ini"
WARP_AGENTS_DIR="$PROJECTPATH/.agents_md"

agents_config_ensure() {
    if [ -f "$WARP_AGENTS_CONFIG_FILE" ]; then
        return 0
    fi

    if [ ! -f "$WARP_AGENTS_CONFIG_TEMPLATE" ]; then
        warp_message_error "agents config template not found: .warp/setup/init/config/agents/config.ini"
        return 1
    fi

    mkdir -p "$(dirname "$WARP_AGENTS_CONFIG_FILE")" || {
        warp_message_error "could not create agents config directory: .warp/docker/config/agents"
        return 1
    }

    cp "$WARP_AGENTS_CONFIG_TEMPLATE" "$WARP_AGENTS_CONFIG_FILE" || {
        warp_message_error "could not create agents config: .warp/docker/config/agents/config.ini"
        return 1
    }

    warp_message_warn "agents config created: .warp/docker/config/agents/config.ini"
    warp_message_warn "Complete AGENTS_REPO with an SSH Git URL, then run: warp agents install"
    return 0
}

agents_config_repo() {
    local _repo=""

    [ -f "$WARP_AGENTS_CONFIG_FILE" ] || return 1

    _repo=$(grep -m1 '^AGENTS_REPO=' "$WARP_AGENTS_CONFIG_FILE" 2>/dev/null | cut -d '=' -f2-)
    _repo=$(printf '%s' "$_repo" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//")
    printf '%s\n' "$_repo"
}

agents_repo_is_ssh_url() {
    local _repo="$1"

    case "$_repo" in
        git@*:*.git|git@*:*)
            return 0
            ;;
        ssh://git@*/*.git|ssh://git@*/*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

agents_dir_has_content() {
    [ -d "$WARP_AGENTS_DIR" ] || return 1
    [ -n "$(find "$WARP_AGENTS_DIR" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]
}

agents_gitignore_ensure() {
    local _line="/.agents_md"

    [ -f "$GITIGNOREFILE" ] || : > "$GITIGNOREFILE"
    grep -qxF "$_line" "$GITIGNOREFILE" 2>/dev/null && return 0
    printf '%s\n' "$_line" >> "$GITIGNOREFILE"
}

agents_install() {
    local _repo=""

    agents_config_ensure || return 1

    if agents_dir_has_content; then
        agents_gitignore_ensure
        warp_message "agents ya esta instalado, nada que hacer"
        return 0
    fi

    _repo=$(agents_config_repo)
    if [ -z "$_repo" ]; then
        agents_gitignore_ensure
        warp_message_error "AGENTS_REPO is empty in .warp/docker/config/agents/config.ini"
        warp_message_warn "Complete it with an SSH Git URL, then run: warp agents install"
        return 1
    fi

    if ! agents_repo_is_ssh_url "$_repo"; then
        warp_message_error "AGENTS_REPO must be an SSH Git URL."
        warp_message_warn "Supported examples: git@host:org/repo.git or ssh://git@host/org/repo.git"
        return 1
    fi

    hash git 2>/dev/null || {
        warp_message_error "git command not found; install git before running warp agents install"
        return 1
    }

    agents_gitignore_ensure
    mkdir -p "$WARP_AGENTS_DIR" || {
        warp_message_error "could not create agents directory: .agents_md"
        return 1
    }

    if ! git clone "$_repo" "$WARP_AGENTS_DIR"; then
        warp_message_error "could not clone private agents repo."
        warp_message_warn "Configure a valid SSH key with access to the repository, then retry: warp agents install"
        return 1
    fi

    [ -f "$WARP_AGENTS_DIR/install.sh" ] || {
        warp_message_error "agents install script not found: .agents_md/install.sh"
        return 1
    }

    bash "$WARP_AGENTS_DIR/install.sh"
}

agents_update() {
    [ -d "$WARP_AGENTS_DIR" ] || {
        warp_message_error "agents is not installed. Run first: warp agents install"
        return 1
    }

    [ -f "$WARP_AGENTS_DIR/update.sh" ] || {
        warp_message_error "agents update script not found: .agents_md/update.sh"
        return 1
    }

    bash "$WARP_AGENTS_DIR/update.sh"
}

agents_post_start_update() {
    [ -f "$WARP_AGENTS_DIR/update.sh" ] || return 0

    if ! bash "$WARP_AGENTS_DIR/update.sh" >/dev/null 2>&1; then
        warp_message_warn "agents update could not be completed"
    fi
}

agents_main() {
    case "$1" in
        agents)
            shift 1
            case "$1" in
                install)
                    shift 1
                    agents_install "$@"
                    ;;
                update)
                    shift 1
                    agents_update "$@"
                    ;;
                -h|--help|help|"")
                    agents_help_usage
                    ;;
                *)
                    agents_help_usage
                    return 1
                    ;;
            esac
            ;;
        -h|--help|help|"")
            agents_help_usage
            ;;
        *)
            agents_help_usage
            return 1
            ;;
    esac
}
