#!/bin/bash

WARP_BINARY_FILE=$1
WARP_WRAPPER_TEMPLATE=$2

if [ -z "$WARP_BINARY_FILE" ] || [ -z "$WARP_WRAPPER_TEMPLATE" ]; then
    echo "usage: binary.sh <target> <warp-wrapper-template>" >&2
    exit 1
fi

if [ ! -f "$WARP_WRAPPER_TEMPLATE" ]; then
    echo "warp wrapper template not found: $WARP_WRAPPER_TEMPLATE" >&2
    exit 1
fi

cp "$WARP_WRAPPER_TEMPLATE" "$WARP_BINARY_FILE"
chmod 755 "$WARP_BINARY_FILE"

if ! cmp -s "$WARP_WRAPPER_TEMPLATE" "$WARP_BINARY_FILE"; then
    echo "warp wrapper install verification failed: $WARP_BINARY_FILE" >&2
    exit 1
fi
