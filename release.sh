#!/bin/bash


COMMIT_VERSION=`git rev-parse --short HEAD`
BUILD_VERSION=`date +%Y.%m.%d`
TAG_VERSIONS=`git tag -l | sort -r`


cat release/commit.sh.template | sed -e "s/COMMIT_VERSION/${COMMIT_VERSION}/" > .warp/lib/commit.sh
cat release/version.sh.template | sed -e "s/BUILD_VERSION/${BUILD_VERSION}/" > .warp/lib/version.sh

mkdir -p dist
printf "%s\n" "$BUILD_VERSION" > dist/version.md

# Crea el compilado ejecutable:
#
# cat warp.sh warparchive.tar.xz > warp
#
tar cJf warparchive.tar.xz --exclude=".DS_Store" .warp/.
sed -e "s/__BUILD_VERSION__/${BUILD_VERSION}/g" warp.sh > dist/warp
cat warparchive.tar.xz >> dist/warp
chmod +x dist/warp
cp dist/warp dist/warp_$BUILD_VERSION

if command -v sha256sum >/dev/null 2>&1; then
    sha256sum dist/warp | awk '{print $1}' > dist/sha256sum.md
elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 dist/warp | awk '{print $1}' > dist/sha256sum.md
elif command -v openssl >/dev/null 2>&1; then
    openssl dgst -sha256 dist/warp | awk '{print $NF}' > dist/sha256sum.md
else
    echo "No SHA256 tool found (sha256sum/shasum/openssl)." >&2
    exit 1
fi

# OUTPUT dist/warp
