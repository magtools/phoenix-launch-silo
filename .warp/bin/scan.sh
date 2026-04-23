#!/bin/bash

. "$PROJECTPATH/.warp/bin/scan_help.sh"

scan_command()
{
    case "$1" in
        -h|--help|"")
            scan_help_usage
            return 0
            ;;
        scraping|scrapping)
            shift
            scan_scraping_main "$@"
            return $?
            ;;
        *)
            warp_message_error "unknown scan: $1"
            scan_help_usage
            return 1
            ;;
    esac
}

scan_scraping_default_patterns()
{
    printf '%s\n' \
        "$PROJECTPATH/.warp/docker/volumes/nginx/logs/access.log" \
        "$PROJECTPATH/.warp/docker/volumes/nginx/logs/default-access.log" \
        "$PROJECTPATH/.warp/docker/volumes/nginx/logs/*access*.log" \
        "$PROJECTPATH/.warp/docker/volumes/nginx/logs/*access*.log.[1-9]" \
        "$PROJECTPATH/.warp/docker/volumes/nginx/logs/*access*.log.[1-9][0-9]" \
        "$PROJECTPATH/.warp/docker/volumes/nginx/logs/*access*.log*.gz" \
        "$PROJECTPATH/.warp/docker/volumes/php-fpm/logs/access.log" \
        "$PROJECTPATH/.warp/docker/volumes/php-fpm/logs/access.log.[1-9]" \
        "$PROJECTPATH/.warp/docker/volumes/php-fpm/logs/access.log.[1-9][0-9]" \
        "$PROJECTPATH/.warp/docker/volumes/php-fpm/logs/access.log*.gz"
}

scan_scraping_add_matches()
{
    local _pattern="$1"
    local _matched=()
    local _file=""

    shopt -s nullglob
    _matched=( $_pattern )
    shopt -u nullglob

    if [ ${#_matched[@]} -eq 0 ] && [ -f "$_pattern" ]; then
        _matched=( "$_pattern" )
    fi

    for _file in "${_matched[@]}"; do
        [ -f "$_file" ] || continue
        SCAN_SCRAPING_FILES+=("$_file")
    done
}

scan_scraping_resolve_files()
{
    local _pattern=""

    SCAN_SCRAPING_FILES=()

    if [ ${#SCAN_SCRAPING_PATTERNS[@]} -eq 0 ]; then
        while IFS= read -r _pattern; do
            scan_scraping_add_matches "$_pattern"
        done < <(scan_scraping_default_patterns)
    else
        for _pattern in "${SCAN_SCRAPING_PATTERNS[@]}"; do
            scan_scraping_add_matches "$_pattern"
        done
    fi
}

scan_scraping_file_size()
{
    local _file="$1"
    local _size

    _size=$(stat -c '%s' "$_file" 2>/dev/null)
    if [ -z "$_size" ]; then
        _size=$(stat -f '%z' "$_file" 2>/dev/null)
    fi

    case "$_size" in
        ''|*[!0-9]*) echo 0 ;;
        *) echo "$_size" ;;
    esac
}

scan_scraping_gzip_uncompressed_size()
{
    local _file="$1"
    local _size

    _size=$(gzip -l -- "$_file" 2>/dev/null | awk 'END { if ($2 ~ /^[0-9]+$/) print $2 }')

    case "$_size" in
        ''|*[!0-9]*) return 1 ;;
        *) echo "$_size" ;;
    esac
}

scan_scraping_input_size()
{
    local _file="$1"
    local _size=""

    case "$_file" in
        *.gz)
            _size=$(scan_scraping_gzip_uncompressed_size "$_file" 2>/dev/null)
            ;;
    esac

    if [ -z "$_size" ]; then
        _size=$(scan_scraping_file_size "$_file")
    fi

    echo "$_size"
}

scan_scraping_total_input_size()
{
    local _file=""
    local _size=0
    local _total=0

    for _file in "${SCAN_SCRAPING_FILES[@]}"; do
        _size=$(scan_scraping_input_size "$_file")
        _total=$((_total + _size))
    done

    echo "$_total"
}

scan_scraping_human_bytes()
{
    local _bytes="$1"

    case "$_bytes" in
        ''|*[!0-9]*) _bytes=0 ;;
    esac

    if [ "$_bytes" -ge 1073741824 ]; then
        printf '%s GiB' "$((_bytes / 1073741824))"
    elif [ "$_bytes" -ge 1048576 ]; then
        printf '%s MiB' "$((_bytes / 1048576))"
    elif [ "$_bytes" -ge 1024 ]; then
        printf '%s KiB' "$((_bytes / 1024))"
    else
        printf '%s B' "$_bytes"
    fi
}

scan_scraping_stream_logs()
{
    local _file=""

    for _file in "${SCAN_SCRAPING_FILES[@]}"; do
        if [ ! -r "$_file" ]; then
            warp_message_warn "log not readable: $_file" >&2
            continue
        fi

        case "$_file" in
            *.gz)
                gzip -cd -- "$_file"
                ;;
            *)
                cat -- "$_file"
                ;;
        esac
    done
}

scan_scraping_progress_enabled()
{
    [ "${WARP_SCAN_SCRAPING_PROGRESS:-1}" = "1" ] || return 1
    [ -t 2 ] || return 1

    return 0
}

scan_scraping_spinner_wait()
{
    local _pid="$1"
    local _label="$2"
    local _spin='|/-\'
    local _progress_file="${WARP_SCAN_SCRAPING_PROGRESS_FILE:-}"
    local _total_bytes="${WARP_SCAN_SCRAPING_TOTAL_BYTES:-0}"
    local _bytes=0
    local _lines=0
    local _parsed=0
    local _stage=""
    local _percent=0
    local _detail=""
    local _i=0

    scan_scraping_progress_enabled || return 0

    while kill -0 "$_pid" 2>/dev/null; do
        _i=$(((_i + 1) % 4))
        _detail="$_label"
        if [ -n "$_progress_file" ] && [ -r "$_progress_file" ]; then
            IFS=$'\t' read -r _bytes _lines _parsed _stage < "$_progress_file"
            case "$_bytes" in
                ''|*[!0-9]*) _bytes=0 ;;
            esac
            case "$_lines" in
                ''|*[!0-9]*) _lines=0 ;;
            esac
            case "$_parsed" in
                ''|*[!0-9]*) _parsed=0 ;;
            esac
            [ -n "$_stage" ] || _stage="ingesting"
            if [ "$_total_bytes" -gt 0 ]; then
                _percent=$((_bytes * 100 / _total_bytes))
                [ "$_percent" -gt 100 ] && _percent=100
                _detail="$_label: ${_stage}; $(scan_scraping_human_bytes "$_bytes") / $(scan_scraping_human_bytes "$_total_bytes") (${_percent}%, lines=${_lines}, parsed=${_parsed})"
            else
                _detail="$_label: ${_stage}; $(scan_scraping_human_bytes "$_bytes") ingested (lines=${_lines}, parsed=${_parsed})"
            fi
        fi
        printf "\r\033[K[%c] %s" "${_spin:$_i:1}" "$_detail" >&2
        sleep 0.1
    done

    printf "\r\033[K" >&2
}

scan_scraping_progress_ok()
{
    local _label="$1"
    local _progress_file="${WARP_SCAN_SCRAPING_PROGRESS_FILE:-}"
    local _total_bytes="${WARP_SCAN_SCRAPING_TOTAL_BYTES:-0}"
    local _bytes=0
    local _lines=0
    local _parsed=0
    local _stage=""

    scan_scraping_progress_enabled || return 0
    if [ -n "$_progress_file" ] && [ -r "$_progress_file" ]; then
        IFS=$'\t' read -r _bytes _lines _parsed _stage < "$_progress_file"
        case "$_bytes" in
            ''|*[!0-9]*) _bytes=0 ;;
        esac
        case "$_lines" in
            ''|*[!0-9]*) _lines=0 ;;
        esac
        case "$_parsed" in
            ''|*[!0-9]*) _parsed=0 ;;
        esac
        if [ "$_total_bytes" -gt 0 ]; then
            _label="$_label ($(scan_scraping_human_bytes "$_bytes") / $(scan_scraping_human_bytes "$_total_bytes"), lines=${_lines}, parsed=${_parsed})"
        else
            _label="$_label ($(scan_scraping_human_bytes "$_bytes") ingested, lines=${_lines}, parsed=${_parsed})"
        fi
    fi
    printf "[ok] %s\n" "$_label" >&2
}

scan_scraping_progress_error()
{
    local _label="$1"

    scan_scraping_progress_enabled || return 0
    printf "[error] %s\n" "$_label" >&2
}

scan_scraping_progress_stage()
{
    local _stage="$1"
    local _progress_file="${WARP_SCAN_SCRAPING_PROGRESS_FILE:-}"
    local _bytes=0
    local _lines=0
    local _parsed=0
    local _old_stage=""

    [ -n "$_progress_file" ] || return 0

    if [ -r "$_progress_file" ]; then
        IFS=$'\t' read -r _bytes _lines _parsed _old_stage < "$_progress_file"
    fi

    case "$_bytes" in
        ''|*[!0-9]*) _bytes=0 ;;
    esac
    case "$_lines" in
        ''|*[!0-9]*) _lines=0 ;;
    esac
    case "$_parsed" in
        ''|*[!0-9]*) _parsed=0 ;;
    esac

    printf '%s\t%s\t%s\t%s\n' "$_bytes" "$_lines" "$_parsed" "$_stage" > "$_progress_file"
}

scan_scraping_analyze_with_spinner()
{
    local _summary_file="$1"
    local _min_score="$2"
    local _request_time_field="$3"
    local _since_epoch="$4"
    local _window_seconds="$5"
    local _page_gap="$6"
    local _pid
    local _status

    scan_scraping_analyze "$_summary_file" "$_min_score" "$_request_time_field" "$_since_epoch" "$_window_seconds" "$_page_gap" &
    _pid=$!
    scan_scraping_spinner_wait "$_pid" "analyzing ${#SCAN_SCRAPING_FILES[@]} log file(s)"
    wait "$_pid"
    _status=$?

    if [ $_status -eq 0 ]; then
        scan_scraping_progress_ok "analyzed scraping signals"
    else
        scan_scraping_progress_error "analyze scraping signals"
    fi

    return $_status
}

scan_scraping_render_with_spinner()
{
    local _summary_file="$1"
    local _top_n="$2"
    local _min_score="$3"
    local _json="$4"
    local _tmp_output="$5"
    local _pid
    local _status

    scan_scraping_progress_stage "rendering report"

    if [ "$_json" -eq 1 ]; then
        scan_scraping_print_json "$_summary_file" "$_top_n" "$_min_score" > "$_tmp_output" &
    else
        scan_scraping_print_human "$_summary_file" "$_top_n" "$_min_score" > "$_tmp_output" &
    fi

    _pid=$!
    scan_scraping_spinner_wait "$_pid" "rendering scraping report"
    wait "$_pid"
    _status=$?

    if [ $_status -eq 0 ]; then
        scan_scraping_progress_ok "rendered scraping report"
    else
        scan_scraping_progress_error "render scraping report"
    fi

    return $_status
}

scan_scraping_analyze()
{
    local _summary_file="$1"
    local _min_score="$2"
    local _request_time_field="$3"
    local _since_epoch="$4"
    local _window_seconds="$5"
    local _page_gap="$6"

    scan_scraping_stream_logs | awk -v min_score="$_min_score" -v request_time_field="$_request_time_field" -v since_epoch="$_since_epoch" -v window_seconds="$_window_seconds" -v page_gap="$_page_gap" -v progress_file="${WARP_SCAN_SCRAPING_PROGRESS_FILE:-}" '
function write_progress(force) {
    if (progress_file == "") {
        return
    }

    if (!force && (ingested_bytes - last_progress_bytes) < progress_interval) {
        return
    }

    print ingested_bytes "\t" NR "\t" parsed "\t" progress_stage > progress_file
    close(progress_file)
    last_progress_bytes = ingested_bytes
}

function ua_family(ua, lower) {
    lower = tolower(ua)

    if (lower ~ /(axios|node-fetch|python-httpx|python-requests|curl\/|wget\/|libwww-perl|go-http-client|java\/|okhttp|aiohttp|scrapy|httpclient)/) {
        return "http-lib"
    }

    if (lower ~ /(googlebot|bingbot|google-inspectiontool|adsbot-google|apis-google|mediapartners-google)/) {
        return "search-bot-claimed"
    }

    if (lower ~ /(facebookexternalhit|meta-external|meta-webindexer)/) {
        return "meta-bot-claimed"
    }

    if (lower ~ /(bot|crawler|crawl|spider|slurp|archive)/) {
        return "other-bot"
    }

    if (lower ~ /(chrome|safari|firefox|edg|opr\/|opera|mozilla\/5\.0)/) {
        return "browser"
    }

    if (lower == "" || lower == "-") {
        return "unknown"
    }

    return "other"
}

function normalize_target(target) {
    if (target ~ /^https?:\/\//) {
        sub(/^https?:\/\/[^\/]+/, "", target)
    }

    if (target == "") {
        return "/"
    }

    return target
}

function is_interesting_path(path) {
    if (path ~ /^\/(static|media)\//) {
        return 0
    }

    if (path ~ /^\/rest(\/|$)/) {
        return 0
    }

    if (path ~ /^\/healthcheck66\.php$/ || path ~ /^\/health_check\.php$/) {
        return 0
    }

    if (path ~ /\.(css|js|mjs|png|jpe?g|gif|svg|ico|webp|avif|woff2?|ttf|eot|map|txt|xml)$/) {
        return 0
    }

    return 1
}

function query_param(query, key, chunks, i, pair, count) {
    if (query == "") {
        return ""
    }

    count = split(query, chunks, "&")
    for (i = 1; i <= count; i++) {
        split(chunks[i], pair, "=")
        if (pair[1] == key) {
            return pair[2]
        }
    }

    return ""
}

function normalize_query(query, chunks, count, i, j, tmp, normalized) {
    if (query == "") {
        return ""
    }

    count = split(query, chunks, "&")
    for (i = 1; i <= count; i++) {
        chunks[i] = tolower(chunks[i])
    }

    for (i = 1; i <= count; i++) {
        for (j = i + 1; j <= count; j++) {
            if (chunks[j] < chunks[i]) {
                tmp = chunks[i]
                chunks[i] = chunks[j]
                chunks[j] = tmp
            }
        }
    }

    normalized = ""
    for (i = 1; i <= count; i++) {
        if (chunks[i] == "") {
            continue
        }
        normalized = (normalized == "") ? chunks[i] : normalized "&" chunks[i]
    }

    return normalized
}

function score_client(family, count, unique_queries, max_p, price_count, total_time, avg_time, blank_ref_count, error_count, unique_pages, page_span, page_run, score) {
    score = 0

    if (family == "http-lib") {
        score += 3
    } else if (family == "other-bot") {
        score += 1
    }

    if (count >= 50) {
        score += 3
    } else if (count >= 20) {
        score += 2
    } else if (count >= 10) {
        score += 1
    }

    if (unique_queries >= 20) {
        score += 3
    } else if (unique_queries >= 10) {
        score += 2
    } else if (unique_queries >= 5) {
        score += 1
    }

    if (max_p >= 80) {
        score += 3
    } else if (max_p >= 30) {
        score += 2
    } else if (max_p >= 10) {
        score += 1
    }

    if (page_run >= 20) {
        score += 4
    } else if (page_run >= 10) {
        score += 3
    } else if (page_run >= 5) {
        score += 2
    } else if (page_run >= 3) {
        score += 1
    }

    if (unique_pages >= 20) {
        score += 2
    } else if (unique_pages >= 10) {
        score += 1
    }

    if (page_span >= 50) {
        score += 2
    } else if (page_span >= 20) {
        score += 1
    }

    if (price_count >= 10) {
        score += 3
    } else if (price_count >= 3) {
        score += 2
    } else if (price_count > 0) {
        score += 1
    }

    if (total_time >= 20) {
        score += 2
    } else if (avg_time >= 1) {
        score += 1
    }

    if (blank_ref_count == count) {
        score += 1
    }

    if (error_count >= 10) {
        score += 1
    }

    if (family == "search-bot-claimed" || family == "meta-bot-claimed") {
        score -= 1
    }

    return score
}

function request_time_value(status, candidate) {
    if (request_time_field ~ /^[0-9]+$/ && request_time_field > 0 && request_time_field <= NF) {
        candidate = $request_time_field
        return (candidate ~ /^[0-9]+(\.[0-9]+)?$/) ? candidate + 0 : 0
    }

    candidate = $NF
    if (candidate ~ /^[0-9]+(\.[0-9]+)?$/ && candidate != status) {
        request_time_detected = 1
        return candidate + 0
    }

    return 0
}

function month_number(mon, lower) {
    lower = tolower(mon)
    if (lower == "jan") return 1
    if (lower == "feb") return 2
    if (lower == "mar") return 3
    if (lower == "apr") return 4
    if (lower == "may") return 5
    if (lower == "jun") return 6
    if (lower == "jul") return 7
    if (lower == "aug") return 8
    if (lower == "sep") return 9
    if (lower == "oct") return 10
    if (lower == "nov") return 11
    if (lower == "dec") return 12
    return 0
}

function log_epoch(line, date_text, mon, mon_num) {
    if (!match(line, /[0-9][0-9]\/[A-Za-z][A-Za-z][A-Za-z]\/[0-9][0-9][0-9][0-9]:[0-9][0-9]:[0-9][0-9]:[0-9][0-9]/)) {
        return 0
    }

    date_text = substr(line, RSTART, RLENGTH)
    mon = substr(date_text, 4, 3)
    mon_num = month_number(mon)
    if (mon_num == 0) {
        return 0
    }

    return mktime(sprintf("%04d %02d %02d %02d %02d %02d", substr(date_text, 8, 4), mon_num, substr(date_text, 1, 2), substr(date_text, 13, 2), substr(date_text, 16, 2), substr(date_text, 19, 2)))
}

function window_label(epoch, start_epoch) {
    if (window_seconds <= 0 || epoch <= 0) {
        return "-"
    }

    start_epoch = int(epoch / window_seconds) * window_seconds
    return strftime("%Y-%m-%dT%H:%M:%S", start_epoch)
}

function compute_page_metrics(client_key,    page_count, pages, i, j, tmp, run, best, span) {
    delete pages
    page_count = split(client_pages[client_key], pages, ",")
    if (page_count == 1 && pages[1] == "") {
        page_count = 0
    }

    if (page_count == 0) {
        client_unique_pages[client_key] = 0
        client_page_span[client_key] = 0
        client_page_run[client_key] = 0
        return
    }

    for (i = 1; i <= page_count; i++) {
        for (j = i + 1; j <= page_count; j++) {
            if (pages[j] < pages[i]) {
                tmp = pages[i]
                pages[i] = pages[j]
                pages[j] = tmp
            }
        }
    }

    run = 1
    best = 1
    for (i = 2; i <= page_count; i++) {
        if ((pages[i] - pages[i - 1]) <= page_gap) {
            run++
        } else {
            run = 1
        }

        if (run > best) {
            best = run
        }
    }

    span = pages[page_count] - pages[1]
    client_unique_pages[client_key] = page_count
    client_page_span[client_key] = span
    client_page_run[client_key] = best
}

BEGIN {
    quote = sprintf("%c", 34)
    parsed = 0
    skipped = 0
    skipped_since = 0
    skipped_time = 0
    request_time_detected = 0
    ingested_bytes = 0
    last_progress_bytes = 0
    progress_interval = 1048576
    progress_stage = "ingesting"
    write_progress(1)
}

{
    line = $0
    ingested_bytes += length(line) + 1
    write_progress(0)
    epoch = 0

    if (since_epoch > 0 || window_seconds > 0) {
        epoch = log_epoch(line)
        if (epoch <= 0) {
            skipped_time++
            next
        }

        if (since_epoch > 0 && epoch < since_epoch) {
            skipped_since++
            next
        }
    }

    n = split(line, parts, quote)
    if (n < 3) {
        skipped++
        next
    }

    request = parts[2]
    referer = (n >= 5) ? parts[4] : "-"
    ua = (n >= 7) ? parts[6] : "-"
    status_field = parts[3]

    split(parts[1], prefix, " ")
    ip = prefix[1]
    if (ip == "") {
        skipped++
        next
    }

    sub(/^[[:space:]]+/, "", status_field)
    split(status_field, status_bits, " ")
    status = status_bits[1]

    split(request, request_bits, " ")
    target = normalize_target(request_bits[2])
    if (target == "") {
        skipped++
        next
    }

    query = ""
    normalized_query = ""
    path = target
    query_pos = index(target, "?")
    if (query_pos > 0) {
        path = substr(target, 1, query_pos - 1)
        query = substr(target, query_pos + 1)
        normalized_query = normalize_query(query)
    }

    if (!is_interesting_path(path)) {
        skipped++
        next
    }

    parsed++
    order_value = tolower(query_param(query, "product_list_order"))
    if (order_value == "") {
        order_value = tolower(query_param(query, "order"))
    }

    p_value = query_param(query, "p") + 0
    is_price_sort = (order_value == "price") ? 1 : 0
    family = ua_family(ua)
    request_time = request_time_value(status)
    blank_referer = (referer == "" || referer == "-") ? 1 : 0
    window = window_label(epoch)

    client_key = window "|" ip "|" family "|" path
    client_family[client_key] = family
    client_count[client_key]++
    client_time[client_key] += request_time
    client_blank_ref[client_key] += blank_referer
    if (is_price_sort) {
        client_price[client_key]++
    }
    if (p_value > client_max_p[client_key]) {
        client_max_p[client_key] = p_value
    }
    if (p_value > 0) {
        client_page_key = client_key SUBSEP p_value
        if (!(client_page_key in seen_client_page)) {
            seen_client_page[client_page_key] = 1
            client_pages[client_key] = (client_pages[client_key] == "") ? p_value : client_pages[client_key] "," p_value
        }
    }
    if (status ~ /^(4|5)/) {
        client_errors[client_key]++
    }
    if (normalized_query != "") {
        client_query_key = client_key SUBSEP normalized_query
        if (!(client_query_key in seen_client_query)) {
            seen_client_query[client_query_key] = 1
            client_unique_queries[client_key]++
        }
    }

    path_count[path]++
    path_time[path] += request_time
    if (is_price_sort) {
        path_price[path]++
    }
    if (p_value > path_max_p[path]) {
        path_max_p[path] = p_value
    }
    path_ip_key = path SUBSEP ip
    if (!(path_ip_key in seen_path_ip)) {
        seen_path_ip[path_ip_key] = 1
        path_unique_ips[path]++
    }
    if (normalized_query != "") {
        path_query_key = path SUBSEP normalized_query
        if (!(path_query_key in seen_path_query)) {
            seen_path_query[path_query_key] = 1
            path_unique_queries[path]++
        }
    }

    signature_query = (normalized_query == "") ? "-" : normalized_query
    signature_key = path "|" signature_query "|" family
    signature_count[signature_key]++
    signature_time[signature_key] += request_time
    if (is_price_sort) {
        signature_price[signature_key]++
    }
    if (p_value > signature_max_p[signature_key]) {
        signature_max_p[signature_key] = p_value
    }
    signature_ip_key = signature_key SUBSEP ip
    if (!(signature_ip_key in seen_signature_ip)) {
        seen_signature_ip[signature_ip_key] = 1
        signature_unique_ips[signature_key]++
    }

    ua_count[family]++
    ua_ip_key = family SUBSEP ip
    if (!(ua_ip_key in seen_ua_ip)) {
        seen_ua_ip[ua_ip_key] = 1
        ua_unique_ips[family]++
    }
}

END {
    progress_stage = "finalizing client metrics"
    write_progress(1)

    print "METRIC\tparsed_lines\t" parsed
    print "METRIC\tskipped_lines\t" skipped
    print "METRIC\tskipped_since\t" skipped_since
    print "METRIC\tskipped_time\t" skipped_time
    print "METRIC\trequest_time\t" (request_time_detected ? "detected" : "unknown")
    print "METRIC\tsince_epoch\t" since_epoch
    print "METRIC\twindow_seconds\t" window_seconds
    print "METRIC\tpage_gap\t" page_gap

    client_done = 0
    for (client_key in client_count) {
        client_done++
        if ((client_done % 500) == 0) {
            progress_stage = "finalizing client metrics " client_done
            write_progress(1)
        }
        compute_page_metrics(client_key)
        score = score_client(client_family[client_key], client_count[client_key], client_unique_queries[client_key] + 0, client_max_p[client_key] + 0, client_price[client_key] + 0, client_time[client_key] + 0, client_time[client_key] / client_count[client_key], client_blank_ref[client_key] + 0, client_errors[client_key] + 0, client_unique_pages[client_key] + 0, client_page_span[client_key] + 0, client_page_run[client_key] + 0)

        if (score >= min_score) {
            split(client_key, key_parts, "|")
            print "CLIENT\t" score "\t" client_count[client_key] "\t" (client_unique_queries[client_key] + 0) "\t" (client_max_p[client_key] + 0) "\t" (client_price[client_key] + 0) "\t" sprintf("%.3f", client_time[client_key]) "\t" sprintf("%.3f", client_time[client_key] / client_count[client_key]) "\t" (client_errors[client_key] + 0) "\t" key_parts[1] "\t" (client_unique_pages[client_key] + 0) "\t" (client_page_span[client_key] + 0) "\t" (client_page_run[client_key] + 0) "\t" key_parts[2] "|" key_parts[3] "|" key_parts[4]
        }
    }

    progress_stage = "writing path summaries"
    write_progress(1)
    for (path in path_count) {
        print "PATH\t" path_count[path] "\t" (path_unique_ips[path] + 0) "\t" (path_unique_queries[path] + 0) "\t" (path_max_p[path] + 0) "\t" (path_price[path] + 0) "\t" sprintf("%.3f", path_time[path]) "\t" sprintf("%.3f", path_time[path] / path_count[path]) "\t" path
    }

    progress_stage = "writing signature summaries"
    write_progress(1)
    for (signature_key in signature_count) {
        split(signature_key, signature_parts, "|")
        print "SIGNATURE\t" signature_count[signature_key] "\t" (signature_unique_ips[signature_key] + 0) "\t" (signature_max_p[signature_key] + 0) "\t" (signature_price[signature_key] + 0) "\t" sprintf("%.3f", signature_time[signature_key]) "\t" sprintf("%.3f", signature_time[signature_key] / signature_count[signature_key]) "\t" signature_parts[1] "\t" signature_parts[2] "\t" signature_parts[3]
    }

    progress_stage = "writing user-agent summaries"
    write_progress(1)
    for (family in ua_count) {
        print "UA\t" ua_count[family] "\t" (ua_unique_ips[family] + 0) "\t" family
    }

    progress_stage = "done"
    write_progress(1)
}
' > "$_summary_file"
}

scan_scraping_metric()
{
    local _summary_file="$1"
    local _name="$2"

    awk -F'\t' -v name="$_name" '$1 == "METRIC" && $2 == name { print $3; exit }' "$_summary_file"
}

scan_scraping_duration_to_seconds()
{
    local _value="$1"
    local _number
    local _unit

    if [[ ! "$_value" =~ ^([0-9]+)([smhd]?)$ ]]; then
        return 1
    fi

    _number="${BASH_REMATCH[1]}"
    _unit="${BASH_REMATCH[2]:-s}"

    case "$_unit" in
        s|"") echo "$_number" ;;
        m) echo $((_number * 60)) ;;
        h) echo $((_number * 3600)) ;;
        d) echo $((_number * 86400)) ;;
        *) return 1 ;;
    esac
}

scan_scraping_since_to_epoch()
{
    local _value="$1"
    local _duration_seconds

    _duration_seconds=$(scan_scraping_duration_to_seconds "$_value" 2>/dev/null)
    if [ -n "$_duration_seconds" ]; then
        echo "$(($(date +%s) - _duration_seconds))"
        return 0
    fi

    date -d "$_value" +%s 2>/dev/null
}

scan_scraping_print_human()
{
    local _summary_file="$1"
    local _top_n="$2"
    local _min_score="$3"
    local _parsed
    local _skipped
    local _skipped_since
    local _skipped_time
    local _request_time
    local _since_epoch
    local _window_seconds
    local _page_gap
    local _rows

    _parsed=$(scan_scraping_metric "$_summary_file" "parsed_lines")
    _skipped=$(scan_scraping_metric "$_summary_file" "skipped_lines")
    _skipped_since=$(scan_scraping_metric "$_summary_file" "skipped_since")
    _skipped_time=$(scan_scraping_metric "$_summary_file" "skipped_time")
    _request_time=$(scan_scraping_metric "$_summary_file" "request_time")
    _since_epoch=$(scan_scraping_metric "$_summary_file" "since_epoch")
    _window_seconds=$(scan_scraping_metric "$_summary_file" "window_seconds")
    _page_gap=$(scan_scraping_metric "$_summary_file" "page_gap")

    echo "Files scanned:"
    printf '  - %s\n' "${SCAN_SCRAPING_FILES[@]}"

    echo
    echo "Parser:"
    echo "  parsed_lines=${_parsed:-0} skipped_lines=${_skipped:-0} skipped_since=${_skipped_since:-0} skipped_time=${_skipped_time:-0} request_time=${_request_time:-unknown}"
    echo "  since_epoch=${_since_epoch:-0} window_seconds=${_window_seconds:-0} page_gap=${_page_gap:-4}"

    echo
    echo "Suspicious clients (score >= $_min_score)"
    echo "score count unique_q max_p price_sort pages span run sum_rt avg_rt errors window ip|ua_family|path"
    _rows=$(grep -F $'CLIENT\t' "$_summary_file" | sort -t $'\t' -k2,2nr -k3,3nr -k7,7nr | awk -F'\t' -v top_n="$_top_n" 'NR <= top_n {printf "%-5s %-5s %-8s %-5s %-10s %-5s %-5s %-3s %-8s %-8s %-6s %-19s %s\n", $2, $3, $4, $5, $6, $11, $12, $13, $7, $8, $9, $10, $14}')
    [ -n "$_rows" ] && printf '%s\n' "$_rows" || echo "(No rows)"

    echo
    echo "Hot paths"
    echo "count unique_ips unique_q max_p price_sort sum_rt avg_rt path"
    _rows=$(grep -F $'PATH\t' "$_summary_file" | sort -t $'\t' -k2,2nr -k7,7nr | awk -F'\t' -v top_n="$_top_n" 'NR <= top_n {printf "%-5s %-10s %-8s %-5s %-10s %-8s %-8s %s\n", $2, $3, $4, $5, $6, $7, $8, $9}')
    [ -n "$_rows" ] && printf '%s\n' "$_rows" || echo "(No rows)"

    echo
    echo "Signatures"
    echo "count unique_ips max_p price_sort sum_rt avg_rt ua_family path query"
    _rows=$(grep -F $'SIGNATURE\t' "$_summary_file" | sort -t $'\t' -k2,2nr -k6,6nr | awk -F'\t' -v top_n="$_top_n" 'NR <= top_n {printf "%-5s %-10s %-5s %-10s %-8s %-8s %-10s %s %s\n", $2, $3, $4, $5, $6, $7, $10, $8, $9}')
    [ -n "$_rows" ] && printf '%s\n' "$_rows" || echo "(No rows)"

    echo
    echo "User-agent families"
    echo "count unique_ips family"
    _rows=$(grep -F $'UA\t' "$_summary_file" | sort -t $'\t' -k2,2nr | awk -F'\t' -v top_n="$_top_n" 'NR <= top_n {printf "%-5s %-10s %s\n", $2, $3, $4}')
    [ -n "$_rows" ] && printf '%s\n' "$_rows" || echo "(No rows)"

    echo
    echo "Notes:"
    echo "  - Bot user-agents are claimed, not DNS-verified in this run."
    echo "  - Scores are heuristics for investigation, not automatic blocking decisions."
}

scan_scraping_json_string()
{
    printf '%s' "$1" | awk '
    {
        gsub(/\\/,"\\\\")
        gsub(/"/,"\\\"")
        gsub(/\t/,"\\t")
        gsub(/\r/,"\\r")
        gsub(/\n/,"\\n")
        printf "%s", $0
    }'
}

scan_scraping_print_json()
{
    local _summary_file="$1"
    local _top_n="$2"
    local _min_score="$3"
    local _parsed
    local _skipped
    local _skipped_since
    local _skipped_time
    local _request_time
    local _since_epoch
    local _window_seconds
    local _page_gap
    local _file
    local _first=1

    _parsed=$(scan_scraping_metric "$_summary_file" "parsed_lines")
    _skipped=$(scan_scraping_metric "$_summary_file" "skipped_lines")
    _skipped_since=$(scan_scraping_metric "$_summary_file" "skipped_since")
    _skipped_time=$(scan_scraping_metric "$_summary_file" "skipped_time")
    _request_time=$(scan_scraping_metric "$_summary_file" "request_time")
    _since_epoch=$(scan_scraping_metric "$_summary_file" "since_epoch")
    _window_seconds=$(scan_scraping_metric "$_summary_file" "window_seconds")
    _page_gap=$(scan_scraping_metric "$_summary_file" "page_gap")

    printf '{\n'
    printf '  "files": ['
    for _file in "${SCAN_SCRAPING_FILES[@]}"; do
        [ $_first -eq 0 ] && printf ', '
        printf '"%s"' "$(scan_scraping_json_string "$_file")"
        _first=0
    done
    printf '],\n'
    printf '  "parser": {"parsed_lines": %s, "skipped_lines": %s, "skipped_since": %s, "skipped_time": %s, "request_time": "%s", "since_epoch": %s, "window_seconds": %s, "page_gap": %s},\n' "${_parsed:-0}" "${_skipped:-0}" "${_skipped_since:-0}" "${_skipped_time:-0}" "$(scan_scraping_json_string "${_request_time:-unknown}")" "${_since_epoch:-0}" "${_window_seconds:-0}" "${_page_gap:-4}"

    awk -F'\t' -v top_n="$_top_n" -v min_score="$_min_score" '
    function esc(s) {
        gsub(/\\/,"\\\\",s)
        gsub(/"/,"\\\"",s)
        gsub(/\t/,"\\t",s)
        return s
    }
    BEGIN {
        print "  \"clients\": ["
    }
    $1 == "CLIENT" {
        client_count++
        if (client_count <= top_n) {
            row[++rows] = $0
        }
    }
    END {
        for (i = 1; i <= rows; i++) {
            split(row[i], f, "\t")
            split(f[14], key, "|")
            printf "%s    {\"score\": %s, \"count\": %s, \"unique_queries\": %s, \"max_p\": %s, \"price_sort\": %s, \"unique_pages\": %s, \"page_span\": %s, \"page_run\": %s, \"sum_request_time\": %s, \"avg_request_time\": %s, \"errors\": %s, \"window\": \"%s\", \"ip\": \"%s\", \"ua_family\": \"%s\", \"path\": \"%s\"}", (i > 1 ? ",\n" : ""), f[2], f[3], f[4], f[5], f[6], f[11], f[12], f[13], f[7], f[8], f[9], esc(f[10]), esc(key[1]), esc(key[2]), esc(key[3])
        }
        print ""
        print "  ],"
    }' < <(grep -F $'CLIENT\t' "$_summary_file" | sort -t $'\t' -k2,2nr -k3,3nr -k7,7nr)

    awk -F'\t' -v top_n="$_top_n" '
    function esc(s) {
        gsub(/\\/,"\\\\",s)
        gsub(/"/,"\\\"",s)
        gsub(/\t/,"\\t",s)
        return s
    }
    BEGIN {
        print "  \"paths\": ["
    }
    $1 == "PATH" {
        path_count++
        if (path_count <= top_n) {
            printf "%s    {\"count\": %s, \"unique_ips\": %s, \"unique_queries\": %s, \"max_p\": %s, \"price_sort\": %s, \"sum_request_time\": %s, \"avg_request_time\": %s, \"path\": \"%s\"}", (path_count > 1 ? ",\n" : ""), $2, $3, $4, $5, $6, $7, $8, esc($9)
        }
    }
    END {
        print ""
        print "  ],"
    }' < <(grep -F $'PATH\t' "$_summary_file" | sort -t $'\t' -k2,2nr -k7,7nr)

    awk -F'\t' -v top_n="$_top_n" '
    function esc(s) {
        gsub(/\\/,"\\\\",s)
        gsub(/"/,"\\\"",s)
        gsub(/\t/,"\\t",s)
        return s
    }
    BEGIN {
        print "  \"signatures\": ["
    }
    $1 == "SIGNATURE" {
        signature_count++
        if (signature_count <= top_n) {
            printf "%s    {\"count\": %s, \"unique_ips\": %s, \"max_p\": %s, \"price_sort\": %s, \"sum_request_time\": %s, \"avg_request_time\": %s, \"path\": \"%s\", \"query\": \"%s\", \"ua_family\": \"%s\"}", (signature_count > 1 ? ",\n" : ""), $2, $3, $4, $5, $6, $7, esc($8), esc($9), esc($10)
        }
    }
    END {
        print ""
        print "  ],"
    }' < <(grep -F $'SIGNATURE\t' "$_summary_file" | sort -t $'\t' -k2,2nr -k6,6nr)

    awk -F'\t' -v top_n="$_top_n" '
    function esc(s) {
        gsub(/\\/,"\\\\",s)
        gsub(/"/,"\\\"",s)
        gsub(/\t/,"\\t",s)
        return s
    }
    BEGIN {
        print "  \"user_agent_families\": ["
    }
    $1 == "UA" {
        ua_count++
        if (ua_count <= top_n) {
            printf "%s    {\"count\": %s, \"unique_ips\": %s, \"family\": \"%s\"}", (ua_count > 1 ? ",\n" : ""), $2, $3, esc($4)
        }
    }
    END {
        print ""
        print "  ],"
    }' < <(grep -F $'UA\t' "$_summary_file" | sort -t $'\t' -k2,2nr)

    printf '  "notes": ["Bot user-agents are claimed, not DNS-verified in this run.", "Scores are heuristics for investigation, not automatic blocking decisions."]\n'
    printf '}\n'
}

scan_scraping_write_output()
{
    local _output_file="$1"
    local _tmp_output="$2"
    local _output_dir

    if [ -z "$_output_file" ]; then
        cat "$_tmp_output"
        return 0
    fi

    _output_dir=$(dirname "$_output_file")
    if [ "$_output_dir" != "." ]; then
        mkdir -p "$_output_dir" || {
            warp_message_error "could not create output directory: $_output_dir"
            return 1
        }
    fi

    cp "$_tmp_output" "$_output_file" || {
        warp_message_error "could not write output file: $_output_file"
        return 1
    }

    warp_message_ok "scan report written: $_output_file"
}

scan_scraping_auto_output_file()
{
    local _output_dir="$1"
    local _json="$2"
    local _extension="txt"
    local _timestamp

    [ "$_json" -eq 1 ] && _extension="json"
    _timestamp=$(date +%Y%m%d-%H%M%S)
    printf '%s/warp-scan-scraping-%s.%s\n' "$_output_dir" "$_timestamp" "$_extension"
}

scan_scraping_main()
{
    local _top_n=25
    local _min_score=4
    local _output_file=""
    local _output_dir="$PROJECTPATH/var/log"
    local _save=0
    local _json=0
    local _format="auto"
    local _request_time_field=""
    local _since=""
    local _since_epoch=0
    local _window=""
    local _window_seconds=0
    local _page_gap=4
    local _progress=1
    local _progress_file=""
    local _total_bytes=0
    local _summary_file
    local _tmp_output
    local _status=0

    SCAN_SCRAPING_PATTERNS=()

    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help)
                scan_scraping_help_usage
                return 0
                ;;
            -n|--top)
                shift
                [ $# -gt 0 ] || { warp_message_error "--top requires a value"; return 2; }
                _top_n="$1"
                ;;
            -s|--min-score)
                shift
                [ $# -gt 0 ] || { warp_message_error "--min-score requires a value"; return 2; }
                _min_score="$1"
                ;;
            --log)
                shift
                [ $# -gt 0 ] || { warp_message_error "--log requires a value"; return 2; }
                SCAN_SCRAPING_PATTERNS+=("$1")
                ;;
            --path)
                shift
                [ $# -gt 0 ] || { warp_message_error "--path requires a value"; return 2; }
                SCAN_SCRAPING_PATTERNS+=("$1")
                ;;
            --format)
                shift
                [ $# -gt 0 ] || { warp_message_error "--format requires a value"; return 2; }
                _format="$1"
                ;;
            --request-time-field)
                shift
                [ $# -gt 0 ] || { warp_message_error "--request-time-field requires a value"; return 2; }
                _request_time_field="$1"
                ;;
            --since)
                shift
                [ $# -gt 0 ] || { warp_message_error "--since requires a value"; return 2; }
                _since="$1"
                ;;
            --window)
                shift
                [ $# -gt 0 ] || { warp_message_error "--window requires a value"; return 2; }
                _window="$1"
                ;;
            --page-gap)
                shift
                [ $# -gt 0 ] || { warp_message_error "--page-gap requires a value"; return 2; }
                _page_gap="$1"
                ;;
            --json)
                _json=1
                ;;
            --save)
                _save=1
                ;;
            --output-dir)
                shift
                [ $# -gt 0 ] || { warp_message_error "--output-dir requires a value"; return 2; }
                _output_dir="$1"
                ;;
            --output)
                shift
                [ $# -gt 0 ] || { warp_message_error "--output requires a value"; return 2; }
                _output_file="$1"
                ;;
            --no-progress)
                _progress=0
                ;;
            --*)
                warp_message_error "unknown option for scan scraping: $1"
                return 2
                ;;
            *)
                SCAN_SCRAPING_PATTERNS+=("$1")
                ;;
        esac
        shift
    done

    case "$_top_n" in
        ''|*[!0-9]*)
            warp_message_error "invalid --top value: $_top_n"
            return 2
            ;;
    esac

    case "$_min_score" in
        ''|*[!0-9]*)
            warp_message_error "invalid --min-score value: $_min_score"
            return 2
            ;;
    esac

    case "$_format" in
        auto|combined|warp) ;;
        *)
            warp_message_error "invalid --format value: $_format"
            return 2
            ;;
    esac

    if [ -n "$_request_time_field" ]; then
        case "$_request_time_field" in
            *[!0-9]*)
                warp_message_error "invalid --request-time-field value: $_request_time_field"
                return 2
                ;;
        esac
    fi

    case "$_page_gap" in
        ''|*[!0-9]*)
            warp_message_error "invalid --page-gap value: $_page_gap"
            return 2
            ;;
    esac

    if [ "$_page_gap" -lt 1 ]; then
        warp_message_error "--page-gap must be greater than zero"
        return 2
    fi

    if [ -n "$_since" ]; then
        _since_epoch=$(scan_scraping_since_to_epoch "$_since")
        if [ -z "$_since_epoch" ]; then
            warp_message_error "invalid --since value: $_since"
            warp_message_error "use relative durations like 15m, 1h, 24h, 7d, or an absolute date accepted by date -d"
            return 2
        fi
    fi

    if [ -n "$_window" ]; then
        _window_seconds=$(scan_scraping_duration_to_seconds "$_window")
        if [ -z "$_window_seconds" ] || [ "$_window_seconds" -le 0 ]; then
            warp_message_error "invalid --window value: $_window"
            warp_message_error "use durations like 1m, 5m, 1h, or 1d"
            return 2
        fi
    fi

    if [ $_json -eq 1 ] && [ -z "$_output_file" ]; then
        export WARP_SKIP_UPDATE_CHECK=1
    fi

    if [ $_save -eq 1 ] && [ -z "$_output_file" ]; then
        _output_file=$(scan_scraping_auto_output_file "$_output_dir" "$_json")
    fi

    scan_scraping_resolve_files
    if [ ${#SCAN_SCRAPING_FILES[@]} -eq 0 ]; then
        warp_message_error "no log files matched"
        return 1
    fi

    _total_bytes=$(scan_scraping_total_input_size)
    export WARP_SCAN_SCRAPING_PROGRESS="$_progress"
    export WARP_SCAN_SCRAPING_TOTAL_BYTES="$_total_bytes"

    _summary_file=$(mktemp 2>/dev/null) || {
        warp_message_error "could not create temporary summary file"
        return 1
    }

    _tmp_output=$(mktemp 2>/dev/null) || {
        rm -f "$_summary_file"
        warp_message_error "could not create temporary output file"
        return 1
    }

    if [ $_progress -eq 1 ]; then
        _progress_file=$(mktemp 2>/dev/null)
        if [ -n "$_progress_file" ]; then
            export WARP_SCAN_SCRAPING_PROGRESS_FILE="$_progress_file"
        else
            export WARP_SCAN_SCRAPING_PROGRESS=0
        fi
    fi

    scan_scraping_analyze_with_spinner "$_summary_file" "$_min_score" "$_request_time_field" "$_since_epoch" "$_window_seconds" "$_page_gap"
    _status=$?
    if [ $_status -ne 0 ]; then
        rm -f "$_summary_file" "$_tmp_output" "$_progress_file"
        return $_status
    fi

    scan_scraping_render_with_spinner "$_summary_file" "$_top_n" "$_min_score" "$_json" "$_tmp_output"
    _status=$?
    if [ $_status -ne 0 ]; then
        rm -f "$_summary_file" "$_tmp_output" "$_progress_file"
        return $_status
    fi

    scan_scraping_write_output "$_output_file" "$_tmp_output"
    _status=$?

    rm -f "$_summary_file" "$_tmp_output" "$_progress_file"
    return $_status
}

function scan_main()
{
    scan_command "$@"
}
