#!/bin/bash
set -e

REDIS_VERSION=$1
REDIS_SHA256=$2
BUILD_TARGETS=$3
MEMORY_ALLOCATOR=$4

if [ -z "$BUILD_TARGETS" ] || [ -z "$MEMORY_ALLOCATOR" ]; then
    echo "Error: Missing arguments."
    exit 1
fi

echo ">>> BUILDING: Targets=['$BUILD_TARGETS'] | Allocator=['$MEMORY_ALLOCATOR'] <<<"

mkdir -p /rootfs/usr/bin /rootfs/usr/local/etc/redis /rootfs/etc
echo 'root:x:0:0:root:/root:/sbin/nologin' > /rootfs/etc/passwd
echo 'redis:x:999:999:redis:/data:/sbin/nologin' >> /rootfs/etc/passwd
echo 'root:x:0:' > /rootfs/etc/group
echo 'redis:x:999:' >> /rootfs/etc/group

wget -qO redis.tar.gz "https://github.com/redis/redis/archive/refs/tags/${REDIS_VERSION}.tar.gz"
if [ -n "$REDIS_SHA256" ]; then
    echo "$REDIS_SHA256  redis.tar.gz" | sha256sum -c -
fi
mkdir -p /usr/src/redis
tar -xzf redis.tar.gz -C /usr/src/redis --strip-components=1
rm redis.tar.gz

if [ "$MEMORY_ALLOCATOR" = "jemalloc" ] && [ -f /usr/src/redis/deps/jemalloc/include/jemalloc/internal/util.h ]; then
    sed -i 's/^#define unreachable() JEMALLOC_INTERNAL_UNREACHABLE()/#ifndef unreachable\n#define unreachable() JEMALLOC_INTERNAL_UNREACHABLE()\n#endif/' \
        /usr/src/redis/deps/jemalloc/include/jemalloc/internal/util.h
fi

export OPTIMIZATION="-O2"
export CFLAGS="${OPTIMIZATION} -fstack-protector-strong -Wformat -Werror=format-security -fPIE -D_FORTIFY_SOURCE=2 -Wno-error -Wno-array-bounds -Wno-maybe-uninitialized -Wno-alloc-size-larger-than"
export LDFLAGS="-Wl,-z,relro -Wl,-z,now -fPIE -pie"

for target in $BUILD_TARGETS; do
    echo "--- Building target: $target ---"
    make -C /usr/src/redis -j "$(nproc)" \
        BUILD_TLS=yes \
        MALLOC="$MEMORY_ALLOCATOR" \
        DISABLE_INTERNAL_MODULES=yes \
        CFLAGS="$CFLAGS" \
        LDFLAGS="$LDFLAGS" \
        "$target"
        
    echo "Installing $target..."
    cp "/usr/src/redis/src/$target" /rootfs/usr/bin/
done

scanelf --nobanner -E ET_DYN,ET_EXEC /rootfs/usr/bin/* \
| awk '{print $2}' \
| xargs -r strip --strip-unneeded

rm -rf /usr/src/redis
echo ">>> BUILD COMPLETE <<<"