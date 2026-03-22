#!/bin/bash

# Canonical service version matrix helpers.
# Stage 3 goal: expose the declarative matrix in .warp/variables.sh
# through simple Bash functions, without changing setup/runtime behavior yet.

warp_service_version__upper() {
    printf '%s' "$1" | tr '[:lower:]-' '[:upper:]_'
}

warp_service_version__var_prefix() {
    _capability="$1"
    _engine="$2"

    [ -n "$_capability" ] || return 1
    [ -n "$_engine" ] || return 1

    _capability_up=$(warp_service_version__upper "$_capability")
    _engine_up=$(warp_service_version__upper "$_engine")
    printf 'WARP_%s_%s' "$_capability_up" "$_engine_up"
}

warp_service_version__echo_array() {
    _var_name="$1"
    [ -n "$_var_name" ] || return 1

    eval '_values=( "${'"$_var_name"'[@]}" )'
    for _value in "${_values[@]}"; do
        printf '%s\n' "$_value"
    done
}

warp_service_version_capabilities() {
    warp_service_version__echo_array WARP_SERVICE_CAPABILITIES
}

warp_service_version_engines() {
    _capability="$1"
    [ -n "$_capability" ] || return 1

    _capability_up=$(warp_service_version__upper "$_capability")
    warp_service_version__echo_array "WARP_${_capability_up}_ENGINES"
}

warp_service_version_engine_default() {
    _capability="$1"
    [ -n "$_capability" ] || return 1

    _capability_up=$(warp_service_version__upper "$_capability")
    eval 'printf "%s\n" "${WARP_'"$_capability_up"'_ENGINE_DEFAULT}"'
}

warp_service_version_image_repo() {
    _prefix=$(warp_service_version__var_prefix "$1" "$2") || return 1
    eval 'printf "%s\n" "${'"$_prefix"'_IMAGE_REPO}"'
}

warp_service_version_tag_default() {
    _prefix=$(warp_service_version__var_prefix "$1" "$2") || return 1
    eval 'printf "%s\n" "${'"$_prefix"'_TAG_DEFAULT}"'
}

warp_service_version_tag_legacy_default() {
    _prefix=$(warp_service_version__var_prefix "$1" "$2") || return 1
    eval 'printf "%s\n" "${'"$_prefix"'_TAG_LEGACY_DEFAULT}"'
}

warp_service_version_tags_suggested() {
    _prefix=$(warp_service_version__var_prefix "$1" "$2") || return 1
    warp_service_version__echo_array "${_prefix}_TAGS_SUGGESTED"
}

warp_service_version_tags_legacy() {
    _prefix=$(warp_service_version__var_prefix "$1" "$2") || return 1
    warp_service_version__echo_array "${_prefix}_TAGS_LEGACY"
}

warp_service_version_tags_csv() {
    _capability="$1"
    _engine="$2"
    _kind="${3:-suggested}"

    case "$_kind" in
        suggested)
            _values=$(warp_service_version_tags_suggested "$_capability" "$_engine")
            ;;
        legacy)
            _values=$(warp_service_version_tags_legacy "$_capability" "$_engine")
            ;;
        *)
            return 1
            ;;
    esac

    printf '%s\n' "$_values" | awk 'NF { if (out != "") out = out ", "; out = out $0 } END { print out }'
}

warp_service_version_engines_csv() {
    _capability="$1"
    [ -n "$_capability" ] || return 1

    warp_service_version_engines "$_capability" | awk 'NF { if (out != "") out = out " | "; out = out $0 } END { print out }'
}

warp_service_version_tag_known() {
    _capability="$1"
    _engine="$2"
    _tag="$3"

    [ -n "$_capability" ] || return 1
    [ -n "$_engine" ] || return 1
    [ -n "$_tag" ] || return 1

    warp_service_version_tags_suggested "$_capability" "$_engine" | grep -Fxq "$_tag" && return 0
    warp_service_version_tags_legacy "$_capability" "$_engine" | grep -Fxq "$_tag" && return 0
    return 1
}

warp_service_version__dockerhub_repo() {
    _repo="$1"
    [ -n "$_repo" ] || return 1

    case "$_repo" in
        *.*/*)
            return 1
            ;;
        */*)
            printf '%s\n' "$_repo"
            ;;
        *)
            printf 'library/%s\n' "$_repo"
            ;;
    esac
}

warp_service_version_tag_validate_elastic() {
    _repo="$1"
    _tag="$2"
    [ -n "$_repo" ] || return 2
    [ -n "$_tag" ] || return 2

    _elastic_path="${_repo#docker.elastic.co/}"
    [ "$_elastic_path" != "$_repo" ] || return 2
    _url="https://www.docker.elastic.co/r/${_elastic_path}:${_tag}"

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$_url" >/dev/null 2>&1
        _rc=$?
    elif command -v wget >/dev/null 2>&1; then
        wget -q -O /dev/null "$_url" >/dev/null 2>&1
        _rc=$?
    else
        return 2
    fi

    case "$_rc" in
        0)
            return 0
            ;;
        8|22)
            return 1
            ;;
        *)
            return 2
            ;;
    esac
}

warp_service_version_tag_validate_remote() {
    _capability="$1"
    _engine="$2"
    _tag="$3"
    _repo=$(warp_service_version_image_repo "$_capability" "$_engine") || return 2

    case "$_repo" in
        docker.elastic.co/*)
            warp_service_version_tag_validate_elastic "$_repo" "$_tag"
            return $?
            ;;
    esac

    _hub_repo=$(warp_service_version__dockerhub_repo "$_repo") || return 2
    _url="https://hub.docker.com/v2/repositories/${_hub_repo}/tags/${_tag}"

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$_url" >/dev/null 2>&1
        _rc=$?
    elif command -v wget >/dev/null 2>&1; then
        wget -q -O /dev/null "$_url" >/dev/null 2>&1
        _rc=$?
    else
        return 2
    fi

    case "$_rc" in
        0)
            return 0
            ;;
        8|22)
            return 1
            ;;
        *)
            return 2
            ;;
    esac
}

warp_service_version_prompt_tag() {
    _capability="$1"
    _engine="$2"
    _prompt="$3"
    _default="$4"

    [ -n "$_capability" ] || return 1
    [ -n "$_engine" ] || return 1
    [ -n "$_prompt" ] || return 1
    [ -n "$_default" ] || return 1

    while : ; do
        _tag=$(warp_question_ask_default "$_prompt" "$_default")

        if warp_service_version_tag_known "$_capability" "$_engine" "$_tag"; then
            printf '%s\n' "$_tag"
            return 0
        fi

        warp_service_version_tag_validate_remote "$_capability" "$_engine" "$_tag"
        _rc=$?

        case "$_rc" in
            0)
                warp_message_info2 "Custom tag validated: ${_engine}:${_tag}"
                printf '%s\n' "$_tag"
                return 0
                ;;
            1)
                warp_message_warn "Tag not found for ${_engine}: ${_tag}"
                ;;
            2)
                warp_message_warn "Could not validate tag online for ${_engine}: ${_tag}"
                if warp_fallback_confirm_explicit_yes "Continue without validation? [y/N] "; then
                    printf '%s\n' "$_tag"
                    return 0
                fi
                ;;
        esac
    done
}
