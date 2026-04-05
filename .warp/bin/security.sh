#!/bin/bash

. "$PROJECTPATH/.warp/bin/security_help.sh"

security_log_file() {
    echo "$PROJECTPATH/var/log/warp-security.log"
}

security_log_archive_file() {
    date '+%Y%m%d-%H%M' | awk -v base="$PROJECTPATH/var/log/warp-security-" '{ print base $1 ".log" }'
}

security_log_separator() {
    printf '\n%100s\n\n' '' | tr ' ' '='
}

security_log_write() {
    local _line="$1"
    printf '%s\n' "$_line" >> "$(security_log_file)"
}

security_log_section_begin() {
    local _title="$1"
    local _discover="$2"
    local _cleanup="$3"
    local _log_file

    _log_file="$(security_log_file)"
    if [ -s "$_log_file" ]; then
        security_log_separator >> "$_log_file"
    fi

    security_log_write "[$_title]"
    security_log_write "discovery: $_discover"
    security_log_write "cleanup: $_cleanup"
    security_log_write ""
}

security_known_paths_file() {
    echo "$PROJECTPATH/.known-paths"
}

security_known_files_file() {
    echo "$PROJECTPATH/.known-files"
}

security_known_findings_file() {
    echo "$PROJECTPATH/.known-findings"
}

security_known_metadata_bootstrap() {
    local _paths_file=""
    local _files_file=""
    local _findings_file=""

    _paths_file="$(security_known_paths_file)"
    if [ ! -f "$_paths_file" ]; then
        cat > "$_paths_file" <<'EOF'
# Expected relative paths, one per line.
# Used to soften untracked drift only.
# Presence here never whitelists dangerous content.
#
# Examples:
# pub/.well-known
# pub/media/tmp
EOF
    fi

    _files_file="$(security_known_files_file)"
    if [ ! -f "$_files_file" ]; then
        cat > "$_files_file" <<'EOF'
# Expected relative files, one per line.
# Used for project-known files that should not count as unexpected PHP by themselves.
# Modified files can still be reported separately.
pub/cron.php
pub/get.php
pub/health_check.php
pub/index.php
pub/static.php
EOF
    fi

    _findings_file="$(security_known_findings_file)"
    if [ ! -f "$_findings_file" ]; then
        cat > "$_findings_file" <<'EOF'
# Expected findings, one per line.
# Format: path|indicator|class
# Example:
# pub/errors/processor.php|$_POST|risky primitive
EOF
    fi
}

security_known_paths_list() {
    local _file

    _file="$(security_known_paths_file)"
    if [ ! -f "$_file" ]; then
        return 0
    fi

    sed -e 's/#.*$//' -e 's/[[:space:]]*$//' -e '/^[[:space:]]*$/d' "$_file"
}

security_known_files_list() {
    local _file

    _file="$(security_known_files_file)"
    if [ ! -f "$_file" ]; then
        return 0
    fi

    sed -e 's/#.*$//' -e 's/[[:space:]]*$//' -e '/^[[:space:]]*$/d' "$_file"
}

security_known_findings_list() {
    local _file

    _file="$(security_known_findings_file)"
    if [ ! -f "$_file" ]; then
        return 0
    fi

    sed -e 's/#.*$//' -e 's/[[:space:]]*$//' -e '/^[[:space:]]*$/d' "$_file"
}

security_path_is_known() {
    local _path="$1"
    local _known=""

    while IFS= read -r _known; do
        [ -n "$_known" ] || continue
        case "$_path" in
            "$_known"|"$_known"/*)
                return 0
                ;;
        esac
    done < <(security_known_paths_list)

    return 1
}

security_file_is_known() {
    local _path="$1"
    local _known=""

    while IFS= read -r _known; do
        [ -n "$_known" ] || continue
        [ "$_path" = "$_known" ] && return 0
    done < <(security_known_files_list)

    return 1
}

security_finding_is_known() {
    local _path="$1"
    local _indicator="$2"
    local _class="$3"
    local _entry=""
    local _known_path=""
    local _known_indicator=""
    local _known_class=""

    while IFS= read -r _entry; do
        [ -n "$_entry" ] || continue
        IFS='|' read -r _known_path _known_indicator _known_class <<EOF
$_entry
EOF
        [ -n "$_known_path" ] || continue
        [ "$_path" = "$_known_path" ] || continue
        [ "$_indicator" = "$_known_indicator" ] || continue
        [ "$_class" = "$_known_class" ] || continue
        return 0
    done < <(security_known_findings_list)

    return 1
}

security_append_screen_family() {
    local _family="$1"

    case " $WARP_SECURITY_FAMILIES " in
        *" $_family "*) ;;
        *) WARP_SECURITY_FAMILIES="${WARP_SECURITY_FAMILIES} ${_family}" ;;
    esac
}

security_record_finding() {
    local _line="$1"
    local _family="$2"

    security_log_write "$_line"
    WARP_SECURITY_FINDINGS=$((WARP_SECURITY_FINDINGS + 1))
    [ -n "$_family" ] && security_append_screen_family "$_family"
}

security_add_score() {
    local _points="${1:-0}"

    WARP_SECURITY_SCORE=$((WARP_SECURITY_SCORE + _points))
}

security_current_severity() {
    if [ "${WARP_SECURITY_SCORE:-0}" -ge 90 ]; then
        echo "critical"
        return 0
    fi

    if [ "${WARP_SECURITY_SCORE:-0}" -ge 60 ]; then
        echo "high"
        return 0
    fi

    if [ "${WARP_SECURITY_SCORE:-0}" -ge 25 ]; then
        echo "medium"
        return 0
    fi

    if [ "${WARP_SECURITY_SCORE:-0}" -gt 0 ]; then
        echo "low"
        return 0
    fi

    echo "none"
}

security_level_color() {
    case "$1" in
        none) printf '%s' "$FGRN" ;;
        low) printf '%s' "$FCYN" ;;
        medium) printf '%s' "$FYEL" ;;
        high) printf '%s' "$FRED" ;;
        critical) printf '%s' "$BRED$FWHT" ;;
        *) printf '%s' "$RS" ;;
    esac
}

security_level_status() {
    case "$1" in
        none) echo "Systems nominal. No suspicious signals detected." ;;
        low) echo "Minor fluctuations detected. Monitoring recommended." ;;
        medium) echo "Warning: anomalous signals detected. Security review advised." ;;
        high) echo "Intrusion indicators detected on active paths. Immediate review required." ;;
        critical) echo "Code Red: multiple high-confidence compromise signals detected." ;;
        *) echo "Security state unknown." ;;
    esac
}

security_level_badge() {
    local _level="$1"
    local _color=""
    local _label=""

    _color="$(security_level_color "$_level")"
    _label="$(printf '%s' "$_level" | tr '[:lower:]' '[:upper:]')"
    printf '%b%s%b' "${_color}" "${_label}" "${RS}"
}

security_finish_section_empty_if_needed() {
    if [ "${WARP_SECURITY_SECTION_FINDINGS:-0}" -eq 0 ]; then
        security_log_write "No findings."
    fi
}

security_log_archive_rotate() {
    local _current_log=""
    local _archive_log=""
    local _old_logs=""

    _current_log="$(security_log_file)"
    _archive_log="$(security_log_archive_file)"

    cp "$_current_log" "$_archive_log" 2>/dev/null || return 1

    _old_logs="$(find "$PROJECTPATH/var/log" -maxdepth 1 -type f -name 'warp-security-*.log' | sort | head -n -10)"
    if [ -n "$_old_logs" ]; then
        printf '%s\n' "$_old_logs" | xargs -r rm -f
    fi

    WARP_SECURITY_ARCHIVE_LOG="${_archive_log#$PROJECTPATH/}"
    return 0
}

security_access_logs_list() {
    local _candidate=""

    for _candidate in \
        "$PROJECTPATH/.warp/docker/volumes/nginx/logs/access.log" \
        "$PROJECTPATH/.warp/docker/volumes/nginx/logs/default-access.log" \
        /var/log/nginx/access.log \
        /var/log/nginx/*access*.log \
        /var/log/httpd/*access*.log \
        /var/log/apache2/*access*.log
    do
        [ -f "$_candidate" ] && [ -r "$_candidate" ] && printf '%s\n' "$_candidate"
    done | sort -u
}

security_has_rg() {
    command -v rg >/dev/null 2>&1
}

security_warn_missing_rg_once() {
    if security_has_rg; then
        return 0
    fi

    [ "${WARP_SECURITY_RG_WARNED:-0}" -eq 1 ] && return 0

    warp_message_warn "ripgrep (rg) not found; using grep fallback."
    warp_message " package: ripgrep"
    warp_message " install: apt install ripgrep | dnf install ripgrep | yum install ripgrep | apk add ripgrep | brew install ripgrep"
    warp_message ""
    WARP_SECURITY_RG_WARNED=1
}

security_search_tree() {
    local _pattern="$1"
    shift

    if security_has_rg; then
        rg -n -H -e "$_pattern" "$@" 2>/dev/null
        return 0
    fi

    grep -RInE -- "$_pattern" "$@" 2>/dev/null
}

security_search_tree_i() {
    local _pattern="$1"
    shift

    if security_has_rg; then
        rg -n -H -i -e "$_pattern" "$@" 2>/dev/null
        return 0
    fi

    grep -RInEi -- "$_pattern" "$@" 2>/dev/null
}

security_find_and_search() {
    local _pattern="$1"
    shift
    local _find_args=("$@")

    if security_has_rg; then
        rg -n -H -e "$_pattern" "${_find_args[@]}" 2>/dev/null
        return 0
    fi

    find "${_find_args[@]}" -type f 2>/dev/null | while IFS= read -r _file; do
        [ -f "$_file" ] || continue
        grep -nHE -- "$_pattern" "$_file" 2>/dev/null
    done
}

security_find_named_and_search() {
    local _pattern="$1"
    shift
    local _root_list=()
    local _name_list=()
    local _arg=""
    local _file=""

    while [ $# -gt 0 ]; do
        _arg="$1"
        shift
        case "$_arg" in
            --name)
                [ $# -gt 0 ] || break
                _name_list+=("$1")
                shift
                ;;
            *)
                _root_list+=("$_arg")
                ;;
        esac
    done

    if security_has_rg; then
        local _rg_args=()
        for _arg in "${_name_list[@]}"; do
            _rg_args+=(-g "$_arg")
        done
        rg -n -H "${_rg_args[@]}" -e "$_pattern" "${_root_list[@]}" 2>/dev/null
        return 0
    fi

    for _arg in "${_root_list[@]}"; do
        [ -d "$_arg" ] || continue
        for _file in "${_name_list[@]}"; do
            find "$_arg" -type f -name "$_file" 2>/dev/null
        done
    done | while IFS= read -r _file; do
        [ -f "$_file" ] || continue
        grep -nHE -- "$_pattern" "$_file" 2>/dev/null
    done
}

security_known_paths_usage() {
    security_known_metadata_bootstrap

    if [ -f "$PROJECTPATH/.known-paths" ]; then
        warp_message ".known-paths:"
        sed 's/^/  /' "$PROJECTPATH/.known-paths"
    else
        warp_message ".known-paths:"
        warp_message "  (file not found)"
        warp_message "  create .known-paths with one relative path per line, for example:"
        warp_message "  pub/.well-known"
        warp_message "  pub/media/tmp"
    fi
    warp_message ""
    if [ -f "$PROJECTPATH/.known-files" ]; then
        warp_message ".known-files:"
        sed 's/^/  /' "$PROJECTPATH/.known-files"
    else
        warp_message ".known-files:"
        warp_message "  (file not found)"
    fi
    warp_message ""
    if [ -f "$PROJECTPATH/.known-findings" ]; then
        warp_message ".known-findings:"
        sed 's/^/  /' "$PROJECTPATH/.known-findings"
    else
        warp_message ".known-findings:"
        warp_message "  (file not found)"
    fi
    warp_message ""
}

security_toolkit_header() {
    local _title="$1"
    warp_message_info "[TOOLKIT]"
    warp_message " ${_title}"
    warp_message ""
}

security_toolkit_section_analysis_begin() {
    warp_message_info "[ANALYSIS]"
}

security_toolkit_section_cleanup_begin() {
    warp_message ""
    warp_message_warn "[CLEANUP - MANUAL]"
}

security_toolkit_print_command() {
    warp_message " $1"
}

security_toolkit_fs() {
    security_toolkit_header "SURFACE: fs"
    security_toolkit_section_analysis_begin
    security_toolkit_print_command 'find pub/media -type f \( -name "*.php" -o -name "*.phtml" -o -name "*.phar" -o -name "*.html" \)'
    security_toolkit_print_command 'find pub/media/custom_options -type f'
    security_toolkit_print_command 'find pub/media/customer_address -type f'
    security_toolkit_print_command 'find pub/media pub/static pub/opt -type f \( -name "*.php" -o -name "*.phtml" -o -name "*.phar" \) 2>/dev/null'
    security_toolkit_print_command 'grep -RInE "<\?php|base64_decode\(|passthru\(|system\(|shell_exec\(|assert\(|proc_open\(" pub/media pub/opt'
    security_toolkit_print_command 'grep -RInE "<\?php|md5\(\$_COOKIE\["d"\]\)|md5\(\$_COOKIE\['\''d'\''\]\)|new Function\(event\.data\)|RTCPeerConnection|createDataChannel|new WebSocket|wss://" pub/static'
    security_toolkit_print_command 'grep -R --line-number '\''md5($_COOKIE\["d"\])'\'' .'
    security_toolkit_print_command 'grep -RInE '\''md5\(\$_COOKIE\["d"\]\)|md5\(\$_COOKIE\['\''d'\''\]\)|new Function\(event\.data\)|preg_replace\s*\(.*/e|create_function\(|hash_equals\(md5\(|\$_REQUEST\["password"\]'\'' app pub var generated'
    security_toolkit_print_command 'git status --porcelain --untracked-files=all -- pub'
    security_toolkit_print_command 'git diff -- pub'
    security_toolkit_print_command 'cat .known-paths'
    security_toolkit_section_cleanup_begin
    security_toolkit_print_command 'mkdir -p var/quarantine'
    security_toolkit_print_command 'mv <suspicious-file> var/quarantine/'
    security_toolkit_print_command 'find pub/media -type f \( -name "*.php" -o -name "*.phtml" -o -name "*.phar" \) -delete'
    security_toolkit_print_command 'find pub/media/custom_options -type f -delete'
    security_toolkit_print_command 'find pub/media/customer_address -type f -delete'
    warp_message ""
}

security_toolkit_logs() {
    security_toolkit_header "SURFACE: logs"
    security_toolkit_section_analysis_begin
    security_toolkit_print_command 'grep -RInE "guest-carts/.*/items" /var/log/nginx /var/log/httpd'
    security_toolkit_print_command 'grep -RIn "customer/address_file/upload" /var/log/nginx /var/log/httpd'
    security_toolkit_print_command 'grep -RInE "estimate-shipping-methods|test-ambio" /var/log/nginx /var/log/httpd'
    security_toolkit_print_command 'grep -RInE "python-requests|curl|Go-http-client" /var/log/nginx /var/log/httpd'
    security_toolkit_print_command 'awk '\''$9 ~ /404|500|502|503|504/'\'' /var/log/nginx/access.log'
    security_toolkit_section_cleanup_begin
    security_toolkit_print_command '# preserve and export evidence before any cleanup'
    security_toolkit_print_command 'cp /var/log/nginx/access.log var/log/access.log.forensics.copy'
    warp_message ""
}

security_toolkit_db() {
    security_toolkit_header "SURFACE: db"
    security_toolkit_section_analysis_begin
    security_toolkit_print_command './warp db connect'
    security_toolkit_print_command "SELECT layout_update_id, handle, xml FROM layout_update WHERE xml REGEXP 'eval|base64|WebSocket|RTCPeerConnection|system\\(';"
    security_toolkit_print_command "SELECT block_id, title, identifier FROM cms_block WHERE content REGEXP 'eval|base64|wss://|WebSocket|RTCPeerConnection';"
    security_toolkit_print_command "SELECT config_id, path FROM core_config_data WHERE value REGEXP 'eval|base64|wss://|WebSocket';"
    security_toolkit_print_command "SELECT user_id, username, created, modified FROM admin_user ORDER BY modified DESC;"
    security_toolkit_section_cleanup_begin
    security_toolkit_print_command 'UPDATE layout_update SET xml=<clean> WHERE layout_update_id=<id>;'
    security_toolkit_print_command 'DELETE FROM layout_update WHERE layout_update_id=<id>;'
    security_toolkit_print_command '# prefer restoring known-good content before deleting rows'
    warp_message ""
}

security_toolkit_host() {
    security_toolkit_header "SURFACE: host"
    security_toolkit_section_analysis_begin
    security_toolkit_print_command 'crontab -l'
    security_toolkit_print_command 'grep -RInE "defunct|base64|LD_PRELOAD|gsocket" /etc/cron* /var/spool/cron /var/spool/cron/crontabs'
    security_toolkit_print_command 'ps auxww | grep -E "\[raid5wq\]|\[kswapd0\]|defunct|gsocket|nginx: worker process"'
    security_toolkit_print_command 'grep -al LD_L1BRARY_PATH /proc/*/environ 2>/dev/null'
    security_toolkit_print_command 'find /dev/shm ~/.config ~/.cache -maxdepth 3 -type f'
    security_toolkit_section_cleanup_begin
    security_toolkit_print_command 'crontab -e'
    security_toolkit_print_command 'kill -9 <pid>'
    security_toolkit_print_command 'rm -f ~/.config/htop/defunct ~/.config/htop/defunct.dat'
    security_toolkit_print_command 'rm -f /dev/shm/php-shared'
    warp_message ""
}

security_toolkit_nginx() {
    security_toolkit_header "SURFACE: nginx"
    security_toolkit_section_analysis_begin
    security_toolkit_print_command 'grep -RIn "location" /etc/nginx /usr/local/nginx/conf'
    security_toolkit_print_command 'grep -RIn "php" /etc/nginx /usr/local/nginx/conf'
    security_toolkit_print_command 'grep -RIn "custom_options" /etc/nginx /usr/local/nginx/conf'
    security_toolkit_print_command 'nginx -T | grep -n "custom_options"'
    security_toolkit_section_cleanup_begin
    security_toolkit_print_command 'nginx -t'
    security_toolkit_print_command '# manually edit nginx config to block PHP execution in uploads'
    security_toolkit_print_command '# reload nginx manually after validating the change'
    warp_message ""
}

security_toolkit_family_polyshell() {
    security_toolkit_header "FAMILY: polyshell"
    security_toolkit_section_analysis_begin
    security_toolkit_print_command 'find pub/media/custom_options -type f'
    security_toolkit_print_command 'find pub/media/custom_options -type f \( -name "*.php" -o -name "*.phtml" -o -name "*.phar" -o -name "*.html" \)'
    security_toolkit_print_command 'grep -RInE "GIF89a|<\?php|eval\(base64_decode|system\(" pub/media/custom_options'
    security_toolkit_print_command 'grep -RInE "guest-carts/.*/items" <access-log>'
    security_toolkit_print_command 'git status --porcelain --untracked-files=all -- pub'
    security_toolkit_section_cleanup_begin
    security_toolkit_print_command 'mkdir -p var/quarantine'
    security_toolkit_print_command 'mv pub/media/custom_options/<file> var/quarantine/'
    security_toolkit_print_command 'find pub/media/custom_options -type f \( -name "*.php" -o -name "*.phtml" -o -name "*.phar" \) -delete'
    warp_message ""
}

security_toolkit_family_sessionreaper() {
    security_toolkit_header "FAMILY: sessionreaper"
    security_toolkit_section_analysis_begin
    security_toolkit_print_command 'find pub/media/customer_address -type f'
    security_toolkit_print_command 'grep -RIn "customer/address_file/upload" <access-log>'
    security_toolkit_print_command 'grep -RIl "<?php" pub/media/customer_address'
    security_toolkit_section_cleanup_begin
    security_toolkit_print_command 'mkdir -p var/quarantine'
    security_toolkit_print_command 'mv pub/media/customer_address/<file> var/quarantine/'
    security_toolkit_print_command 'find pub/media/customer_address -type f -delete'
    warp_message ""
}

security_toolkit_family_cosmicsting() {
    security_toolkit_header "FAMILY: cosmicsting"
    security_toolkit_section_analysis_begin
    security_toolkit_print_command 'grep -RIn "estimate-shipping-methods" <access-log>'
    security_toolkit_print_command 'grep -RIn "test-ambio" <access-log>'
    security_toolkit_print_command 'find ~/.config/htop -maxdepth 2 -type f'
    security_toolkit_print_command 'crontab -l | grep -n "defunct"'
    security_toolkit_print_command 'ps auxww | grep -E "raid5wq|kswapd0|defunct"'
    security_toolkit_section_cleanup_begin
    security_toolkit_print_command 'crontab -e'
    security_toolkit_print_command 'kill -9 <pid>'
    security_toolkit_print_command 'rm -f ~/.config/htop/defunct ~/.config/htop/defunct.dat'
    warp_message ""
}

security_toolkit_family_webshell() {
    security_toolkit_header "FAMILY: webshell"
    security_toolkit_section_analysis_begin
    security_toolkit_print_command 'find pub/media pub/static pub/opt -type f \( -name "*.php" -o -name "*.phtml" -o -name "*.phar" \) 2>/dev/null'
    security_toolkit_print_command 'grep -RInE "<\?php|base64_decode\(|passthru\(|system\(|shell_exec\(|assert\(|proc_open\(" pub/media pub/opt'
    security_toolkit_print_command 'grep -RInE "<\?php|md5\(\$_COOKIE\["d"\]\)|md5\(\$_COOKIE\['\''d'\''\]\)|new Function\(event\.data\)|RTCPeerConnection|createDataChannel|new WebSocket|wss://" pub/static'
    security_toolkit_print_command 'grep -R --line-number '\''md5($_COOKIE\["d"\])'\'' .'
    security_toolkit_print_command 'git status --porcelain --untracked-files=all -- pub'
    security_toolkit_print_command 'git diff -- pub'
    security_toolkit_section_cleanup_begin
    security_toolkit_print_command 'mkdir -p var/quarantine'
    security_toolkit_print_command 'mv <suspicious-file> var/quarantine/'
    security_toolkit_print_command 'rm -f <suspicious-file>'
    warp_message ""
}

security_toolkit_family_xml() {
    security_toolkit_header "FAMILY: xml"
    security_toolkit_section_analysis_begin
    security_toolkit_print_command './warp db connect'
    security_toolkit_print_command "SELECT layout_update_id, handle, xml FROM layout_update WHERE xml REGEXP 'eval|base64|WebSocket|RTCPeerConnection|system\\(';"
    security_toolkit_print_command "SELECT block_id, title, identifier FROM cms_block WHERE content REGEXP 'eval|base64|wss://|WebSocket|RTCPeerConnection';"
    security_toolkit_section_cleanup_begin
    security_toolkit_print_command 'UPDATE layout_update SET xml=<clean> WHERE layout_update_id=<id>;'
    security_toolkit_print_command 'DELETE FROM layout_update WHERE layout_update_id=<id>;'
    warp_message ""
}

security_toolkit_family_skimmer() {
    security_toolkit_header "FAMILY: skimmer"
    security_toolkit_section_analysis_begin
    security_toolkit_print_command 'grep -RInE "new WebSocket|wss://|RTCPeerConnection|createDataChannel" app pub vendor'
    security_toolkit_print_command 'grep -RInE "sellerstat|statsseo|inspectdlet|iconstaff" app pub vendor'
    security_toolkit_print_command "SELECT block_id, title, identifier FROM cms_block WHERE content REGEXP 'wss://|WebSocket|RTCPeerConnection';"
    security_toolkit_section_cleanup_begin
    security_toolkit_print_command '# restore known-good template or CMS block content'
    security_toolkit_print_command '# remove malicious domain/payload manually after confirming the source'
    warp_message ""
}

security_toolkit_family_hardening() {
    security_toolkit_header "FAMILY: hardening"
    security_toolkit_section_analysis_begin
    security_toolkit_print_command 'find pub/static pub/opt -type f \( -name "*.php" -o -name "*.phtml" -o -name "*.phar" \) 2>/dev/null'
    security_toolkit_print_command 'nginx -T | grep -n "custom_options"'
    security_toolkit_print_command 'cat .known-paths'
    security_toolkit_section_cleanup_begin
    security_toolkit_print_command 'nginx -t'
    security_toolkit_print_command '# manually block PHP execution below pub/media, pub/static and pub/opt'
    warp_message ""
}

security_toolkit_render_surface() {
    case "$1" in
        fs) security_toolkit_fs ;;
        logs) security_toolkit_logs ;;
        db) security_toolkit_db ;;
        host) security_toolkit_host ;;
        nginx) security_toolkit_nginx ;;
        *)
            warp_message_error "Unknown surface: $1"
            return 1
        ;;
    esac
}

security_toolkit_render_family() {
    case "$1" in
        polyshell) security_toolkit_family_polyshell ;;
        sessionreaper) security_toolkit_family_sessionreaper ;;
        cosmicsting) security_toolkit_family_cosmicsting ;;
        webshell) security_toolkit_family_webshell ;;
        xml) security_toolkit_family_xml ;;
        skimmer) security_toolkit_family_skimmer ;;
        hardening) security_toolkit_family_hardening ;;
        *)
            warp_message_error "Unknown family: $1"
            return 1
        ;;
    esac
}

security_toolkit_collect_from_log() {
    local _log_file="$1"

    [ -f "$_log_file" ] || return 1

    if awk '
        BEGIN { in_section=0; has_findings=0 }
        /^\[PUB_DRIFT\]$/ { in_section=1; has_findings=0; next }
        /^\[/ && $0 != "[PUB_DRIFT]" { in_section=0 }
        in_section && $0 !~ /^(discovery:|cleanup:|No findings\.|=+|$)/ { has_findings=1 }
        END { exit(has_findings ? 0 : 1) }
    ' "$_log_file"; then
        printf '%s\n' "webshell"
    fi

    if awk '
        BEGIN { in_section=0; has_findings=0 }
        /^\[CORE_PUB_ENTRYPOINTS\]$/ { in_section=1; has_findings=0; next }
        /^\[/ && $0 != "[CORE_PUB_ENTRYPOINTS]" { in_section=0 }
        in_section && $0 !~ /^(discovery:|cleanup:|No findings\.|=+|$)/ { has_findings=1 }
        END { exit(has_findings ? 0 : 1) }
    ' "$_log_file"; then
        printf '%s\n' "webshell"
    fi

    if awk '
        BEGIN { in_section=0; has_findings=0 }
        /^\[PHP_IN_PUB\]$/ { in_section=1; has_findings=0; next }
        /^\[/ && $0 != "[PHP_IN_PUB]" { in_section=0 }
        in_section && $0 !~ /^(discovery:|cleanup:|No findings\.|=+|$)/ { has_findings=1 }
        END { exit(has_findings ? 0 : 1) }
    ' "$_log_file"; then
        printf '%s\n' "webshell"
    fi

    if awk '
        BEGIN { in_section=0; has_findings=0 }
        /^\[PHP_MARKERS_IN_UPLOADS\]$/ { in_section=1; has_findings=0; next }
        /^\[/ && $0 != "[PHP_MARKERS_IN_UPLOADS]" { in_section=0 }
        in_section && $0 !~ /^(discovery:|cleanup:|No findings\.|=+|$)/ { has_findings=1 }
        END { exit(has_findings ? 0 : 1) }
    ' "$_log_file"; then
        printf '%s\n' "webshell"
    fi

    if awk '
        BEGIN { in_section=0; found=0 }
        /^\[JS_SKIMMER\]$/ { in_section=1; next }
        /^\[/ && $0 != "[JS_SKIMMER]" { in_section=0 }
        in_section && $0 !~ /^(discovery:|cleanup:|No findings\.|=+|$)/ { found=1 }
        END { exit(found ? 0 : 1) }
    ' "$_log_file"; then
        printf '%s\n' "skimmer"
    fi

    if awk '
        BEGIN { in_section=0; found=0 }
        /^\[KNOWN_IOC\]$/ { in_section=1; next }
        /^\[/ && $0 != "[KNOWN_IOC]" { in_section=0 }
        in_section && $0 !~ /^(discovery:|cleanup:|No findings\.|=+|$)/ && /RTCPeerConnection|new Function\(event\.data\)/ { found=1 }
        END { exit(found ? 0 : 1) }
    ' "$_log_file"; then
        printf '%s\n' "skimmer"
    fi

    if awk '
        BEGIN { in_section=0; found=0 }
        /^\[KNOWN_IOC\]$/ { in_section=1; next }
        /^\[/ && $0 != "[KNOWN_IOC]" { in_section=0 }
        in_section && $0 !~ /^(discovery:|cleanup:|No findings\.|=+|$)/ { found=1 }
        END { exit(found ? 0 : 1) }
    ' "$_log_file"; then
        printf '%s\n' "webshell"
    fi

    if awk '
        BEGIN { in_section=0; found=0 }
        /^\[ACCESS_LOG_IOC\]$/ { in_section=1; next }
        /^\[/ && $0 != "[ACCESS_LOG_IOC]" { in_section=0 }
        in_section && $0 !~ /^(discovery:|cleanup:|No findings\.|source:|=+|$)/ && /guest-carts\/.*items/ { found=1 }
        END { exit(found ? 0 : 1) }
    ' "$_log_file"; then
        printf '%s\n' "polyshell"
    fi

    if awk '
        BEGIN { in_section=0; found=0 }
        /^\[ACCESS_LOG_IOC\]$/ { in_section=1; next }
        /^\[/ && $0 != "[ACCESS_LOG_IOC]" { in_section=0 }
        in_section && $0 !~ /^(discovery:|cleanup:|No findings\.|source:|=+|$)/ && /customer\/address_file\/upload/ { found=1 }
        END { exit(found ? 0 : 1) }
    ' "$_log_file"; then
        printf '%s\n' "sessionreaper"
    fi

    if awk '
        BEGIN { in_section=0; found=0 }
        /^\[ACCESS_LOG_IOC\]$/ { in_section=1; next }
        /^\[/ && $0 != "[ACCESS_LOG_IOC]" { in_section=0 }
        in_section && $0 !~ /^(discovery:|cleanup:|No findings\.|source:|=+|$)/ && /estimate-shipping-methods|test-ambio|python-requests|Go-http-client/ { found=1 }
        END { exit(found ? 0 : 1) }
    ' "$_log_file"; then
        printf '%s\n' "cosmicsting"
    fi

    if awk '
        BEGIN { in_section=0; has_findings=0 }
        /^\[HOST_PERSISTENCE\]$/ { in_section=1; has_findings=0; next }
        /^\[/ && $0 != "[HOST_PERSISTENCE]" { in_section=0 }
        in_section && $0 !~ /^(discovery:|cleanup:|No findings\.|=+|$)/ { has_findings=1 }
        END { exit(has_findings ? 0 : 1) }
    ' "$_log_file"; then
        printf '%s\n' "cosmicsting"
    fi
}

security_toolkit_render_from_log() {
    local _from_log="$1"
    local _family=""
    local _rendered=""

    if [ ! -f "$_from_log" ]; then
        warp_message_error "Log file not found: $_from_log"
        return 1
    fi

    _rendered="$(security_toolkit_collect_from_log "$_from_log" | sort -u)"
    if [ -z "$_rendered" ]; then
        warp_message_warn "No actionable families detected in log: $_from_log"
        warp_message "Try a broader toolkit:"
        warp_message "  warp security toolkit --surface fs"
        warp_message "  warp security toolkit --surface logs"
        warp_message "  warp security toolkit --surface host"
        warp_message ""
        return 0
    fi

    warp_message_info "[TOOLKIT]"
    warp_message " contextual source: $_from_log"
    warp_message ""

    while IFS= read -r _family; do
        [ -n "$_family" ] || continue
        security_toolkit_render_family "$_family" || return 1
    done <<EOF
$_rendered
EOF

    return 0
}

security_toolkit_main() {
    local _family=""
    local _surface=""
    local _with_cleanup="false"
    local _from_log=""
    local _arg=""

    while [ $# -gt 0 ]; do
        case "$1" in
            --family)
                shift
                _family="$1"
                ;;
            --surface)
                shift
                _surface="$1"
                ;;
            --with-cleanup)
                _with_cleanup="true"
                ;;
            --from-log)
                shift
                _from_log="$1"
                ;;
            -h|--help)
                security_help_usage
                return 0
                ;;
            *)
                warp_message_error "Unknown toolkit option: $1"
                return 1
                ;;
        esac
        shift
    done

    if [ -n "$_from_log" ]; then
        if [ -n "$_family" ] || [ -n "$_surface" ]; then
            warp_message_error "Use --from-log alone, without --family or --surface."
            return 1
        fi
        security_known_paths_usage
        security_toolkit_render_from_log "$_from_log"
        return $?
    fi

    security_known_paths_usage

    if [ -n "$_family" ] && [ -n "$_surface" ]; then
        warp_message_error "Use either --family or --surface, not both."
        return 1
    fi

    if [ -n "$_family" ]; then
        security_toolkit_render_family "$_family" || return 1
        return 0
    fi

    if [ -n "$_surface" ]; then
        security_toolkit_render_surface "$_surface" || return 1
        return 0
    fi

    warp_message_info "[TOOLKIT]"
    warp_message " families: polyshell, sessionreaper, cosmicsting, webshell, xml, skimmer, hardening"
    warp_message " surfaces: fs, logs, db, host, nginx"
    warp_message ""
    warp_message " try:"
    warp_message "  warp security toolkit --family polyshell"
    warp_message "  warp security toolkit --family webshell"
    warp_message "  warp security toolkit --surface fs"
    if [ "$_with_cleanup" = "true" ]; then
        warp_message "  cleanup commands are already included below each section."
    fi
    warp_message ""

    security_toolkit_family_polyshell
    security_toolkit_family_webshell
    security_toolkit_family_skimmer
    return 0
}

security_git_status_effective_path() {
    local _path="$1"

    case "$_path" in
        *" -> "*)
            echo "${_path##* -> }"
            ;;
        *)
            echo "$_path"
            ;;
    esac
}

security_scan_fast_git() {
    local _line=""
    local _status=""
    local _path=""
    local _effective_path=""

    while IFS= read -r _line; do
        [ -n "$_line" ] || continue
        _status="${_line:0:2}"
        _path="${_line:3}"
        [ -n "$_path" ] || continue
        _effective_path="$(security_git_status_effective_path "$_path")"

        if [ "$_status" = "??" ] && security_path_is_known "$_effective_path"; then
            continue
        fi

        WARP_SECURITY_SCAN_DRIFT=$((WARP_SECURITY_SCAN_DRIFT + 1))
        WARP_SECURITY_SCAN_FINDINGS=$((WARP_SECURITY_SCAN_FINDINGS + 1))
        WARP_SECURITY_SCAN_SCORE=$((WARP_SECURITY_SCAN_SCORE + 2))
        security_scan_append_attention "${_effective_path} - git drift [${_status}]"

        case "$_effective_path" in
            pub/*)
                security_append_screen_family "webshell"
                WARP_SECURITY_SCAN_SCORE=$((WARP_SECURITY_SCAN_SCORE + 4))
                ;;
            app/*|bin/*|generated/*) security_append_screen_family "review" ;;
        esac
    done < <(git status --porcelain --untracked-files=all -- pub app bin generated 2>/dev/null)
}

security_scan_fast_php_in_pub() {
    local _found=""
    local _path=""

    while IFS= read -r _path; do
        [ -n "$_path" ] || continue
        _path="${_path#$PROJECTPATH/}"
        security_file_is_known "$_path" && continue
        _found="$_path"
        break
    done < <(find "$PROJECTPATH/pub" \
        -path "$PROJECTPATH/pub/errors" -prune -o \
        -type f \( -name '*.php' -o -name '*.phtml' -o -name '*.phar' \) \
        -print 2>/dev/null)

    [ -n "$_found" ] || return 0

    WARP_SECURITY_SCAN_CODE=$((WARP_SECURITY_SCAN_CODE + 1))
    WARP_SECURITY_SCAN_FINDINGS=$((WARP_SECURITY_SCAN_FINDINGS + 1))
    WARP_SECURITY_SCAN_SCORE=$((WARP_SECURITY_SCAN_SCORE + 20))
    security_append_screen_family "webshell"
    return 0
}

security_scan_fast_core_pub_entrypoints() {
    local _line=""
    local _file_args=()

    while IFS= read -r _line; do
        [ -n "$_line" ] || continue
        _file_args+=("$_line")
    done < <(security_known_files_list)

    [ "${#_file_args[@]}" -gt 0 ] || return 0

    while IFS= read -r _line; do
        [ -n "$_line" ] || continue
        WARP_SECURITY_SCAN_CODE=$((WARP_SECURITY_SCAN_CODE + 1))
        WARP_SECURITY_SCAN_FINDINGS=$((WARP_SECURITY_SCAN_FINDINGS + 1))
        WARP_SECURITY_SCAN_SCORE=$((WARP_SECURITY_SCAN_SCORE + 10))
        security_append_screen_family "review"
        return 0
    done < <(git status --porcelain --untracked-files=all -- "${_file_args[@]}" 2>/dev/null)

    return 0
}

security_scan_fast_code() {
    local _line=""
    local _path=""
    local _indicator=""
    local _class=""

    while IFS= read -r _line; do
        [ -n "$_line" ] || continue
        security_scan_should_ignore_line "$_line" && continue
        _path="${_line%%:*}"
        [ -n "$_path" ] || continue
        _indicator="$(security_scan_indicator_for_match "$_line")"
        _class="$(security_scan_class_for_match "$_line")"
        security_finding_is_known "$_path" "$_indicator" "$_class" && continue

        WARP_SECURITY_SCAN_CODE=$((WARP_SECURITY_SCAN_CODE + 1))
        WARP_SECURITY_SCAN_FINDINGS=$((WARP_SECURITY_SCAN_FINDINGS + 1))
        WARP_SECURITY_SCAN_SCORE=$((WARP_SECURITY_SCAN_SCORE + 4))
        security_scan_append_attention "${_path} - ${_indicator} [${_class}]"

        case "$_line" in
            *eval\(base64_decode*|*gzuncompress\(base64_decode*|*str_rot13*base64_decode*|*md5\(\$_COOKIE*|*hash_equals\(md5*|*\$_REQUEST*system\(*|*\$_COOKIE*system\(*|*\$_POST*system\(*)
                security_append_screen_family "webshell"
                WARP_SECURITY_SCAN_STRONG=$((WARP_SECURITY_SCAN_STRONG + 1))
                WARP_SECURITY_SCAN_SCORE=$((WARP_SECURITY_SCAN_SCORE + 16))
                ;;
            *)
                security_append_screen_family "review"
                ;;
        esac
    done < <(security_find_named_and_search \
        'eval\s*\(|base64_decode\s*\(|(^|[^[:alnum:]_])system\s*\(|shell_exec\s*\(|passthru\s*\(|assert\s*\(|proc_open\s*\(|preg_replace\s*\(.*/e|create_function\s*\(|eval\s*\(\s*base64_decode|gzuncompress\s*\(\s*base64_decode|str_rot13\s*\(.*base64_decode|md5\(\$_COOKIE|hash_equals\s*\(\s*md5\(|\$_REQUEST|\$_COOKIE|\$_POST' \
        "$PROJECTPATH/pub" "$PROJECTPATH/app" "$PROJECTPATH/bin" \
        --name '*.php' --name '*.phtml' --name '*.phar' --name '*.inc' | sed "s#^$PROJECTPATH/##")
}

security_scan_fast_js() {
    local _line=""
    local _path=""
    local _indicator=""
    local _class=""

    while IFS= read -r _line; do
        [ -n "$_line" ] || continue
        security_scan_should_ignore_line "$_line" && continue
        security_scan_should_ignore_known_js_library_match "$_line" && continue
        _path="${_line%%:*}"
        [ -n "$_path" ] || continue
        _indicator="$(security_scan_indicator_for_match "$_line")"
        _class="$(security_scan_class_for_match "$_line")"
        security_finding_is_known "$_path" "$_indicator" "$_class" && continue

        WARP_SECURITY_SCAN_CODE=$((WARP_SECURITY_SCAN_CODE + 1))
        WARP_SECURITY_SCAN_FINDINGS=$((WARP_SECURITY_SCAN_FINDINGS + 1))
        WARP_SECURITY_SCAN_STRONG=$((WARP_SECURITY_SCAN_STRONG + 1))
        WARP_SECURITY_SCAN_SCORE=$((WARP_SECURITY_SCAN_SCORE + 20))
        security_scan_append_attention "${_path} - ${_indicator} [${_class}]"
        security_append_screen_family "skimmer"
    done < <(security_find_named_and_search \
        'RTCPeerConnection|createDataChannel|new WebSocket|wss://|new Function\(event\.data\)' \
        "$PROJECTPATH/pub" "$PROJECTPATH/app" \
        --name '*.js' --name '*.phtml' --name '*.html' | sed "s#^$PROJECTPATH/##")
}

security_scan_fast_suspicion() {
    if [ "${WARP_SECURITY_SCAN_SCORE:-0}" -ge 60 ]; then
        echo "high"
        return 0
    fi

    if [ "${WARP_SECURITY_SCAN_SCORE:-0}" -ge 20 ]; then
        echo "medium"
        return 0
    fi

    if [ "${WARP_SECURITY_SCAN_SCORE:-0}" -gt 0 ]; then
        echo "low"
        return 0
    fi

    echo "none"
}

security_scan_indicator_for_match() {
    local _line="$1"

    case "$_line" in
        *eval\(base64_decode*) echo "eval(base64_decode)" ;;
        *gzuncompress*base64_decode*|*base64_decode*gzuncompress*) echo "gzuncompress(base64_decode)" ;;
        *str_rot13*base64_decode*|*base64_decode*str_rot13*) echo "str_rot13 + base64_decode" ;;
        *md5\(\$_COOKIE*) echo 'md5($_COOKIE["d"])' ;;
        *hash_equals\(md5*) echo "hash_equals(md5(...))" ;;
        *base64_decode*) echo "base64_decode" ;;
        *shell_exec*) echo "shell_exec" ;;
        *passthru*) echo "passthru" ;;
        *proc_open*) echo "proc_open" ;;
        *system\(*) echo "system()" ;;
        *assert\(*) echo "assert()" ;;
        *preg_replace*) echo "preg_replace /e" ;;
        *create_function*) echo "create_function" ;;
        *RTCPeerConnection*) echo "RTCPeerConnection" ;;
        *createDataChannel*) echo "createDataChannel" ;;
        *new\ WebSocket*) echo "new WebSocket" ;;
        *wss://*) echo "wss://" ;;
        *new\ Function\(event.data\)*) echo "new Function(event.data)" ;;
        *\$_REQUEST*) echo '$_REQUEST' ;;
        *\$_COOKIE*) echo '$_COOKIE' ;;
        *\$_POST*) echo '$_POST' ;;
        *) echo "heuristic match" ;;
    esac
}

security_scan_class_for_match() {
    local _line="$1"

    case "$_line" in
        *RTCPeerConnection*|*createDataChannel*|*new\ WebSocket*|*wss://*|*new\ Function\(event.data\)*)
            echo "js skimmer"
            ;;
        *md5\(\$_COOKIE*|*eval\(base64_decode*|*gzuncompress*base64_decode*|*hash_equals\(md5*|*preg_replace*|*create_function*)
            echo "known IOC"
            ;;
        *base64_decode*|*shell_exec*|*passthru*|*proc_open*|*system\(*|*assert\(*|*\$_REQUEST*|*\$_COOKIE*|*\$_POST*)
            echo "risky primitive"
            ;;
        *)
            echo "review"
            ;;
    esac
}

security_scan_should_ignore_known_js_library_match() {
    local _line="$1"
    local _path=""

    _path="${_line%%:*}"
    [ -n "$_path" ] || return 1

    case "$_path" in
        pub/static/*jquery/uppy/*)
            case "$_line" in
                *new\ WebSocket*)
                    case "$_line" in
                        *wss://*|*RTCPeerConnection*|*createDataChannel*|*new\ Function\(event.data\)*)
                            return 1
                            ;;
                    esac
                    return 0
                    ;;
            esac
            ;;
    esac

    return 1
}

security_scan_should_ignore_known_ioc_path() {
    local _line="$1"
    local _path=""

    _path="${_line%%:*}"
    [ -n "$_path" ] || return 1

    case "$_path" in
        */node_modules/*|var/log/*|var/hyva*/*)
            return 0
            ;;
    esac

    return 1
}

security_scan_append_attention() {
    local _entry="$1"

    WARP_SECURITY_SCAN_PATHS="${WARP_SECURITY_SCAN_PATHS}"$'\n'"${_entry}"
}

security_scan_should_ignore_line() {
    local _line="$1"
    local _content=""
    local _trimmed=""

    _content="${_line#*:}"
    _content="${_content#*:}"
    _trimmed="${_content#"${_content%%[![:space:]]*}"}"

    case "$_trimmed" in
        //*) return 0 ;;
        '/*'*) return 0 ;;
        '*/'*) return 0 ;;
        \**) return 0 ;;
    esac

    case "$_content" in
        *"//"*"audit:ignore"*) return 0 ;;
    esac

    return 1
}

security_process_line() {
    local _label="$1"
    printf '%-35s' "$_label"
}

security_process_notice() {
    printf '%b\n' "${FRED}[FOUND]${RS}"
}

security_process_ok_local() {
    printf '%b\n' "${FGRN}[SAFE]${RS}"
}

security_process_fail_local() {
    printf '%b\n' "${FYEL}[FAIL]${RS}"
}

security_step_run() {
    local _label="$1"
    local _fn="$2"
    local _before=0
    local _after=0
    local _delta=0
    local _status=0

    _before=$(( ${WARP_SECURITY_FINDINGS:-0} + ${WARP_SECURITY_SCAN_FINDINGS:-0} ))
    security_process_line "$_label"
    "$_fn"
    _status=$?
    if [ $_status -ne 0 ]; then
        security_process_fail_local
        return $_status
    fi

    _after=$(( ${WARP_SECURITY_FINDINGS:-0} + ${WARP_SECURITY_SCAN_FINDINGS:-0} ))
    _delta=$((_after - _before))
    if [ "$_delta" -gt 0 ]; then
        security_process_notice
    else
        security_process_ok_local
    fi

    return 0
}

security_scan_fast_attention_paths() {
    printf '%s\n' "$WARP_SECURITY_SCAN_PATHS" | sed '/^$/d' | sort -u | head -n 30
}

security_scan_attention_paths_total() {
    printf '%s\n' "$WARP_SECURITY_SCAN_PATHS" | sed '/^$/d' | sort -u | wc -l | awk '{print $1}'
}

security_known_references_note() {
    warp_message " known refs: .known-paths .known-files .known-findings"
}

security_scan_main() {
    local _suspicion=""
    local _path=""
    local _status=""
    local _shown_count=0
    local _total_count=0

    if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
        security_help_usage
        return 0
    fi

    security_known_metadata_bootstrap
    WARP_SECURITY_SCAN_FINDINGS=0
    WARP_SECURITY_SCAN_DRIFT=0
    WARP_SECURITY_SCAN_CODE=0
    WARP_SECURITY_SCAN_STRONG=0
    WARP_SECURITY_SCAN_SCORE=0
    WARP_SECURITY_SCAN_PATHS=""
    WARP_SECURITY_FAMILIES=""
    WARP_SECURITY_RG_WARNED=0

    security_warn_missing_rg_once
    security_step_run "Checking git drift..." security_scan_fast_git || return 1
    security_step_run "Checking PHP in pub..." security_scan_fast_php_in_pub || return 1
    security_step_run "Checking core pub entrypoints..." security_scan_fast_core_pub_entrypoints || return 1
    security_step_run "Checking risky PHP primitives..." security_scan_fast_code || return 1
    security_step_run "Checking JS skimmer signals..." security_scan_fast_js || return 1

    _suspicion="$(security_scan_fast_suspicion)"
    _status="$(security_level_status "$_suspicion")"

    warp_message_info "[SECURITY SCAN]"
    warp_message " suspicion: $(security_level_badge "$_suspicion")"
    warp_message " status: $_status"
    warp_message " score: $WARP_SECURITY_SCAN_SCORE"
    warp_message " drift signals: $WARP_SECURITY_SCAN_DRIFT"
    warp_message " code signals: $WARP_SECURITY_SCAN_CODE"
    security_known_references_note

    if [ "$WARP_SECURITY_SCAN_FINDINGS" -gt 0 ]; then
        warp_message " attention paths:"
        while IFS= read -r _path; do
            [ -n "$_path" ] || continue
            _shown_count=$((_shown_count + 1))
            warp_message "  $_path"
        done < <(security_scan_fast_attention_paths)
        _total_count="$(security_scan_attention_paths_total)"
        if [ "$_total_count" -gt "$_shown_count" ]; then
            warp_message "  showing ${_shown_count}/${_total_count}"
        fi
    fi

    case "$_suspicion" in
        medium|high)
            warp_message ""
            warp_message_warn "Review suggested:"
            warp_message "  warp security check"
            warp_message "  warp security toolkit --from-log var/log/warp-security.log"
            ;;
    esac

    warp_message ""
    return 0
}

security_scan_git_pub_drift() {
    local _line=""
    local _path=""
    local _status=""
    local _discover="git status --porcelain --untracked-files=all -- pub"
    local _cleanup='git diff -- pub && mkdir -p var/quarantine && mv <suspicious-file> var/quarantine/'

    WARP_SECURITY_SECTION_FINDINGS=0
    security_log_section_begin "PUB_DRIFT" "$_discover" "$_cleanup"

    while IFS= read -r _line; do
        [ -n "$_line" ] || continue
        _status="${_line:0:2}"
        _path="${_line:3}"
        [ -n "$_path" ] || continue
        security_path_is_known "$_path" && continue
        WARP_SECURITY_SECTION_FINDINGS=$((WARP_SECURITY_SECTION_FINDINGS + 1))
        security_add_score 8
        security_record_finding "${_status} ${_path}" "webshell"
    done < <(git status --porcelain --untracked-files=all -- pub 2>/dev/null)

    security_finish_section_empty_if_needed
}

security_scan_php_in_pub() {
    local _path=""
    local _discover='find pub/media pub/static pub/opt -type f \( -name "*.php" -o -name "*.phtml" -o -name "*.phar" \) 2>/dev/null'
    local _cleanup='mkdir -p var/quarantine && mv <suspicious-file> var/quarantine/'
    local _note=""

    WARP_SECURITY_SECTION_FINDINGS=0
    security_log_section_begin "PHP_IN_PUB" "$_discover" "$_cleanup"

    while IFS= read -r _path; do
        [ -n "$_path" ] || continue
        _note=""
        if security_path_is_known "$_path"; then
            _note=" [known path]"
        fi
        WARP_SECURITY_SECTION_FINDINGS=$((WARP_SECURITY_SECTION_FINDINGS + 1))
        security_add_score 30
        security_record_finding "${_path}${_note}" "webshell"
    done < <(find "$PROJECTPATH/pub/media" "$PROJECTPATH/pub/static" "$PROJECTPATH/pub/opt" -type f \( -name "*.php" -o -name "*.phtml" -o -name "*.phar" \) 2>/dev/null | sed "s#^$PROJECTPATH/##")

    security_finish_section_empty_if_needed
}

security_scan_core_pub_entrypoints() {
    local _line=""
    local _status=""
    local _path=""
    local _discover='git status --porcelain --untracked-files=all -- $(cat .known-files)'
    local _cleanup='git diff -- $(cat .known-files)'
    local _file_args=()

    WARP_SECURITY_SECTION_FINDINGS=0
    security_log_section_begin "CORE_PUB_ENTRYPOINTS" "$_discover" "$_cleanup"

    while IFS= read -r _line; do
        [ -n "$_line" ] || continue
        _file_args+=("$_line")
    done < <(security_known_files_list)

    [ "${#_file_args[@]}" -gt 0 ] || {
        security_finish_section_empty_if_needed
        return 0
    }

    while IFS= read -r _line; do
        [ -n "$_line" ] || continue
        _status="${_line:0:2}"
        _path="${_line:3}"
        [ -n "$_path" ] || continue
        WARP_SECURITY_SECTION_FINDINGS=$((WARP_SECURITY_SECTION_FINDINGS + 1))
        security_add_score 20
        security_record_finding "${_status} ${_path}" "webshell"
    done < <(git status --porcelain --untracked-files=all -- "${_file_args[@]}" 2>/dev/null)

    security_finish_section_empty_if_needed
}

security_scan_php_markers_in_pub() {
    local _discover='grep -RInE "<\?php|base64_decode\(|passthru\(|system\(|shell_exec\(|assert\(|proc_open\(" pub/media pub/opt'
    local _cleanup='mkdir -p var/quarantine && mv <suspicious-file> var/quarantine/'
    local _line=""
    local _path=""
    local _indicator=""
    local _class=""

    WARP_SECURITY_SECTION_FINDINGS=0
    security_log_section_begin "PHP_MARKERS_IN_UPLOADS" "$_discover" "$_cleanup"

    while IFS= read -r _line; do
        [ -n "$_line" ] || continue
        _path="${_line%%:*}"
        [ -n "$_path" ] || continue
        _indicator="$(security_scan_indicator_for_match "$_line")"
        _class="$(security_scan_class_for_match "$_line")"
        security_finding_is_known "$_path" "$_indicator" "$_class" && continue
        WARP_SECURITY_SECTION_FINDINGS=$((WARP_SECURITY_SECTION_FINDINGS + 1))
        security_add_score 15
        security_record_finding "$_line" "webshell"
    done < <(security_search_tree '<\?php|base64_decode\(|passthru\(|system\(|shell_exec\(|assert\(|proc_open\(' "$PROJECTPATH/pub/media" "$PROJECTPATH/pub/opt" | sed "s#^$PROJECTPATH/##")

    security_finish_section_empty_if_needed
}

security_scan_js_skimmer() {
    local _discover='grep -RInE "RTCPeerConnection|createDataChannel|new WebSocket|wss://|new Function\(event\.data\)" app pub'
    local _cleanup='restore known-good JS/template content before removing suspicious snippets'
    local _line=""
    local _path=""
    local _indicator=""
    local _class=""

    WARP_SECURITY_SECTION_FINDINGS=0
    security_log_section_begin "JS_SKIMMER" "$_discover" "$_cleanup"

    while IFS= read -r _line; do
        [ -n "$_line" ] || continue
        security_scan_should_ignore_known_js_library_match "$_line" && continue
        _path="${_line%%:*}"
        [ -n "$_path" ] || continue
        _indicator="$(security_scan_indicator_for_match "$_line")"
        _class="$(security_scan_class_for_match "$_line")"
        security_finding_is_known "$_path" "$_indicator" "$_class" && continue
        WARP_SECURITY_SECTION_FINDINGS=$((WARP_SECURITY_SECTION_FINDINGS + 1))
        security_add_score 20
        security_record_finding "$_line" "skimmer"
    done < <(security_search_tree 'RTCPeerConnection|createDataChannel|new WebSocket|wss://|new Function\(event\.data\)' "$PROJECTPATH/app" "$PROJECTPATH/pub" | sed "s#^$PROJECTPATH/##")

    security_finish_section_empty_if_needed
}

security_scan_known_ioc() {
    local _discover='grep -RInE '\''md5\(\$_COOKIE\["d"\]\)|md5\(\$_COOKIE\['\''d'\''\]\)|new Function\(event\.data\)|preg_replace\s*\(.*/e|(^|[^[:alnum:]_])create_function\s*\(|hash_equals\(md5\(|\$_REQUEST\["password"\]'\'' app pub var generated'
    local _cleanup='mkdir -p var/quarantine && mv <suspicious-file> var/quarantine/'
    local _line=""
    local _family=""
    local _path=""
    local _indicator=""
    local _class=""

    WARP_SECURITY_SECTION_FINDINGS=0
    security_log_section_begin "KNOWN_IOC" "$_discover" "$_cleanup"

    while IFS= read -r _line; do
        [ -n "$_line" ] || continue
        security_scan_should_ignore_known_ioc_path "$_line" && continue
        _path="${_line%%:*}"
        [ -n "$_path" ] || continue
        _indicator="$(security_scan_indicator_for_match "$_line")"
        _class="$(security_scan_class_for_match "$_line")"
        security_finding_is_known "$_path" "$_indicator" "$_class" && continue
        _family="webshell"
        case "$_line" in
            *RTCPeerConnection*|*new\ Function*|*event.data*)
                _family="skimmer"
                security_add_score 25
                ;;
            *)
                security_add_score 25
                ;;
        esac
        WARP_SECURITY_SECTION_FINDINGS=$((WARP_SECURITY_SECTION_FINDINGS + 1))
        security_record_finding "$_line" "$_family"
    done < <(security_search_tree 'md5\(\$_COOKIE\["d"\]\)|md5\(\$_COOKIE\['"'"'d'"'"'\]\)|new Function\(event\.data\)|preg_replace\s*\(.*/e|(^|[^[:alnum:]_])create_function\s*\(|hash_equals\(md5\(|\$_REQUEST\["password"\]' "$PROJECTPATH/app" "$PROJECTPATH/pub" "$PROJECTPATH/var" "$PROJECTPATH/generated" | sed "s#^$PROJECTPATH/##")

    security_finish_section_empty_if_needed
}

security_scan_access_logs() {
    local _discover='grep -RInE "guest-carts/.*/items|customer/address_file/upload|estimate-shipping-methods|test-ambio|python-requests|Go-http-client" <access-log>'
    local _cleanup='# preserve evidence first; then investigate source IPs, requests and touched files'
    local _log_file=""
    local _line=""
    local _matched="false"

    WARP_SECURITY_SECTION_FINDINGS=0
    security_log_section_begin "ACCESS_LOG_IOC" "$_discover" "$_cleanup"

    while IFS= read -r _log_file; do
        [ -n "$_log_file" ] || continue
        _matched="true"
        security_log_write "source: ${_log_file#$PROJECTPATH/}"
        while IFS= read -r _line; do
            [ -n "$_line" ] || continue
            WARP_SECURITY_SECTION_FINDINGS=$((WARP_SECURITY_SECTION_FINDINGS + 1))
            case "$_line" in
                *guest-carts/*items*|*customer/address_file/upload*)
                    security_add_score 20
                    security_record_finding "  $_line" "polyshell"
                    ;;
                *estimate-shipping-methods*|*test-ambio*|*python-requests*|*Go-http-client*)
                    security_add_score 20
                    security_record_finding "  $_line" "cosmicsting"
                    ;;
                *)
                    security_add_score 12
                    security_record_finding "  $_line" "webshell"
                    ;;
            esac
        done < <(security_search_tree_i 'guest-carts/.*/items|customer/address_file/upload|estimate-shipping-methods|test-ambio|python-requests|Go-http-client' "$_log_file")
        security_log_write ""
    done < <(security_access_logs_list)

    if [ "$_matched" != "true" ]; then
        security_log_write "No readable access logs found."
    else
        security_finish_section_empty_if_needed
    fi
}

security_scan_host_persistence() {
    local _discover='crontab -l; find ~/.config/htop /dev/shm -maxdepth 2 -type f; ps auxww | awk ...'
    local _cleanup='crontab -e ; kill -9 <pid> ; mv <artifact> var/quarantine/'
    local _line=""
    local _path=""
    local _host_correlated=0

    WARP_SECURITY_SECTION_FINDINGS=0
    security_log_section_begin "HOST_PERSISTENCE" "$_discover" "$_cleanup"

    while IFS= read -r _line; do
        [ -n "$_line" ] || continue
        _host_correlated=1
        WARP_SECURITY_SECTION_FINDINGS=$((WARP_SECURITY_SECTION_FINDINGS + 1))
        security_add_score 25
        security_record_finding "crontab: $_line" "cosmicsting"
    done < <(crontab -l 2>/dev/null | grep -nEi 'defunct|base64|gsocket|LD_PRELOAD' 2>/dev/null)

    while IFS= read -r _path; do
        [ -n "$_path" ] || continue
        _host_correlated=1
        WARP_SECURITY_SECTION_FINDINGS=$((WARP_SECURITY_SECTION_FINDINGS + 1))
        security_add_score 25
        security_record_finding "artifact: ${_path#$HOME/}" "cosmicsting"
    done < <(find "$HOME/.config/htop" /dev/shm -maxdepth 2 -type f \( -name 'defunct' -o -name 'defunct.dat' -o -name 'php-shared' \) 2>/dev/null)

    while IFS= read -r _line; do
        [ -n "$_line" ] || continue
        case "$_line" in
            *gsocket*|*defunct*)
                WARP_SECURITY_SECTION_FINDINGS=$((WARP_SECURITY_SECTION_FINDINGS + 1))
                security_add_score 25
                security_record_finding "process: $_line" "cosmicsting"
                ;;
            *"[raid5wq]"*|*"[kswapd0]"*)
                if [ "$_host_correlated" -eq 1 ]; then
                    WARP_SECURITY_SECTION_FINDINGS=$((WARP_SECURITY_SECTION_FINDINGS + 1))
                    security_add_score 25
                    security_record_finding "process: $_line" "cosmicsting"
                fi
                ;;
        esac
    done < <(ps auxww 2>/dev/null | awk 'BEGIN{IGNORECASE=1} /(\[raid5wq\]|\[kswapd0\]|defunct|gsocket)/ && $0 !~ /awk/ {print}')

    security_finish_section_empty_if_needed
}

security_check_main() {
    local _log_file=""
    local _archive_log=""
    local _families_display=""
    local _severity=""
    local _status=""

    if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
        security_help_usage
        return 0
    fi

    _log_file="$(security_log_file)"
    mkdir -p "$PROJECTPATH/var/log"
    : > "$_log_file"

    security_known_metadata_bootstrap
    WARP_SECURITY_FINDINGS=0
    WARP_SECURITY_FAMILIES=""
    WARP_SECURITY_SECTION_FINDINGS=0
    WARP_SECURITY_SCORE=0
    WARP_SECURITY_RG_WARNED=0

    security_warn_missing_rg_once
    security_step_run "Checking pub drift..." security_scan_git_pub_drift || return 1
    security_step_run "Checking core pub entrypoints..." security_scan_core_pub_entrypoints || return 1
    security_step_run "Checking PHP in pub..." security_scan_php_in_pub || return 1
    security_step_run "Checking PHP markers in uploads..." security_scan_php_markers_in_pub || return 1
    security_step_run "Checking JS skimmer signals..." security_scan_js_skimmer || return 1
    security_step_run "Checking known IOC..." security_scan_known_ioc || return 1
    security_step_run "Checking access logs..." security_scan_access_logs || return 1
    security_step_run "Checking host persistence..." security_scan_host_persistence || return 1

    security_log_archive_rotate
    _archive_log="${WARP_SECURITY_ARCHIVE_LOG:-}"

    _families_display="$(echo "$WARP_SECURITY_FAMILIES" | xargs 2>/dev/null)"
    _severity="$(security_current_severity)"
    _status="$(security_level_status "$_severity")"

    warp_message_info "[SECURITY]"
    warp_message " severity: $(security_level_badge "$_severity")"
    warp_message " status: $_status"
    warp_message " score: $WARP_SECURITY_SCORE"
    if [ "$WARP_SECURITY_FINDINGS" -eq 0 ]; then
        warp_message " findings: none"
    else
        warp_message_warn " findings: $WARP_SECURITY_FINDINGS"
        if [ -n "$_families_display" ]; then
            warp_message " probable families: $_families_display"
            warp_message " toolkit: warp security toolkit --family ${_families_display%% *}"
        fi
    fi
    security_known_references_note
    warp_message " log: var/log/warp-security.log"
    [ -n "$_archive_log" ] && warp_message " archive: $_archive_log"
    warp_message ""
    return 0
}

security_main() {
    case "$1" in
        scan)
            shift
            security_scan_main "$@"
            ;;
        toolkit)
            shift
            security_toolkit_main "$@"
            ;;
        check)
            shift
            security_check_main "$@"
            ;;
        -h|--help|"")
            security_help_usage
            ;;
        *)
            security_help_usage
            return 1
            ;;
    esac
}
