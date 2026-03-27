#!/bin/bash

warp_host_lscpu_field() {
    local _field="$1"
    command -v lscpu >/dev/null 2>&1 || return 1

    lscpu 2>/dev/null | awk -F: -v key="$_field" '
        {
            label=$1
            sub(/^[[:space:]]+/, "", label)
            sub(/[[:space:]]+$/, "", label)
            if (label != key) {
                next
            }
            val=$2
            sub(/^[[:space:]]+/, "", val)
            sub(/[[:space:]]+$/, "", val)
            print val
            exit
        }
    '
}

warp_host_threads_reserve_default() {
    if [[ "$WARP_HOST_THREADS_RESERVE_DEFAULT" =~ ^[0-9]+$ ]]; then
        echo "$WARP_HOST_THREADS_RESERVE_DEFAULT"
    else
        echo "1"
    fi
}

warp_host_threads_reserve() {
    local _reserve=""
    local _default=""

    _default=$(warp_host_threads_reserve_default)

    if [ -f "$ENVIRONMENTVARIABLESFILE" ]; then
        warp_env_ensure_var "WARP_HOST_THREADS_RESERVE" "$_default" >/dev/null 2>&1 || true
        _reserve=$(warp_env_read_var "WARP_HOST_THREADS_RESERVE")
    fi

    if ! [[ "$_reserve" =~ ^[0-9]+$ ]]; then
        _reserve="$_default"
    fi

    echo "$_reserve"
}

warp_host_cpu_logical() {
    local _value=""

    if command -v nproc >/dev/null 2>&1; then
        _value=$(nproc 2>/dev/null)
    elif command -v getconf >/dev/null 2>&1; then
        _value=$(getconf _NPROCESSORS_ONLN 2>/dev/null)
    elif command -v sysctl >/dev/null 2>&1; then
        _value=$(sysctl -n hw.logicalcpu 2>/dev/null)
        [ -z "$_value" ] && _value=$(sysctl -n hw.ncpu 2>/dev/null)
    fi

    if ! [[ "$_value" =~ ^[0-9]+$ ]]; then
        _value=$(warp_host_lscpu_field "CPU(s)")
    fi

    if [[ "$_value" =~ ^[0-9]+$ ]] && [ "$_value" -gt 0 ]; then
        echo "$_value"
    fi
}

warp_host_cpu_sockets() {
    local _value=""

    _value=$(warp_host_lscpu_field "Socket(s)")
    if ! [[ "$_value" =~ ^[0-9]+$ ]] && command -v sysctl >/dev/null 2>&1; then
        _value=$(sysctl -n hw.packages 2>/dev/null)
    fi

    if [[ "$_value" =~ ^[0-9]+$ ]] && [ "$_value" -gt 0 ]; then
        echo "$_value"
    fi
}

warp_host_cpu_cores_per_socket() {
    local _value=""

    _value=$(warp_host_lscpu_field "Core(s) per socket")
    if [[ "$_value" =~ ^[0-9]+$ ]] && [ "$_value" -gt 0 ]; then
        echo "$_value"
    fi
}

warp_host_cpu_threads_per_core() {
    local _value=""
    local _logical=""
    local _physical=""

    _value=$(warp_host_lscpu_field "Thread(s) per core")
    if ! [[ "$_value" =~ ^[0-9]+$ ]] && command -v sysctl >/dev/null 2>&1; then
        _logical=$(sysctl -n hw.logicalcpu 2>/dev/null)
        _physical=$(sysctl -n hw.physicalcpu 2>/dev/null)
        if [[ "$_logical" =~ ^[0-9]+$ ]] && [[ "$_physical" =~ ^[0-9]+$ ]] && [ "$_logical" -ge "$_physical" ] && [ "$_physical" -gt 0 ]; then
            _value=$(( _logical / _physical ))
        fi
    fi

    if ! [[ "$_value" =~ ^[0-9]+$ ]]; then
        _logical=$(warp_host_cpu_logical)
        _physical=$(warp_host_cpu_physical)
        if [[ "$_logical" =~ ^[0-9]+$ ]] && [[ "$_physical" =~ ^[0-9]+$ ]] && [ "$_logical" -ge "$_physical" ] && [ "$_physical" -gt 0 ]; then
            _value=$(( _logical / _physical ))
        fi
    fi

    if [[ "$_value" =~ ^[0-9]+$ ]] && [ "$_value" -gt 0 ]; then
        echo "$_value"
    fi
}

warp_host_cpu_physical() {
    local _cores_per_socket=""
    local _sockets=""
    local _value=""

    _cores_per_socket=$(warp_host_cpu_cores_per_socket)
    _sockets=$(warp_host_cpu_sockets)
    if [[ "$_cores_per_socket" =~ ^[0-9]+$ ]] && [[ "$_sockets" =~ ^[0-9]+$ ]]; then
        _value=$(( _cores_per_socket * _sockets ))
    fi

    if ! [[ "$_value" =~ ^[0-9]+$ ]] && command -v sysctl >/dev/null 2>&1; then
        _value=$(sysctl -n hw.physicalcpu 2>/dev/null)
    fi

    if [[ "$_value" =~ ^[0-9]+$ ]] && [ "$_value" -gt 0 ]; then
        echo "$_value"
    fi
}

warp_host_cpu_topology_summary() {
    local _logical=""
    local _physical=""
    local _threads_per_core=""
    local _sockets=""
    local _parts=""

    _logical=$(warp_host_cpu_logical)
    _physical=$(warp_host_cpu_physical)
    _threads_per_core=$(warp_host_cpu_threads_per_core)
    _sockets=$(warp_host_cpu_sockets)

    if [[ "$_sockets" =~ ^[0-9]+$ ]]; then
        _parts="${_sockets} socket"
        [ "$_sockets" -ne 1 ] && _parts="${_parts}s"
    fi
    if [[ "$_physical" =~ ^[0-9]+$ ]]; then
        [ -n "$_parts" ] && _parts="${_parts}, "
        _parts="${_parts}${_physical} physical core"
        [ "$_physical" -ne 1 ] && _parts="${_parts}s"
    fi
    if [[ "$_logical" =~ ^[0-9]+$ ]]; then
        [ -n "$_parts" ] && _parts="${_parts}, "
        _parts="${_parts}${_logical} logical thread"
        [ "$_logical" -ne 1 ] && _parts="${_parts}s"
    fi
    if [[ "$_threads_per_core" =~ ^[0-9]+$ ]]; then
        [ -n "$_parts" ] && _parts="${_parts} "
        _parts="${_parts}(${_threads_per_core} thread"
        [ "$_threads_per_core" -ne 1 ] && _parts="${_parts}s"
        _parts="${_parts}/core)"
    fi

    echo "$_parts"
}

warp_host_worker_threads_default() {
    local _logical=""
    local _reserve=""
    local _threads=""

    _logical=$(warp_host_cpu_logical)
    if ! [[ "$_logical" =~ ^[0-9]+$ ]] || [ "$_logical" -lt 1 ]; then
        _logical=4
    fi

    _reserve=$(warp_host_threads_reserve)
    if ! [[ "$_reserve" =~ ^[0-9]+$ ]]; then
        _reserve=$(warp_host_threads_reserve_default)
    fi

    _threads=$(( _logical - _reserve ))
    [ "$_threads" -lt 1 ] && _threads=1
    echo "$_threads"
}
