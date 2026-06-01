#!/bin/sh
set -eu

if [ ! -f /etc/rsyncd.conf ]; then
    cat > /etc/rsyncd.conf <<'EOF'
uid = root
gid = root
use chroot = yes
log file = /dev/stdout
reverse lookup = no
[warp]
    hosts allow = *
    read only = false
    path = /var/www/html
    comment = docker volume
EOF
fi

if [ ! -d /var/www/html ]; then
    mkdir -p /var/www/html
fi

rsync --daemon --config /etc/rsyncd.conf

exec "$@"
