#!/bin/bash
set -e

REDIS_VERSION=$1
REDIS_SHA256=$2

check_hash() {
    local file=$1
    local hash=$2
    if [ -n "$hash" ]; then
        echo "$hash  $file" | sha256sum -c -
    fi
}

mkdir -p /rootfs/usr/bin /rootfs/usr/local/etc/redis /rootfs/etc

echo 'root:x:0:0:root:/root:/sbin/nologin' > /rootfs/etc/passwd
echo 'redis:x:999:999:redis:/data:/sbin/nologin' >> /rootfs/etc/passwd
echo 'root:x:0:' > /rootfs/etc/group
echo 'redis:x:999:' >> /rootfs/etc/group

wget -qO redis.tar.gz "https://github.com/redis/redis/archive/refs/tags/${REDIS_VERSION}.tar.gz"
check_hash "redis.tar.gz" "$REDIS_SHA256"
mkdir -p /usr/src/redis
tar -xzf redis.tar.gz -C /usr/src/redis --strip-components=1
rm redis.tar.gz

make -C /usr/src/redis -j "$(nproc)" BUILD_TLS=yes MALLOC=libc all

cp /usr/src/redis/src/redis-server /rootfs/usr/bin/
cp /usr/src/redis/src/redis-cli /rootfs/usr/bin/
cp /usr/src/redis/src/redis-benchmark /rootfs/usr/bin/
cp /usr/src/redis/src/redis-check-aof /rootfs/usr/bin/
cp /usr/src/redis/src/redis-check-rdb /rootfs/usr/bin/
cp /usr/src/redis/src/redis-sentinel /rootfs/usr/bin/
strip /rootfs/usr/bin/*

cp /tmp/redis.conf /rootfs/usr/local/etc/redis/redis.conf

gcc -O2 -static -o /rootfs/usr/bin/redis-init /usr/src/redis-init.c
strip /rootfs/usr/bin/redis-init

rm -rf /usr/src/redis