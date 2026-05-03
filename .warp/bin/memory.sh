#!/bin/bash

. "$PROJECTPATH/.warp/bin/memory_help.sh"

MEMORY_PROGRESS=0
MEMORY_PROGRESS_PID=""
MEMORY_LABEL_WIDTH=35
MEMORY_SECTION_SEPARATOR="---------------------------------"

memory_print() {
    printf '%b\n' "$1"
}

memory_print_info() {
    printf '%b\n' "${FCYN}$1${RS}"
}

memory_print_warn() {
    printf '%b\n' "${FYEL}$1${RS}"
}

memory_print_kv() {
    local _label="$1"
    local _value="$2"

    printf '%-*s %b\n' "$MEMORY_LABEL_WIDTH" "${_label}:" "${FCYN}${_value}${RS}"
}

memory_print_separator() {
    memory_print "$MEMORY_SECTION_SEPARATOR"
}

memory_print_php_suggest_block() {
    local _suggest="$1"
    local _line=""
    local _php_key=""
    local _php_value=""

    while IFS= read -r _line; do
        [ -n "$_line" ] || continue
        _php_key=$(printf '%s' "$_line" | cut -d '=' -f1)
        _php_value=$(printf '%s' "$_line" | cut -d '=' -f2-)
        _php_key=$(memory_trim "$_php_key")
        _php_value=$(memory_trim "$_php_value")
        memory_print_kv "PHP-FPM ${_php_key}" "${_php_value}"
    done <<EOF
$_suggest
EOF
}

memory_progress_begin() {
    local _label="$1"
    [ "$MEMORY_PROGRESS" = "1" ] || return 0

    if [ -t 2 ]; then
        (
            local _spin='|/-\'
            local _i=0
            while :; do
                _i=$(((_i + 1) % 4))
                printf "\r[%c] %s" "${_spin:$_i:1}" "$_label" >&2
                sleep 0.1
            done
        ) &
        MEMORY_PROGRESS_PID=$!
    else
        printf "[..] %s\n" "$_label" >&2
    fi
}

memory_progress_end() {
    local _status="$1"
    local _label="$2"
    [ "$MEMORY_PROGRESS" = "1" ] || return 0

    if [ -n "$MEMORY_PROGRESS_PID" ]; then
        kill "$MEMORY_PROGRESS_PID" >/dev/null 2>&1 || true
        wait "$MEMORY_PROGRESS_PID" 2>/dev/null || true
        MEMORY_PROGRESS_PID=""
        printf "\r\033[K" >&2
    fi

    if [ "$_status" -eq 0 ]; then
        printf "[ok] %s\n" "$_label" >&2
    else
        printf "[error] %s\n" "$_label" >&2
    fi
}

memory_trim() {
    printf '%s' "$1" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

memory_docker_available() {
    command -v docker >/dev/null 2>&1 && command -v docker-compose >/dev/null 2>&1
}

memory_compose_available() {
    [ -f "$DOCKERCOMPOSEFILE" ] && memory_docker_available
}

memory_host_total_mb() {
    if [ -r /proc/meminfo ]; then
        awk '/^MemTotal:/ {printf "%d\n", $2/1024; exit}' /proc/meminfo
        return 0
    fi

    if command -v sysctl >/dev/null 2>&1; then
        _bytes=$(sysctl -n hw.memsize 2>/dev/null)
        if [[ "$_bytes" =~ ^[0-9]+$ ]]; then
            awk -v b="$_bytes" 'BEGIN { printf "%d\n", b/1024/1024 }'
            return 0
        fi
    fi

    echo ""
}

memory_host_used_mb() {
    if [ -r /proc/meminfo ]; then
        awk '
            /^MemTotal:/ { t=$2 }
            /^MemAvailable:/ { a=$2 }
            END { if (t>0 && a>0) printf "%d\n", (t-a)/1024; else print "" }
        ' /proc/meminfo
        return 0
    fi

    if command -v vm_stat >/dev/null 2>&1 && command -v sysctl >/dev/null 2>&1; then
        _pagesize=$(sysctl -n hw.pagesize 2>/dev/null)
        _active=$(vm_stat 2>/dev/null | awk '/Pages active/ {gsub("\\.","",$3); print $3}')
        _wired=$(vm_stat 2>/dev/null | awk '/Pages wired down/ {gsub("\\.","",$4); print $4}')
        _comp=$(vm_stat 2>/dev/null | awk '/Pages occupied by compressor/ {gsub("\\.","",$5); print $5}')
        if [[ "$_pagesize" =~ ^[0-9]+$ ]] && [[ "$_active" =~ ^[0-9]+$ ]] && [[ "$_wired" =~ ^[0-9]+$ ]] && [[ "$_comp" =~ ^[0-9]+$ ]]; then
            awk -v p="$_pagesize" -v a="$_active" -v w="$_wired" -v c="$_comp" 'BEGIN { printf "%d\n", ((a+w+c)*p)/1024/1024 }'
            return 0
        fi
    fi

    echo ""
}

memory_host_used_pct() {
    _used="$1"
    _total="$2"
    if [[ "$_used" =~ ^[0-9]+$ ]] && [[ "$_total" =~ ^[0-9]+$ ]] && [ "$_total" -gt 0 ]; then
        awk -v u="$_used" -v t="$_total" 'BEGIN { printf "%.1f", (u/t)*100 }'
        return 0
    fi
    echo "N/A"
}

memory_host_load_1m() {
    if command -v uptime >/dev/null 2>&1; then
        uptime 2>/dev/null | sed -n 's/.*load averages\{0,1\}:[[:space:]]*\([^,[:space:]]*\).*/\1/p' | head -n1
        return 0
    fi
    echo ""
}

memory_host_cores() {
    warp_host_cpu_physical
}

memory_host_threads() {
    warp_host_cpu_logical
}

memory_host_sockets() {
    warp_host_cpu_sockets
}

memory_host_threads_per_core() {
    warp_host_cpu_threads_per_core
}

memory_host_deploy_threads() {
    warp_host_worker_threads_default
}

memory_host_threads_reserve() {
    warp_host_threads_reserve
}

memory_host_cpu_summary() {
    warp_host_cpu_topology_summary
}

memory_mb_to_human() {
    _mb="$1"
    if ! [[ "$_mb" =~ ^[0-9]+$ ]]; then
        echo "N/A"
        return 0
    fi
    if [ "$_mb" -ge 1024 ]; then
        awk -v mb="$_mb" 'BEGIN { printf "%.2f GB", mb/1024 }'
    else
        echo "${_mb} MB"
    fi
}

memory_bytes_to_mb_ceil() {
    _b="$1"
    if ! [[ "$_b" =~ ^[0-9]+$ ]]; then
        echo ""
        return 0
    fi
    awk -v b="$_b" 'BEGIN { v=b/1024/1024; if (v > int(v)) v=int(v)+1; else v=int(v); print v }'
}

memory_round_up_64() {
    _mb="$1"
    if ! [[ "$_mb" =~ ^[0-9]+$ ]]; then
        echo ""
        return 0
    fi
    [ "$_mb" -lt 64 ] && _mb=64
    awk -v mb="$_mb" 'BEGIN { v=int((mb+63)/64)*64; print v }'
}

memory_ceil_number() {
    _v="$1"
    awk -v v="$_v" 'BEGIN { if (v+0 > int(v+0)) print int(v+0)+1; else print int(v+0) }'
}

memory_alert_level() {
    _ratio="$1"
    if awk -v r="$_ratio" 'BEGIN { exit !(r >= 90) }'; then
        echo "CRITICAL"
    elif awk -v r="$_ratio" 'BEGIN { exit !(r >= 75) }'; then
        echo "WARNING"
    else
        echo "OK"
    fi
}

memory_with_unit() {
    _val="$1"
    _unit="$2"
    if [ -z "$_val" ] || [ "$_val" = "N/A" ]; then
        echo "N/A"
    else
        echo "${_val}${_unit}"
    fi
}

memory_mb_human_or_na() {
    _mb="$1"
    if [ -z "$_mb" ] || ! [[ "$_mb" =~ ^[0-9]+$ ]]; then
        echo "N/A"
    else
        memory_mb_to_human "$_mb"
    fi
}

memory_ratio_display() {
    _ratio="$1"
    if [ -z "$_ratio" ] || [ "$_ratio" = "N/A" ]; then
        echo "N/A"
    else
        echo "${_ratio}%"
    fi
}

memory_env_value() {
    _k="$1"
    _v=$(warp_env_read_var "$_k")
    _v=$(memory_trim "$_v")
    if [ -z "$_v" ]; then
        echo "not set"
    else
        echo "$_v"
    fi
}

memory_env_raw() {
    _k="$1"
    _v=$(warp_env_read_var "$_k")
    memory_trim "$_v"
}

memory_es_auth_user() {
    _user=$(memory_env_raw "ES_USER")
    [ -n "$_user" ] && { echo "$_user"; return 0; }

    _search_engine=$(memory_env_raw "SEARCH_ENGINE" | tr '[:upper:]' '[:lower:]')
    if [ "$_search_engine" = "opensearch" ]; then
        echo "admin"
        return 0
    fi

    echo ""
}

memory_es_auth_password() {
    memory_env_raw "ES_PASSWORD"
}

memory_env_to_mb() {
    _raw="$1"
    _v=$(echo "$_raw" | tr '[:upper:]' '[:lower:]' | tr -d ' ')
    case "$_v" in
        *gb|*g)
            _n=$(echo "$_v" | sed -E 's/(gb|g)$//')
            awk -v n="$_n" 'BEGIN { if (n+0>0) print int((n*1024)+0.999); else print "" }'
        ;;
        *mb|*m)
            _n=$(echo "$_v" | sed -E 's/(mb|m)$//')
            awk -v n="$_n" 'BEGIN { if (n+0>0) print int(n+0.999); else print "" }'
        ;;
        *kb|*k)
            _n=$(echo "$_v" | sed -E 's/(kb|k)$//')
            awk -v n="$_n" 'BEGIN { if (n+0>0) print int((n/1024)+0.999); else print "" }'
        ;;
        *)
            if [[ "$_v" =~ ^[0-9]+$ ]]; then
                echo "$_v"
            else
                echo ""
            fi
        ;;
    esac
}

memory_compose_service_id() {
    _service="$1"
    memory_compose_available || { echo ""; return 0; }
    docker-compose -f "$DOCKERCOMPOSEFILE" ps -q "$_service" 2>/dev/null | head -n 1
}

memory_service_is_running() {
    _cid="$1"
    [ -n "$_cid" ] || { echo "false"; return 0; }
    docker inspect --format '{{.State.Running}}' "$_cid" 2>/dev/null
}

memory_service_mem_usage() {
    _service="$1"
    memory_compose_available || { echo "N/A"; return 0; }
    _cid=$(memory_compose_service_id "$_service")
    [ -n "$_cid" ] || { echo "N/A"; return 0; }
    [ "$(memory_service_is_running "$_cid")" = "true" ] || { echo "stopped"; return 0; }
    _mem=$(docker stats --no-stream --format '{{.MemUsage}}' "$_cid" 2>/dev/null | head -n 1)
    _mem=$(memory_trim "$_mem")
    [ -n "$_mem" ] && echo "$_mem" || echo "N/A"
}

memory_search_service_name() {
    for _svc in elasticsearch opensearch; do
        _cid=$(memory_compose_service_id "$_svc")
        [ -n "$_cid" ] || continue
        [ "$(memory_service_is_running "$_cid")" = "true" ] || continue
        echo "$_svc"
        return 0
    done
    echo "elasticsearch"
}

memory_mem_usage_to_mb() {
    _raw="$1"
    _left=$(echo "$_raw" | awk -F'/' '{print $1}')
    _left=$(echo "$_left" | tr -d ' ')
    [ -n "$_left" ] || { echo ""; return 0; }

    _num=$(echo "$_left" | sed -E 's/^([0-9]+([.][0-9]+)?).*/\1/')
    _unit=$(echo "$_left" | sed -E 's/^[0-9]+([.][0-9]+)?//')
    _unit=$(echo "$_unit" | tr '[:upper:]' '[:lower:]')
    [ -n "$_num" ] || { echo ""; return 0; }

    case "$_unit" in
        kib)
            awk -v n="$_num" 'BEGIN { v=n/1024; if (v > int(v)) v=int(v)+1; else v=int(v); print v }'
        ;;
        mib)
            awk -v n="$_num" 'BEGIN { if (n > int(n)) print int(n)+1; else print int(n) }'
        ;;
        gib)
            awk -v n="$_num" 'BEGIN { v=n*1024; if (v > int(v)) v=int(v)+1; else v=int(v); print v }'
        ;;
        kb)
            awk -v n="$_num" 'BEGIN { v=n/1000; if (v > int(v)) v=int(v)+1; else v=int(v); print v }'
        ;;
        mb)
            awk -v n="$_num" 'BEGIN { if (n > int(n)) print int(n)+1; else print int(n) }'
        ;;
        gb)
            awk -v n="$_num" 'BEGIN { v=n*1000; if (v > int(v)) v=int(v)+1; else v=int(v); print v }'
        ;;
        b|bytes)
            awk -v n="$_num" 'BEGIN { v=n/1024/1024; if (v > int(v)) v=int(v)+1; else v=int(v); print v }'
        ;;
        *)
            echo ""
        ;;
    esac
}

memory_redis_info_memory() {
    local _service="$1"
    local _cli_bin=""
    memory_compose_available || return 1
    _cid=$(memory_compose_service_id "$_service")
    [ -n "$_cid" ] || return 1
    [ "$(memory_service_is_running "$_cid")" = "true" ] || return 1
    _cli_bin=$(warp_cache_engine_cli_bin)
    docker exec -i "$_cid" "$_cli_bin" INFO memory 2>/dev/null
}

memory_redis_field() {
    _blob="$1"
    _field="$2"
    echo "$_blob" | awk -F: -v k="$_field" '$1==k {gsub(/\r/,"",$2); print $2; exit}'
}

memory_es_heap_stats_mb() {
    memory_compose_available || return 1
    _service=$(memory_search_service_name)
    _cid=$(memory_compose_service_id "$_service")
    [ -n "$_cid" ] || return 1
    [ "$(memory_service_is_running "$_cid")" = "true" ] || return 1
    _es_user=$(memory_es_auth_user)
    _es_password=$(memory_es_auth_password)

    _line=$(docker exec -i "$_cid" sh -lc '
        _user="$1"
        _password="$2"
        endpoint="/_nodes/stats/jvm?filter_path=nodes.*.jvm.mem.heap_used_in_bytes,nodes.*.jvm.mem.heap_max_in_bytes"
        try_fetch() {
            _url="$1"
            if command -v curl >/dev/null 2>&1; then
                if [ -n "$_user" ] && [ -n "$_password" ]; then
                    curl -ks --user "$_user:$_password" "$_url" 2>/dev/null
                else
                    curl -ks "$_url" 2>/dev/null
                fi
                return 0
            fi
            if command -v wget >/dev/null 2>&1; then
                if [ -n "$_user" ] && [ -n "$_password" ]; then
                    wget --no-check-certificate -qO- --user "$_user" --password "$_password" "$_url" 2>/dev/null
                else
                    wget --no-check-certificate -qO- "$_url" 2>/dev/null
                fi
                return 0
            fi
            return 1
        }
        _resp="$(try_fetch "http://localhost:9200$endpoint")"
        if [ -z "$_resp" ]; then
            _resp="$(try_fetch "https://localhost:9200$endpoint")"
        fi
        echo "$_resp"
    ' _ "$_es_user" "$_es_password" 2>/dev/null \
        | tr -d '\n' \
        | sed -E 's/.*"heap_used_in_bytes"[[:space:]]*:[[:space:]]*([0-9]+).*"heap_max_in_bytes"[[:space:]]*:[[:space:]]*([0-9]+).*/\1 \2/')

    _used_b=$(echo "$_line" | awk '{print $1}')
    _max_b=$(echo "$_line" | awk '{print $2}')
    [[ "$_used_b" =~ ^[0-9]+$ ]] || return 1
    [[ "$_max_b" =~ ^[0-9]+$ ]] || return 1

    _used_mb=$(memory_bytes_to_mb_ceil "$_used_b")
    _max_mb=$(memory_bytes_to_mb_ceil "$_max_b")
    echo "$_used_mb $_max_mb"
}

memory_php_conf_file() {
    [ -f "$PROJECTPATH/.warp/docker/config/php/php-fpm.conf" ] && { echo "$PROJECTPATH/.warp/docker/config/php/php-fpm.conf"; return 0; }
    [ -f "$PROJECTPATH/.warp/setup/php/config/php/php-fpm.conf" ] && { echo "$PROJECTPATH/.warp/setup/php/config/php/php-fpm.conf"; return 0; }
    echo ""
}

memory_php_conf_read() {
    _file="$1"
    _key="$2"
    [ -f "$_file" ] || { echo ""; return 0; }
    awk -F '=' -v k="$_key" '
        function trim(s){gsub(/^[ \t]+|[ \t]+$/, "", s); return s}
        $0 !~ /^[ \t]*[;#]/ {
            lhs=trim($1)
            if (lhs == k) {
                rhs=$0; sub(/^[^=]*=/, "", rhs); print trim(rhs); exit
            }
        }
    ' "$_file"
}

memory_php_max_children_from_ram() {
    _ram_mb="$1"
    _ram_gb=$(awk -v mb="$_ram_mb" 'BEGIN { printf "%.4f", mb/1024 }')

    _raw=$(awk -v x="$_ram_gb" '
        BEGIN {
            x1=7.5; y1=15;
            x2=15.5; y2=30;
            x3=31.5; y3=70;
            if (x <= x2) {
                m=(y2-y1)/(x2-x1);
                y=y1 + m*(x-x1);
            } else {
                m=(y3-y2)/(x3-x2);
                y=y2 + m*(x-x2);
            }
            if (y < 1) y=1;
            printf "%.4f", y;
        }')

    _ceil=$(memory_ceil_number "$_raw")
    if [ "$_ceil" -lt 20 ]; then
        echo $((_ceil + 1))
    else
        echo $((_ceil + 2))
    fi
}

memory_php_suggest_values() {
    _ram_mb="$1"
    _max_children=$(memory_php_max_children_from_ram "$_ram_mb")
    _start=$(memory_ceil_number "$(awk -v m="$_max_children" 'BEGIN {print m*0.20}')")
    _min_spare=$(memory_ceil_number "$(awk -v m="$_max_children" 'BEGIN {print m*0.20}')")
    _max_spare=$(memory_ceil_number "$(awk -v m="$_max_children" 'BEGIN {print m*0.40}')")

    [ "$_start" -gt 15 ] && _start=15
    [ "$_min_spare" -gt 15 ] && _min_spare=15
    [ "$_max_spare" -gt 30 ] && _max_spare=30
    [ "$_max_spare" -lt "$_min_spare" ] && _max_spare="$_min_spare"

    _ram_gb=$(awk -v mb="$_ram_mb" 'BEGIN {print mb/1024}')
    _max_req=$(awk -v gb="$_ram_gb" 'BEGIN {
        x1=7.5; y1=1000;
        x2=15.5; y2=2000;
        x3=31.5; y3=3000;
        if (gb <= x2) {
            m=(y2-y1)/(x2-x1); y=y1 + m*(gb-x1);
        } else {
            m=(y3-y2)/(x3-x2); y=y2 + m*(gb-x2);
        }
        if (y < 500) y=500;
        if (y > 5000) y=5000;
        if (y > int(y)) y=int(y)+1; else y=int(y);
        print y;
    }')

    cat <<EOF
pm=dynamic
pm.max_children=$_max_children
pm.start_servers=$_start
pm.min_spare_servers=$_min_spare
pm.max_spare_servers=$_max_spare
pm.max_requests=$_max_req
EOF
}

memory_redis_recommend() {
    _used_mb="$1"
    _peak_mb="$2"

    if [ -z "$_used_mb" ] || ! [[ "$_used_mb" =~ ^[0-9]+$ ]]; then
        echo "N/A N/A N/A N/A"
        return 0
    fi

    if [ "$_used_mb" -lt 1024 ]; then
        _base=$(awk -v u="$_used_mb" 'BEGIN { print u*2.0 }')
    else
        _base=$(awk -v u="$_used_mb" 'BEGIN { print u*1.6 }')
    fi

    _base_mb=$(memory_round_up_64 "$(memory_ceil_number "$_base")")
    _safe_mb="$_base_mb"
    _note="OK"
    _peak_ratio="0"

    if [[ "$_peak_mb" =~ ^[0-9]+$ ]] && [ "$_base_mb" -gt 0 ]; then
        _peak_ratio=$(awk -v p="$_peak_mb" -v b="$_base_mb" 'BEGIN { printf "%.2f", (p*100)/b }')
        _level=$(memory_alert_level "$_peak_ratio")
        _note="$_level"
        if [ "$_level" = "WARNING" ]; then
            _safe=$(awk -v p="$_peak_mb" 'BEGIN { print p*1.15 }')
            _safe_mb=$(memory_round_up_64 "$(memory_ceil_number "$_safe")")
            [ "$_safe_mb" -lt "$_base_mb" ] && _safe_mb="$_base_mb"
        elif [ "$_level" = "CRITICAL" ]; then
            _safe=$(awk -v p="$_peak_mb" 'BEGIN { print p*1.30 }')
            _safe_mb=$(memory_round_up_64 "$(memory_ceil_number "$_safe")")
            [ "$_safe_mb" -lt "$_base_mb" ] && _safe_mb="$_base_mb"
        fi
    fi

    echo "$_base_mb $_safe_mb $_note $_peak_ratio"
}

memory_es_recommend() {
    _used_mb="$1"
    _peak_mb="$2"

    if [ -z "$_used_mb" ] || ! [[ "$_used_mb" =~ ^[0-9]+$ ]]; then
        echo "N/A N/A N/A N/A"
        return 0
    fi

    if [ "$_used_mb" -lt 1024 ]; then
        _base=$(awk -v u="$_used_mb" 'BEGIN { print u*1.7 }')
    else
        _base=$(awk -v u="$_used_mb" 'BEGIN { print u*1.5 }')
    fi

    _base_mb=$(memory_round_up_64 "$(memory_ceil_number "$_base")")
    _safe_mb="$_base_mb"
    _note="OK"
    _peak_ratio="0"

    if [[ "$_peak_mb" =~ ^[0-9]+$ ]] && [ "$_base_mb" -gt 0 ]; then
        _peak_ratio=$(awk -v p="$_peak_mb" -v b="$_base_mb" 'BEGIN { printf "%.2f", (p*100)/b }')
        _level=$(memory_alert_level "$_peak_ratio")
        _note="$_level"
        if [ "$_level" = "WARNING" ]; then
            _safe=$(awk -v p="$_peak_mb" 'BEGIN { print p*1.15 }')
            _safe_mb=$(memory_round_up_64 "$(memory_ceil_number "$_safe")")
            [ "$_safe_mb" -lt "$_base_mb" ] && _safe_mb="$_base_mb"
        elif [ "$_level" = "CRITICAL" ]; then
            _safe=$(awk -v p="$_peak_mb" 'BEGIN { print p*1.30 }')
            _safe_mb=$(memory_round_up_64 "$(memory_ceil_number "$_safe")")
            [ "$_safe_mb" -lt "$_base_mb" ] && _safe_mb="$_base_mb"
        fi
    fi

    echo "$_base_mb $_safe_mb $_note $_peak_ratio"
}

memory_usage_ratio_pct() {
    _used="$1"
    _assigned="$2"
    if ! [[ "$_used" =~ ^[0-9]+$ ]] || ! [[ "$_assigned" =~ ^[0-9]+$ ]] || [ "$_assigned" -le 0 ]; then
        echo ""
        return 0
    fi
    awk -v u="$_used" -v a="$_assigned" 'BEGIN { printf "%.2f", (u*100)/a }'
}

memory_report_print_text() {
    _show_suggest="$1"

    memory_progress_begin "check host resources"
    _host_mb=$(memory_host_total_mb)
    _host_used_mb=$(memory_host_used_mb)
    _host_used_pct=$(memory_host_used_pct "$_host_used_mb" "$_host_mb")
    _host_load_1m=$(memory_host_load_1m)
    _host_human=$(memory_mb_to_human "$_host_mb")
    _host_cores=$(memory_host_cores)
    _host_threads=$(memory_host_threads)
    _host_sockets=$(memory_host_sockets)
    _host_threads_per_core=$(memory_host_threads_per_core)
    _host_deploy_threads=$(memory_host_deploy_threads)
    _host_threads_reserve=$(memory_host_threads_reserve)
    _host_cpu_summary=$(memory_host_cpu_summary)
    [ -z "$_host_cores" ] && _host_cores="N/A"
    [ -z "$_host_threads" ] && _host_threads="N/A"
    [ -z "$_host_sockets" ] && _host_sockets="N/A"
    [ -z "$_host_threads_per_core" ] && _host_threads_per_core="N/A"
    [ -z "$_host_deploy_threads" ] && _host_deploy_threads="N/A"
    [ -z "$_host_threads_reserve" ] && _host_threads_reserve="N/A"
    [ -z "$_host_cpu_summary" ] && _host_cpu_summary="N/A"
    [ -z "$_host_load_1m" ] && _host_load_1m="N/A"
    memory_progress_end 0 "check host resources"

    memory_progress_begin "check container memory usage"
    _usage_php=$(memory_service_mem_usage "php")
    _usage_mysql=$(memory_service_mem_usage "mysql")
    _search_service=$(memory_search_service_name)
    _usage_es_container=$(memory_service_mem_usage "$_search_service")
    _usage_rc_container=$(memory_service_mem_usage "redis-cache")
    _usage_rf_container=$(memory_service_mem_usage "redis-fpc")
    _usage_rs_container=$(memory_service_mem_usage "redis-session")
    memory_progress_end 0 "check container memory usage"

    memory_progress_begin "read current environment config"
    _cfg_es=$(memory_env_value "ES_MEMORY")
    _cfg_rc=$(memory_env_value "REDIS_CACHE_MAXMEMORY")
    _cfg_rcp=$(memory_env_value "REDIS_CACHE_MAXMEMORY_POLICY")
    _cfg_rf=$(memory_env_value "REDIS_FPC_MAXMEMORY")
    _cfg_rfp=$(memory_env_value "REDIS_FPC_MAXMEMORY_POLICY")
    _cfg_rs=$(memory_env_value "REDIS_SESSION_MAXMEMORY")
    _cfg_rsp=$(memory_env_value "REDIS_SESSION_MAXMEMORY_POLICY")
    memory_progress_end 0 "read current environment config"

    memory_progress_begin "read php-fpm settings"
    _php_conf=$(memory_php_conf_file)
    _php_pm=$(memory_php_conf_read "$_php_conf" "pm")
    _php_mc=$(memory_php_conf_read "$_php_conf" "pm.max_children")
    _php_ss=$(memory_php_conf_read "$_php_conf" "pm.start_servers")
    _php_min=$(memory_php_conf_read "$_php_conf" "pm.min_spare_servers")
    _php_max=$(memory_php_conf_read "$_php_conf" "pm.max_spare_servers")
    _php_req=$(memory_php_conf_read "$_php_conf" "pm.max_requests")
    [ -z "$_php_pm" ] && _php_pm="N/A"
    [ -z "$_php_mc" ] && _php_mc="N/A"
    [ -z "$_php_ss" ] && _php_ss="N/A"
    [ -z "$_php_min" ] && _php_min="N/A"
    [ -z "$_php_max" ] && _php_max="N/A"
    [ -z "$_php_req" ] && _php_req="N/A"
    memory_progress_end 0 "read php-fpm settings"

    memory_progress_begin "collect redis metrics"
    _redis_cache_info=$(memory_redis_info_memory "redis-cache")
    _redis_fpc_info=$(memory_redis_info_memory "redis-fpc")
    _redis_session_info=$(memory_redis_info_memory "redis-session")
    _rc_used_b=$(memory_redis_field "$_redis_cache_info" "used_memory")
    _rc_peak_b=$(memory_redis_field "$_redis_cache_info" "used_memory_peak")
    _rc_max_b=$(memory_redis_field "$_redis_cache_info" "maxmemory")
    _rf_used_b=$(memory_redis_field "$_redis_fpc_info" "used_memory")
    _rf_peak_b=$(memory_redis_field "$_redis_fpc_info" "used_memory_peak")
    _rf_max_b=$(memory_redis_field "$_redis_fpc_info" "maxmemory")
    _rs_used_b=$(memory_redis_field "$_redis_session_info" "used_memory")
    _rs_peak_b=$(memory_redis_field "$_redis_session_info" "used_memory_peak")
    _rs_max_b=$(memory_redis_field "$_redis_session_info" "maxmemory")
    _rc_used_mb=$(memory_bytes_to_mb_ceil "$_rc_used_b")
    _rc_peak_mb=$(memory_bytes_to_mb_ceil "$_rc_peak_b")
    _rc_max_mb=$(memory_bytes_to_mb_ceil "$_rc_max_b")
    _rf_used_mb=$(memory_bytes_to_mb_ceil "$_rf_used_b")
    _rf_peak_mb=$(memory_bytes_to_mb_ceil "$_rf_peak_b")
    _rf_max_mb=$(memory_bytes_to_mb_ceil "$_rf_max_b")
    _rs_used_mb=$(memory_bytes_to_mb_ceil "$_rs_used_b")
    _rs_peak_mb=$(memory_bytes_to_mb_ceil "$_rs_peak_b")
    _rs_max_mb=$(memory_bytes_to_mb_ceil "$_rs_max_b")
    memory_progress_end 0 "collect redis metrics"

    memory_progress_begin "collect elasticsearch metrics"
    _es_heap_stats=$(memory_es_heap_stats_mb)
    _es_used_mb=$(echo "$_es_heap_stats" | awk '{print $1}')
    _es_max_mb=$(echo "$_es_heap_stats" | awk '{print $2}')
    _es_cfg_mb=$(memory_env_to_mb "$_cfg_es")
    _es_source="heap_api"
    if ! [[ "$_es_used_mb" =~ ^[0-9]+$ ]]; then
        _es_used_mb=$(memory_mem_usage_to_mb "$_usage_es_container")
        _es_source="container_approx"
    fi
    _es_assigned_mb="$_es_max_mb"
    [ -z "$_es_assigned_mb" ] && _es_assigned_mb="$_es_cfg_mb"
    [ -z "$_es_assigned_mb" ] && _es_source="unknown"
    _es_peak_mb="$_es_used_mb"
    [ -z "$_es_peak_mb" ] && _es_peak_mb="0"
    memory_progress_end 0 "collect elasticsearch metrics"

    memory_progress_begin "evaluate assigned-memory alerts"
    _rc_ratio=$(memory_usage_ratio_pct "$_rc_used_mb" "$_rc_max_mb")
    _rf_ratio=$(memory_usage_ratio_pct "$_rf_used_mb" "$_rf_max_mb")
    _rs_ratio=$(memory_usage_ratio_pct "$_rs_used_mb" "$_rs_max_mb")
    _es_ratio=$(memory_usage_ratio_pct "$_es_used_mb" "$_es_assigned_mb")

    _rc_alert=$(memory_alert_level "${_rc_ratio:-0}")
    _rf_alert=$(memory_alert_level "${_rf_ratio:-0}")
    _rs_alert=$(memory_alert_level "${_rs_ratio:-0}")
    _es_alert=$(memory_alert_level "${_es_ratio:-0}")

    _rc_warn="no configured limit"
    _rf_warn="no configured limit"
    _rs_warn="no configured limit"
    if [[ "$_rc_max_mb" =~ ^[0-9]+$ ]] && [ "$_rc_max_mb" -gt 0 ]; then _rc_warn="${_rc_alert} (${_rc_ratio}%)"; fi
    if [[ "$_rf_max_mb" =~ ^[0-9]+$ ]] && [ "$_rf_max_mb" -gt 0 ]; then _rf_warn="${_rf_alert} (${_rf_ratio}%)"; fi
    if [[ "$_rs_max_mb" =~ ^[0-9]+$ ]] && [ "$_rs_max_mb" -gt 0 ]; then _rs_warn="${_rs_alert} (${_rs_ratio}%)"; fi
    _es_warn="no detectable limit"
    if [[ "$_es_assigned_mb" =~ ^[0-9]+$ ]] && [ "$_es_assigned_mb" -gt 0 ] && [[ "$_es_used_mb" =~ ^[0-9]+$ ]]; then
        _es_warn="${_es_alert} (${_es_ratio}%)"
    fi
    memory_progress_end 0 "evaluate assigned-memory alerts"

    memory_print ""
    memory_print_info "WARP Memory Report"
    memory_print_kv "Host RAM total" "${_host_human}"
    memory_print_kv "Host RAM used" "$(memory_mb_human_or_na "$_host_used_mb") (${_host_used_pct}%)"
    memory_print_kv "Host CPU topology" "${_host_cpu_summary}"
    memory_print_kv "Host CPU sockets" "${_host_sockets}"
    memory_print_kv "Host physical cores" "${_host_cores}"
    memory_print_kv "Host logical threads" "${_host_threads}"
    memory_print_kv "Host threads/core" "${_host_threads_per_core}"
    memory_print_kv "Host thread reserve" "${_host_threads_reserve}"
    memory_print_kv "Suggested deploy THREADS" "${_host_deploy_threads}"
    memory_print_kv "Host load (1m)" "${_host_load_1m}"
    memory_print ""

    memory_print_info "[CURRENT USAGE]"
    memory_print_kv "php (container)" "${_usage_php}"
    memory_print_kv "mysql (container)" "${_usage_mysql}"
    memory_print_kv "elasticsearch (container)" "${_usage_es_container}"
    memory_print_kv "redis-cache (container)" "${_usage_rc_container}"
    memory_print_kv "redis-fpc (container)" "${_usage_rf_container}"
    memory_print_kv "redis-session (container)" "${_usage_rs_container}"
    memory_print ""

    memory_print_info "[SERVICE USAGE]"
    memory_print_separator
    memory_print_kv "elasticsearch used (heap)" "$(memory_mb_human_or_na "$_es_used_mb")"
    memory_print_kv "elasticsearch max (heap)" "$(memory_mb_human_or_na "$_es_assigned_mb")"
    memory_print_separator
    memory_print_kv "redis-cache used" "$(memory_mb_human_or_na "$_rc_used_mb")"
    memory_print_kv "redis-cache peak" "$(memory_mb_human_or_na "$_rc_peak_mb")"
    memory_print_kv "redis-cache maxmemory" "$(memory_mb_human_or_na "$_rc_max_mb")"
    memory_print_kv "redis-fpc used" "$(memory_mb_human_or_na "$_rf_used_mb")"
    memory_print_kv "redis-fpc peak" "$(memory_mb_human_or_na "$_rf_peak_mb")"
    memory_print_kv "redis-fpc maxmemory" "$(memory_mb_human_or_na "$_rf_max_mb")"
    memory_print_kv "redis-session used" "$(memory_mb_human_or_na "$_rs_used_mb")"
    memory_print_kv "redis-session peak" "$(memory_mb_human_or_na "$_rs_peak_mb")"
    memory_print_kv "redis-session maxmemory" "$(memory_mb_human_or_na "$_rs_max_mb")"
    memory_print_separator
    memory_print ""

    memory_print_info "[CURRENT CONFIG]"
    memory_print_separator
    memory_print_kv "ES_MEMORY" "${_cfg_es}"
    memory_print_separator
    memory_print_kv "REDIS_CACHE_MAXMEMORY" "${_cfg_rc}"
    memory_print_kv "REDIS_CACHE_MAXMEMORY_POLICY" "${_cfg_rcp}"
    memory_print_kv "REDIS_FPC_MAXMEMORY" "${_cfg_rf}"
    memory_print_kv "REDIS_FPC_MAXMEMORY_POLICY" "${_cfg_rfp}"
    memory_print_kv "REDIS_SESSION_MAXMEMORY" "${_cfg_rs}"
    memory_print_kv "REDIS_SESSION_MAXMEMORY_POLICY" "${_cfg_rsp}"
    memory_print_separator
    memory_print_kv "PHP-FPM conf" "${_php_conf:-N/A}"
    memory_print_kv "PHP-FPM pm" "${_php_pm}"
    memory_print_kv "PHP-FPM pm.max_children" "${_php_mc}"
    memory_print_kv "PHP-FPM pm.start_servers" "${_php_ss}"
    memory_print_kv "PHP-FPM pm.min_spare_servers" "${_php_min}"
    memory_print_kv "PHP-FPM pm.max_spare_servers" "${_php_max}"
    memory_print_kv "PHP-FPM pm.max_requests" "${_php_req}"
    memory_print_separator
    memory_print ""

    memory_print_info "[ASSIGNED USAGE ALERTS]"
    memory_print_separator
    memory_print_kv "redis-cache" "${_rc_warn}"
    memory_print_kv "redis-fpc" "${_rf_warn}"
    memory_print_kv "redis-session" "${_rs_warn}"
    memory_print_separator
    memory_print_kv "elasticsearch" "${_es_warn}"
    memory_print_kv "elasticsearch data source" "${_es_source}"
    memory_print_separator
    memory_print ""

    if [ "$_show_suggest" = "0" ]; then
        memory_print_info "Operator note:"
        memory_print " - Redis/ES use warning>=75% and critical>=90% against detected assigned memory."
        memory_print " - If a service shows no limit, define maxmemory/heap before operating."
        memory_print ""
        return 0
    fi

    if ! [[ "$_host_mb" =~ ^[0-9]+$ ]]; then
        memory_print_warn "Could not calculate suggestions: total RAM is unavailable."
        memory_print ""
        return 0
    fi

    memory_progress_begin "calculate recommendations"
    read -r _rc_base _rc_safe _rc_note _rc_peak_ratio <<<"$(memory_redis_recommend "$_rc_used_mb" "$_rc_peak_mb")"
    read -r _rf_base _rf_safe _rf_note _rf_peak_ratio <<<"$(memory_redis_recommend "$_rf_used_mb" "$_rf_peak_mb")"
    read -r _rs_base _rs_safe _rs_note _rs_peak_ratio <<<"$(memory_redis_recommend "$_rs_used_mb" "$_rs_peak_mb")"
    read -r _es_base _es_safe _es_note _es_peak_ratio <<<"$(memory_es_recommend "$_es_used_mb" "$_es_peak_mb")"
    _php_suggest=$(memory_php_suggest_values "$_host_mb")
    memory_progress_end 0 "calculate recommendations"

    memory_print_info "[SUGGESTED]"
    memory_print_separator
    memory_print_kv "ES base calculation (service)" "used=$(memory_mb_human_or_na "$_es_used_mb"), source=${_es_source}"
    memory_print_kv "ES_MEMORY (base)" "$(memory_with_unit "$_es_base" "m")"
    memory_print_kv "ES_MEMORY (minimum safe)" "$(memory_with_unit "$_es_safe" "m")  [peak:${_es_note} $(memory_ratio_display "$_es_peak_ratio")]"
    memory_print_separator
    memory_print_kv "REDIS_CACHE_MAXMEMORY (base)" "$(memory_with_unit "$_rc_base" "mb")"
    memory_print_kv "REDIS_CACHE_MAXMEMORY (minimum safe)" "$(memory_with_unit "$_rc_safe" "mb")  [peak:${_rc_note} $(memory_ratio_display "$_rc_peak_ratio")]"
    memory_print_kv "REDIS_CACHE_MAXMEMORY_POLICY" "allkeys-lru"
    memory_print_kv "REDIS_FPC_MAXMEMORY (base)" "$(memory_with_unit "$_rf_base" "mb")"
    memory_print_kv "REDIS_FPC_MAXMEMORY (minimum safe)" "$(memory_with_unit "$_rf_safe" "mb")  [peak:${_rf_note} $(memory_ratio_display "$_rf_peak_ratio")]"
    memory_print_kv "REDIS_FPC_MAXMEMORY_POLICY" "allkeys-lru"
    memory_print_kv "REDIS_SESSION_MAXMEMORY (base)" "$(memory_with_unit "$_rs_base" "mb")"
    memory_print_kv "REDIS_SESSION_MAXMEMORY (minimum safe)" "$(memory_with_unit "$_rs_safe" "mb")  [peak:${_rs_note} $(memory_ratio_display "$_rs_peak_ratio")]"
    memory_print_kv "REDIS_SESSION_MAXMEMORY_POLICY" "noeviction"
    memory_print_separator
    memory_print_php_suggest_block "$_php_suggest"
    memory_print_separator
    memory_print ""

    memory_print_info "Operator note:"
    memory_print " - Redis/ES recommendations are calculated from used_memory and rounded to 64MB blocks."
    memory_print " - If peak is WARNING/CRITICAL, use the minimum safe value."
    memory_print " - In PHP-FPM, pm.max_children uses RAM extrapolation and optimistic rounding (<20 => ceil+1, >=20 => ceil+2)."
    memory_print ""
}

memory_json_escape() {
    echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

memory_report_print_json() {
    _show_suggest="$1"
    _host_mb=$(memory_host_total_mb)
    _host_used_mb=$(memory_host_used_mb)
    _host_used_pct=$(memory_host_used_pct "$_host_used_mb" "$_host_mb")
    _host_load_1m=$(memory_host_load_1m)
    _host_human=$(memory_mb_to_human "$_host_mb")
    _host_cores=$(memory_host_cores)
    _host_threads=$(memory_host_threads)
    _host_sockets=$(memory_host_sockets)
    _host_threads_per_core=$(memory_host_threads_per_core)
    _host_deploy_threads=$(memory_host_deploy_threads)
    _host_threads_reserve=$(memory_host_threads_reserve)
    _host_cpu_summary=$(memory_host_cpu_summary)
    [ -z "$_host_load_1m" ] && _host_load_1m="N/A"
    [ -z "$_host_human" ] && _host_human="N/A"
    [ -z "$_host_cores" ] && _host_cores="N/A"
    [ -z "$_host_threads" ] && _host_threads="N/A"
    [ -z "$_host_sockets" ] && _host_sockets="N/A"
    [ -z "$_host_threads_per_core" ] && _host_threads_per_core="N/A"
    [ -z "$_host_deploy_threads" ] && _host_deploy_threads="N/A"
    [ -z "$_host_threads_reserve" ] && _host_threads_reserve="N/A"
    [ -z "$_host_cpu_summary" ] && _host_cpu_summary="N/A"

    _usage_php=$(memory_service_mem_usage "php")
    _usage_mysql=$(memory_service_mem_usage "mysql")
    _search_service=$(memory_search_service_name)
    _usage_es_container=$(memory_service_mem_usage "$_search_service")
    _usage_rc_container=$(memory_service_mem_usage "redis-cache")
    _usage_rf_container=$(memory_service_mem_usage "redis-fpc")
    _usage_rs_container=$(memory_service_mem_usage "redis-session")

    _cfg_es=$(memory_env_value "ES_MEMORY")
    _cfg_rc=$(memory_env_value "REDIS_CACHE_MAXMEMORY")
    _cfg_rcp=$(memory_env_value "REDIS_CACHE_MAXMEMORY_POLICY")
    _cfg_rf=$(memory_env_value "REDIS_FPC_MAXMEMORY")
    _cfg_rfp=$(memory_env_value "REDIS_FPC_MAXMEMORY_POLICY")
    _cfg_rs=$(memory_env_value "REDIS_SESSION_MAXMEMORY")
    _cfg_rsp=$(memory_env_value "REDIS_SESSION_MAXMEMORY_POLICY")

    _php_conf=$(memory_php_conf_file)
    _php_pm=$(memory_php_conf_read "$_php_conf" "pm")
    _php_mc=$(memory_php_conf_read "$_php_conf" "pm.max_children")
    _php_ss=$(memory_php_conf_read "$_php_conf" "pm.start_servers")
    _php_min=$(memory_php_conf_read "$_php_conf" "pm.min_spare_servers")
    _php_max=$(memory_php_conf_read "$_php_conf" "pm.max_spare_servers")
    _php_req=$(memory_php_conf_read "$_php_conf" "pm.max_requests")
    [ -z "$_php_conf" ] && _php_conf="N/A"
    [ -z "$_php_pm" ] && _php_pm="N/A"
    [ -z "$_php_mc" ] && _php_mc="N/A"
    [ -z "$_php_ss" ] && _php_ss="N/A"
    [ -z "$_php_min" ] && _php_min="N/A"
    [ -z "$_php_max" ] && _php_max="N/A"
    [ -z "$_php_req" ] && _php_req="N/A"

    _redis_cache_info=$(memory_redis_info_memory "redis-cache")
    _redis_fpc_info=$(memory_redis_info_memory "redis-fpc")
    _redis_session_info=$(memory_redis_info_memory "redis-session")
    _rc_used_mb=$(memory_bytes_to_mb_ceil "$(memory_redis_field "$_redis_cache_info" "used_memory")")
    _rc_peak_mb=$(memory_bytes_to_mb_ceil "$(memory_redis_field "$_redis_cache_info" "used_memory_peak")")
    _rc_max_mb=$(memory_bytes_to_mb_ceil "$(memory_redis_field "$_redis_cache_info" "maxmemory")")
    _rf_used_mb=$(memory_bytes_to_mb_ceil "$(memory_redis_field "$_redis_fpc_info" "used_memory")")
    _rf_peak_mb=$(memory_bytes_to_mb_ceil "$(memory_redis_field "$_redis_fpc_info" "used_memory_peak")")
    _rf_max_mb=$(memory_bytes_to_mb_ceil "$(memory_redis_field "$_redis_fpc_info" "maxmemory")")
    _rs_used_mb=$(memory_bytes_to_mb_ceil "$(memory_redis_field "$_redis_session_info" "used_memory")")
    _rs_peak_mb=$(memory_bytes_to_mb_ceil "$(memory_redis_field "$_redis_session_info" "used_memory_peak")")
    _rs_max_mb=$(memory_bytes_to_mb_ceil "$(memory_redis_field "$_redis_session_info" "maxmemory")")

    _es_heap_stats=$(memory_es_heap_stats_mb)
    _es_used_mb=$(echo "$_es_heap_stats" | awk '{print $1}')
    _es_max_mb=$(echo "$_es_heap_stats" | awk '{print $2}')
    _es_cfg_mb=$(memory_env_to_mb "$_cfg_es")
    _es_source="heap_api"
    if ! [[ "$_es_used_mb" =~ ^[0-9]+$ ]]; then
        _es_used_mb=$(memory_mem_usage_to_mb "$_usage_es_container")
        _es_source="container_approx"
    fi
    _es_assigned_mb="$_es_max_mb"
    [ -z "$_es_assigned_mb" ] && _es_assigned_mb="$_es_cfg_mb"
    [ -z "$_es_assigned_mb" ] && _es_source="unknown"
    _es_peak_mb="$_es_used_mb"
    [ -z "$_es_peak_mb" ] && _es_peak_mb="0"

    _rc_ratio=$(memory_usage_ratio_pct "$_rc_used_mb" "$_rc_max_mb")
    _rf_ratio=$(memory_usage_ratio_pct "$_rf_used_mb" "$_rf_max_mb")
    _rs_ratio=$(memory_usage_ratio_pct "$_rs_used_mb" "$_rs_max_mb")
    _es_ratio=$(memory_usage_ratio_pct "$_es_used_mb" "$_es_assigned_mb")
    _rc_alert=$(memory_alert_level "${_rc_ratio:-0}")
    _rf_alert=$(memory_alert_level "${_rf_ratio:-0}")
    _rs_alert=$(memory_alert_level "${_rs_ratio:-0}")
    _es_alert=$(memory_alert_level "${_es_ratio:-0}")

    if [[ "$_host_mb" =~ ^[0-9]+$ ]] && [ "$_show_suggest" = "1" ]; then
        read -r _rc_base _rc_safe _rc_note _rc_peak_ratio <<<"$(memory_redis_recommend "$_rc_used_mb" "$_rc_peak_mb")"
        read -r _rf_base _rf_safe _rf_note _rf_peak_ratio <<<"$(memory_redis_recommend "$_rf_used_mb" "$_rf_peak_mb")"
        read -r _rs_base _rs_safe _rs_note _rs_peak_ratio <<<"$(memory_redis_recommend "$_rs_used_mb" "$_rs_peak_mb")"
        read -r _es_base _es_safe _es_note _es_peak_ratio <<<"$(memory_es_recommend "$_es_used_mb" "$_es_peak_mb")"
        _php_suggest=$(memory_php_suggest_values "$_host_mb")
    else
        _rc_base=""; _rc_safe=""; _rc_note=""; _rc_peak_ratio=""
        _rf_base=""; _rf_safe=""; _rf_note=""; _rf_peak_ratio=""
        _rs_base=""; _rs_safe=""; _rs_note=""; _rs_peak_ratio=""
        _es_base=""; _es_safe=""; _es_note=""; _es_peak_ratio=""
        _php_suggest=""
    fi

    _php_suggest_pm=$(echo "$_php_suggest" | awk -F= '$1=="pm"{print $2}')
    _php_suggest_mc=$(echo "$_php_suggest" | awk -F= '$1=="pm.max_children"{print $2}')
    _php_suggest_ss=$(echo "$_php_suggest" | awk -F= '$1=="pm.start_servers"{print $2}')
    _php_suggest_min=$(echo "$_php_suggest" | awk -F= '$1=="pm.min_spare_servers"{print $2}')
    _php_suggest_max=$(echo "$_php_suggest" | awk -F= '$1=="pm.max_spare_servers"{print $2}')
    _php_suggest_req=$(echo "$_php_suggest" | awk -F= '$1=="pm.max_requests"{print $2}')

    cat <<EOF
{
  "host": {
    "ram_total_mb": "$(memory_json_escape "$_host_mb")",
    "ram_total_human": "$(memory_json_escape "$_host_human")",
    "ram_used_mb": "$(memory_json_escape "$_host_used_mb")",
    "ram_used_pct": "$(memory_json_escape "$_host_used_pct")",
    "load_1m": "$(memory_json_escape "$_host_load_1m")",
    "cores": "$(memory_json_escape "$_host_cores")",
    "cpu_summary": "$(memory_json_escape "$_host_cpu_summary")",
    "physical_cores": "$(memory_json_escape "$_host_cores")",
    "logical_threads": "$(memory_json_escape "$_host_threads")",
    "threads_per_core": "$(memory_json_escape "$_host_threads_per_core")",
    "sockets": "$(memory_json_escape "$_host_sockets")",
    "threads_reserve": "$(memory_json_escape "$_host_threads_reserve")",
    "deploy_threads_suggested": "$(memory_json_escape "$_host_deploy_threads")"
  },
  "usage": {
    "php_container": "$(memory_json_escape "$_usage_php")",
    "mysql_container": "$(memory_json_escape "$_usage_mysql")",
    "elasticsearch_container": "$(memory_json_escape "$_usage_es_container")",
    "redis_cache_container": "$(memory_json_escape "$_usage_rc_container")",
    "redis_fpc_container": "$(memory_json_escape "$_usage_rf_container")",
    "redis_session_container": "$(memory_json_escape "$_usage_rs_container")",
    "redis_cache_used_mb": "$(memory_json_escape "$_rc_used_mb")",
    "redis_cache_peak_mb": "$(memory_json_escape "$_rc_peak_mb")",
    "redis_fpc_used_mb": "$(memory_json_escape "$_rf_used_mb")",
    "redis_fpc_peak_mb": "$(memory_json_escape "$_rf_peak_mb")",
    "redis_session_used_mb": "$(memory_json_escape "$_rs_used_mb")",
    "redis_session_peak_mb": "$(memory_json_escape "$_rs_peak_mb")",
    "elasticsearch_heap_used_mb": "$(memory_json_escape "$_es_used_mb")",
    "elasticsearch_heap_assigned_mb": "$(memory_json_escape "$_es_assigned_mb")",
    "elasticsearch_metrics_source": "$(memory_json_escape "$_es_source")"
  },
  "alerts": {
    "redis_cache": {"level":"$(memory_json_escape "$_rc_alert")","ratio_pct":"$(memory_json_escape "$_rc_ratio")"},
    "redis_fpc": {"level":"$(memory_json_escape "$_rf_alert")","ratio_pct":"$(memory_json_escape "$_rf_ratio")"},
    "redis_session": {"level":"$(memory_json_escape "$_rs_alert")","ratio_pct":"$(memory_json_escape "$_rs_ratio")"},
    "elasticsearch": {"level":"$(memory_json_escape "$_es_alert")","ratio_pct":"$(memory_json_escape "$_es_ratio")"}
  },
  "config": {
    "es_memory": "$(memory_json_escape "$_cfg_es")",
    "redis_cache_maxmemory": "$(memory_json_escape "$_cfg_rc")",
    "redis_cache_policy": "$(memory_json_escape "$_cfg_rcp")",
    "redis_fpc_maxmemory": "$(memory_json_escape "$_cfg_rf")",
    "redis_fpc_policy": "$(memory_json_escape "$_cfg_rfp")",
    "redis_session_maxmemory": "$(memory_json_escape "$_cfg_rs")",
    "redis_session_policy": "$(memory_json_escape "$_cfg_rsp")",
    "php_fpm_conf": "$(memory_json_escape "$_php_conf")",
    "php_fpm_pm": "$(memory_json_escape "$_php_pm")",
    "php_fpm_max_children": "$(memory_json_escape "$_php_mc")",
    "php_fpm_start_servers": "$(memory_json_escape "$_php_ss")",
    "php_fpm_min_spare_servers": "$(memory_json_escape "$_php_min")",
    "php_fpm_max_spare_servers": "$(memory_json_escape "$_php_max")",
    "php_fpm_max_requests": "$(memory_json_escape "$_php_req")"
  },
  "suggested": {
    "enabled": "$(memory_json_escape "$_show_suggest")",
    "es_memory_base_mb": "$(memory_json_escape "$_es_base")",
    "es_memory_safety_min_mb": "$(memory_json_escape "$_es_safe")",
    "es_peak_note": "$(memory_json_escape "$_es_note")",
    "redis_cache_base_mb": "$(memory_json_escape "$_rc_base")",
    "redis_cache_safety_min_mb": "$(memory_json_escape "$_rc_safe")",
    "redis_cache_peak_note": "$(memory_json_escape "$_rc_note")",
    "redis_fpc_base_mb": "$(memory_json_escape "$_rf_base")",
    "redis_fpc_safety_min_mb": "$(memory_json_escape "$_rf_safe")",
    "redis_fpc_peak_note": "$(memory_json_escape "$_rf_note")",
    "redis_session_base_mb": "$(memory_json_escape "$_rs_base")",
    "redis_session_safety_min_mb": "$(memory_json_escape "$_rs_safe")",
    "redis_session_peak_note": "$(memory_json_escape "$_rs_note")",
    "php_fpm_pm": "$(memory_json_escape "$_php_suggest_pm")",
    "php_fpm_max_children": "$(memory_json_escape "$_php_suggest_mc")",
    "php_fpm_start_servers": "$(memory_json_escape "$_php_suggest_ss")",
    "php_fpm_min_spare_servers": "$(memory_json_escape "$_php_suggest_min")",
    "php_fpm_max_spare_servers": "$(memory_json_escape "$_php_suggest_max")",
    "php_fpm_max_requests": "$(memory_json_escape "$_php_suggest_req")"
  }
}
EOF
}

memory_report() {
    local _output="text"
    local _show_suggest="1"

    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help)
                memory_help_usage
                return 0
            ;;
            --json)
                _output="json"
            ;;
            --no-suggest)
                _show_suggest="0"
            ;;
            *)
                warp_message_error "Wrong input: $1"
                memory_help_usage
                return 1
            ;;
        esac
        shift
    done

    MEMORY_PROGRESS=0
    if [ "$_output" = "text" ]; then
        MEMORY_PROGRESS=1
    fi

    if [ "$_output" = "json" ]; then
        memory_report_print_json "$_show_suggest"
    else
        memory_report_print_text "$_show_suggest"
    fi
}

memory_guide() {
    local _php_conf
    _php_conf=$(memory_php_conf_file)
    [ -z "$_php_conf" ] && _php_conf="$PROJECTPATH/.warp/docker/config/php/php-fpm.conf"

    memory_print ""
    memory_print_info "WARP Memory Guide"
    memory_print "Practical reference: where to configure each report parameter (grouped by service)."
    memory_print ""

    memory_print_info "==============================================================================="
    memory_print_info "CACHE (redis / valkey)"
    memory_print_info "==============================================================================="
    memory_print "1) .env (${FCYN}$PROJECTPATH/.env${RS})"
    memory_print "  REDIS_CACHE_MAXMEMORY=<example: 512mb>"
    memory_print "  REDIS_CACHE_MAXMEMORY_POLICY=<allkeys-lru>"
    memory_print "  REDIS_FPC_MAXMEMORY=<example: 512mb>"
    memory_print "  REDIS_FPC_MAXMEMORY_POLICY=<allkeys-lru>"
    memory_print "  REDIS_SESSION_MAXMEMORY=<example: 128mb>"
    memory_print "  REDIS_SESSION_MAXMEMORY_POLICY=<noeviction>"
    memory_print ""
    memory_print "2) docker-compose-warp.yml (${FCYN}$DOCKERCOMPOSEFILE${RS})"
    memory_print "  Services: redis-cache, redis-fpc, redis-session"
    memory_print "  command (example per service):"
    memory_print "    \${CACHE_SERVER_BIN} \${CACHE_CONTAINER_CONFIG_PATH} \\"
    memory_print "      --maxmemory \${REDIS_CACHE_MAXMEMORY} \\"
    memory_print "      --maxmemory-policy \${REDIS_CACHE_MAXMEMORY_POLICY}"
    memory_print "  (Repeat with FPC and SESSION variables in each service)"
    memory_print "  volumes (if you use a custom config):"
    memory_print "    - ./<path>/<redis|valkey>.conf:\${CACHE_CONTAINER_CONFIG_PATH}"
    memory_print ""
    memory_print "3) base config"
    memory_print "  ${FCYN}$PROJECTPATH/.warp/docker/config/redis/redis.conf${RS}"
    memory_print "  ${FCYN}$PROJECTPATH/.warp/setup/redis/config/redis/redis.conf${RS}"
    memory_print "  ${FCYN}$PROJECTPATH/.warp/docker/config/redis/valkey.conf${RS}"
    memory_print "  ${FCYN}$PROJECTPATH/.warp/setup/redis/config/redis/valkey.conf${RS}"
    memory_print "  Common parameters: maxmemory, maxmemory-policy, appendonly"
    memory_print ""

    memory_print_info "==============================================================================="
    memory_print_info "ELASTICSEARCH / OPENSEARCH"
    memory_print_info "==============================================================================="
    memory_print "1) .env (${FCYN}$PROJECTPATH/.env${RS})"
    memory_print "  SEARCH_ENGINE=<opensearch|elasticsearch>"
    memory_print "  ES_VERSION=<example: 2.12.0>"
    memory_print "  ES_MEMORY=<example: 1024m>"
    memory_print "  ES_PASSWORD=<password>"
    memory_print ""
    memory_print "2) docker-compose-warp.yml (${FCYN}$DOCKERCOMPOSEFILE${RS})"
    memory_print "  Service: elasticsearch (or opensearch if applicable)"
    memory_print "  environment:"
    memory_print "    - ES_JAVA_OPTS=-Xms\${ES_MEMORY} -Xmx\${ES_MEMORY}"
    memory_print "    - OPENSEARCH_JAVA_OPTS=-Xms\${ES_MEMORY} -Xmx\${ES_MEMORY}"
    memory_print "    - OPENSEARCH_INITIAL_ADMIN_PASSWORD=\${ES_PASSWORD}"
    memory_print ""

    memory_print_info "==============================================================================="
    memory_print_info "PHP-FPM"
    memory_print_info "==============================================================================="
    memory_print "1) php-fpm.conf (${FCYN}${_php_conf}${RS})"
    memory_print "  Key parameters:"
    memory_print "  pm=dynamic"
    memory_print "  pm.max_children=<value>"
    memory_print "  pm.start_servers=<value>"
    memory_print "  pm.min_spare_servers=<value>"
    memory_print "  pm.max_spare_servers=<value>"
    memory_print "  pm.max_requests=<value>"
    memory_print ""

    memory_print_info "==============================================================================="
    memory_print_info "MYSQL / MARIADB (TUNING RECOMMENDATION)"
    memory_print_info "==============================================================================="
    memory_print "MySQLTuner (https://github.com/major/MySQLTuner-perl): Perl script that checks"
    memory_print "MySQL/MariaDB configuration and status and suggests performance/stability adjustments."
    memory_print ""
    memory_print "Recommended:"
    memory_print "  warp db tuner"
    memory_print "  (downloads mysqltuner.pl into ./var or /tmp, validates perl and tries distro installation)"
    memory_print ""
    memory_print "Example with extra options:"
    memory_print "  warp db tuner --skipsize --nocolor"
    memory_print ""

    memory_print_info "Quick note"
    memory_print " - 'warp telemetry scan' measures current usage and suggests values."
    memory_print " - 'warp telemetry config' only shows where to edit each parameter."
    memory_print ""
}

# Command contract renamed to `warp telemetry`.
# The implementation remains in memory.sh to keep internal layout stable.
telemetry_main() {
    case "$1" in
        ""|scan)
            [ "$1" = "scan" ] && shift
            memory_report "$@"
        ;;
        config)
            shift
            memory_guide "$@"
        ;;
        -h|--help)
            memory_help_usage
        ;;
        *)
            memory_help_usage
            return 1
        ;;
    esac
}
