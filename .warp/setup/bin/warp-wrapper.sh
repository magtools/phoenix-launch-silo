#!/usr/bin/env bash

if [ -x "./warp" ]; then
    exec ./warp "$@"
fi

if [ -f "./warp.sh" ]; then
    exec bash ./warp.sh "$@"
fi

echo "warp wrapper: ./warp or ./warp.sh not found in current directory" >&2
exit 1
