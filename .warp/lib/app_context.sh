#!/bin/bash

warp_app_context_reset() {
    WARP_APP_FRAMEWORK="unknown"
    WARP_APP_VERSION=""
    WARP_APP_VERSION_CONFIDENCE="unknown"
    WARP_APP_VERSION_SOURCE="unknown"
    WARP_MAGENTO_SERIES=""
    WARP_MAGENTO_PATCH=""
    WARP_APP_COMPAT_PROFILE="general"

    export WARP_APP_FRAMEWORK
    export WARP_APP_VERSION
    export WARP_APP_VERSION_CONFIDENCE
    export WARP_APP_VERSION_SOURCE
    export WARP_MAGENTO_SERIES
    export WARP_MAGENTO_PATCH
    export WARP_APP_COMPAT_PROFILE
}

warp_app_context__framework_from_base() {
    _framework="${FRAMEWORK:-${framework:-}}"

    case "$_framework" in
        m2)
            printf '%s\n' "magento"
            ;;
        oro)
            printf '%s\n' "oro"
            ;;
        php)
            printf '%s\n' "php"
            ;;
        *)
            printf '%s\n' "unknown"
            ;;
    esac
}

warp_app_context_detect_framework() {
    _base_framework=$(warp_app_context__framework_from_base)

    if [ -f "$PROJECTPATH/composer.lock" ] && grep -Eq 'magento/(product|project)-(community|enterprise)-edition' "$PROJECTPATH/composer.lock"; then
        printf '%s\n' "magento"
        return 0
    fi

    if [ -f "$PROJECTPATH/composer.json" ] && grep -Eq 'magento/(product|project)-(community|enterprise)-edition' "$PROJECTPATH/composer.json"; then
        printf '%s\n' "magento"
        return 0
    fi

    if [ -f "$PROJECTPATH/bin/magento" ] || [ -f "$PROJECTPATH/app/etc/env.php" ]; then
        printf '%s\n' "magento"
        return 0
    fi

    printf '%s\n' "$_base_framework"
}

warp_app_context__extract_magento_version_from_lock() {
    _lock_file="$1"
    [ -f "$_lock_file" ] || return 1

    awk '
        /"name":[[:space:]]*"magento\/(product|project)-(community|enterprise)-edition"/ {
            found=1
        }
        found && /"version":[[:space:]]*"/ {
            line=$0
            sub(/.*"version":[[:space:]]*"/, "", line)
            sub(/".*/, "", line)
            print line
            exit
        }
    ' "$_lock_file"
}

warp_app_context__extract_magento_version_from_json() {
    _json_file="$1"
    [ -f "$_json_file" ] || return 1

    awk '
        /"magento\/(product|project)-(community|enterprise)-edition"[[:space:]]*:/ {
            line=$0
            sub(/.*:[[:space:]]*"/, "", line)
            sub(/".*/, "", line)
            print line
            exit
        }
    ' "$_json_file"
}

warp_app_context__normalize_version() {
    _version="$1"
    [ -n "$_version" ] || return 1

    _version=$(printf '%s' "$_version" | sed 's/^v//')
    printf '%s\n' "$_version"
}

warp_app_context__extract_magento_series() {
    _version="$1"
    [ -n "$_version" ] || return 1

    printf '%s\n' "$_version" | sed -n 's/^\([0-9]\+\.[0-9]\+\.[0-9]\+\).*/\1/p'
}

warp_app_context__extract_magento_patch() {
    _version="$1"
    [ -n "$_version" ] || return 1

    printf '%s\n' "$_version" | sed -n 's/^[0-9]\+\.[0-9]\+\.[0-9]\+\(-p[0-9]\+\).*$/\1/p'
}

warp_app_context__patch_number() {
    _patch="$1"
    [ -n "$_patch" ] || return 1

    printf '%s\n' "$_patch" | sed -n 's/^-p\([0-9]\+\)$/\1/p'
}

warp_app_context_detect_magento_version() {
    warp_app_context_reset

    WARP_APP_FRAMEWORK=$(warp_app_context_detect_framework)
    export WARP_APP_FRAMEWORK

    [ "$WARP_APP_FRAMEWORK" = "magento" ] || return 0

    if [ -f "$PROJECTPATH/composer.lock" ]; then
        _version=$(warp_app_context__extract_magento_version_from_lock "$PROJECTPATH/composer.lock")
        if [ -n "$_version" ]; then
            WARP_APP_VERSION=$(warp_app_context__normalize_version "$_version")
            WARP_APP_VERSION_CONFIDENCE="exact"
            WARP_APP_VERSION_SOURCE="composer.lock"
        fi
    fi

    if [ -z "$WARP_APP_VERSION" ] && [ -f "$PROJECTPATH/composer.json" ]; then
        _version=$(warp_app_context__extract_magento_version_from_json "$PROJECTPATH/composer.json")
        if [ -n "$_version" ]; then
            WARP_APP_VERSION=$(warp_app_context__normalize_version "$_version")
            WARP_APP_VERSION_CONFIDENCE="constraint"
            WARP_APP_VERSION_SOURCE="composer.json"
        fi
    fi

    if [ -z "$WARP_APP_VERSION" ]; then
        if [ -f "$PROJECTPATH/bin/magento" ] || [ -f "$PROJECTPATH/app/etc/env.php" ] || [ "${FRAMEWORK:-${framework:-}}" = "m2" ]; then
            WARP_APP_VERSION_CONFIDENCE="framework_only"
            WARP_APP_VERSION_SOURCE="framework_signal"
        fi
    fi

    if [ -n "$WARP_APP_VERSION" ]; then
        WARP_MAGENTO_SERIES=$(warp_app_context__extract_magento_series "$WARP_APP_VERSION")
        WARP_MAGENTO_PATCH=$(warp_app_context__extract_magento_patch "$WARP_APP_VERSION")
    fi

    export WARP_APP_VERSION
    export WARP_APP_VERSION_CONFIDENCE
    export WARP_APP_VERSION_SOURCE
    export WARP_MAGENTO_SERIES
    export WARP_MAGENTO_PATCH
}

warp_app_context_resolve_profile() {
    WARP_APP_COMPAT_PROFILE="general"

    if [ "$WARP_APP_FRAMEWORK" != "magento" ]; then
        export WARP_APP_COMPAT_PROFILE
        return 0
    fi

    case "$WARP_MAGENTO_SERIES" in
        2.4.8|2.4.9)
            WARP_APP_COMPAT_PROFILE="magento-2.4.8+"
            ;;
        2.4.7)
            WARP_APP_COMPAT_PROFILE="magento-2.4.7"
            ;;
        2.4.6)
            WARP_APP_COMPAT_PROFILE="magento-2.4.6"
            ;;
        2.4.5)
            WARP_APP_COMPAT_PROFILE="magento-2.4.5"
            ;;
        "")
            WARP_APP_COMPAT_PROFILE="magento"
            ;;
        *)
            WARP_APP_COMPAT_PROFILE="magento"
            ;;
    esac

    export WARP_APP_COMPAT_PROFILE
}

warp_app_context_detect() {
    warp_app_context_detect_magento_version
    warp_app_context_resolve_profile
}

warp_app_context_cache_supports_valkey() {
    [ "$WARP_APP_FRAMEWORK" = "magento" ] || return 1

    case "$WARP_APP_COMPAT_PROFILE" in
        magento-2.4.8+)
            return 0
            ;;
        magento-2.4.7)
            if [ "$WARP_APP_VERSION_CONFIDENCE" = "exact" ]; then
                _patch_num=$(warp_app_context__patch_number "$WARP_MAGENTO_PATCH")
                [ -n "$_patch_num" ] && [ "$_patch_num" -ge 6 ] && return 0
                return 1
            fi
            return 1
            ;;
        magento-2.4.6)
            if [ "$WARP_APP_VERSION_CONFIDENCE" = "exact" ]; then
                _patch_num=$(warp_app_context__patch_number "$WARP_MAGENTO_PATCH")
                [ -n "$_patch_num" ] && [ "$_patch_num" -ge 11 ] && return 0
                return 1
            fi
            return 1
            ;;
        magento-2.4.5)
            if [ "$WARP_APP_VERSION_CONFIDENCE" = "exact" ]; then
                _patch_num=$(warp_app_context__patch_number "$WARP_MAGENTO_PATCH")
                [ -n "$_patch_num" ] && [ "$_patch_num" -ge 13 ] && return 0
                return 1
            fi
            return 1
            ;;
        *)
            return 1
            ;;
    esac
}

warp_app_context_search_supports_elasticsearch() {
    [ "$WARP_APP_FRAMEWORK" = "magento" ] || return 1

    case "$WARP_APP_COMPAT_PROFILE" in
        magento-2.4.6|magento-2.4.5)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

warp_app_context_engine_class() {
    _capability="$1"
    _engine="$2"

    case "$_capability:$_engine" in
        db:mariadb)
            printf '%s\n' "recommended"
            ;;
        db:mysql)
            printf '%s\n' "compatibility"
            ;;
        cache:redis)
            printf '%s\n' "recommended"
            ;;
        cache:valkey)
            if warp_app_context_cache_supports_valkey; then
                printf '%s\n' "compatibility"
                return 0
            fi
            return 1
            ;;
        search:opensearch)
            printf '%s\n' "recommended"
            ;;
        search:elasticsearch)
            if warp_app_context_search_supports_elasticsearch; then
                printf '%s\n' "compatibility"
                return 0
            fi
            return 1
            ;;
        *)
            return 1
            ;;
    esac
}

warp_app_context_engines() {
    _capability="$1"

    case "$_capability" in
        db)
            printf '%s\n' "mariadb"
            printf '%s\n' "mysql"
            ;;
        cache)
            printf '%s\n' "redis"
            if warp_app_context_cache_supports_valkey; then
                printf '%s\n' "valkey"
            fi
            ;;
        search)
            printf '%s\n' "opensearch"
            if warp_app_context_search_supports_elasticsearch; then
                printf '%s\n' "elasticsearch"
            fi
            ;;
        *)
            return 1
            ;;
    esac
}

warp_app_context_engines_csv() {
    _capability="$1"
    warp_app_context_engines "$_capability" | awk 'NF { if (out != "") out = out " | "; out = out $0 } END { print out }'
}

warp_app_context_show_engine_options() {
    _capability="$1"
    [ -n "$_capability" ] || return 1

    warp_message_info2 "Available ${_capability} engines:"
    while IFS= read -r _engine; do
        [ -n "$_engine" ] || continue
        _class=$(warp_app_context_engine_class "$_capability" "$_engine" 2>/dev/null || true)
        if [ -n "$_class" ]; then
            warp_message_info2 " - ${_engine} [${_class}]"
        else
            warp_message_info2 " - ${_engine}"
        fi
    done <<EOF
$(warp_app_context_engines "$_capability")
EOF
}

warp_app_context_cache_note() {
    [ "$WARP_APP_FRAMEWORK" = "magento" ] || return 1

    if warp_app_context_cache_supports_valkey; then
        return 1
    fi

    case "$WARP_APP_COMPAT_PROFILE" in
        magento-2.4.7)
            if [ "$WARP_APP_VERSION_CONFIDENCE" = "exact" ]; then
                printf '%s\n' "Valkey 8 is hidden because Magento 2.4.7 requires patch level p6 or newer."
                return 0
            fi
            ;;
        magento-2.4.6)
            if [ "$WARP_APP_VERSION_CONFIDENCE" = "exact" ]; then
                printf '%s\n' "Valkey 8 is hidden because Magento 2.4.6 requires patch level p11 or newer."
                return 0
            fi
            ;;
        magento-2.4.5)
            if [ "$WARP_APP_VERSION_CONFIDENCE" = "exact" ]; then
                printf '%s\n' "Valkey 8 is hidden because Magento 2.4.5 requires patch level p13 or newer."
                return 0
            fi
            ;;
        magento)
            printf '%s\n' "Valkey 8 is hidden until Warp can resolve an exact Magento patch level."
            return 0
            ;;
    esac

    return 1
}

warp_app_context_search_note() {
    [ "$WARP_APP_FRAMEWORK" = "magento" ] || return 1

    if warp_app_context_search_supports_elasticsearch; then
        return 1
    fi

    case "$WARP_APP_COMPAT_PROFILE" in
        magento-2.4.8+|magento-2.4.7)
            printf '%s\n' "Elasticsearch compatibility is hidden for this Magento line; Warp recommends OpenSearch."
            return 0
            ;;
        magento)
            printf '%s\n' "Elasticsearch compatibility is hidden until Warp can resolve a Magento line that requires it."
            return 0
            ;;
    esac

    return 1
}

warp_app_context_summary() {
    if [ -n "$WARP_APP_VERSION" ]; then
        printf '%s %s (%s, %s, profile=%s)\n' "$WARP_APP_FRAMEWORK" "$WARP_APP_VERSION" "$WARP_APP_VERSION_SOURCE" "$WARP_APP_VERSION_CONFIDENCE" "$WARP_APP_COMPAT_PROFILE"
    else
        printf '%s (%s, profile=%s)\n' "$WARP_APP_FRAMEWORK" "$WARP_APP_VERSION_CONFIDENCE" "$WARP_APP_COMPAT_PROFILE"
    fi
}
