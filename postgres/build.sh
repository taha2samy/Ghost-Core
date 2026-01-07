#!/bin/bash
set -e

PG_VERSION=$1
PG_SHA256=$2

check_hash() {
    local file=$1
    local hash=$2
    if [ -n "$hash" ]; then
        echo "$hash  $file" | sha256sum -c -
    fi
}

mkdir -p /rootfs/usr/bin /rootfs/usr/lib /rootfs/usr/local/etc/postgres \
         /rootfs/var/lib/postgresql/data /rootfs/var/run/postgresql /rootfs/tmp \
         /rootfs/usr/share/postgresql /rootfs/etc

echo 'root:x:0:0:root:/root:/sbin/nologin' > /rootfs/etc/passwd
echo 'postgres:x:999:999:PostgreSQL:/var/lib/postgresql:/sbin/nologin' >> /rootfs/etc/passwd
echo 'root:x:0:' > /rootfs/etc/group
echo 'postgres:x:999:' >> /rootfs/etc/group

URL="https://ftp.postgresql.org/pub/source/v${PG_VERSION}/postgresql-${PG_VERSION}.tar.gz"

echo ">>> Downloading PostgreSQL v${PG_VERSION} from ${URL}..."
wget -qO postgres.tar.gz "$URL"
check_hash "postgres.tar.gz" "$PG_SHA256"

mkdir -p /usr/src/postgres
tar -xzf postgres.tar.gz -C /usr/src/postgres --strip-components=1
rm postgres.tar.gz

cd /usr/src/postgres

# لاحظ: رجعنا --with-icu لأننا هننسخ ملفاتها خلاص
./configure \
    --prefix=/usr \
    --disable-rpath \
    --without-perl \
    --without-python \
    --without-tcl \
    --without-pam \
    --without-readline \
    --with-openssl \
    --with-libxml \
    --with-icu \
    --with-system-tzdata=/usr/share/zoneinfo

echo ">>> Compiling PostgreSQL Core..."
make -j "$(nproc)"

echo ">>> Compiling PostgreSQL Contrib (Extensions)..."
make -C contrib -j "$(nproc)"

echo ">>> Installing..."
make install DESTDIR=/tmp/pg_install
make -C contrib install DESTDIR=/tmp/pg_install

# Copy Binaries
cp /tmp/pg_install/usr/bin/postgres /rootfs/usr/bin/
cp /tmp/pg_install/usr/bin/initdb /rootfs/usr/bin/
cp /tmp/pg_install/usr/bin/pg_ctl /rootfs/usr/bin/
cp /tmp/pg_install/usr/bin/psql /rootfs/usr/bin/

# Copy Libs (Internal Postgres libs)
cp -r /tmp/pg_install/usr/lib/* /rootfs/usr/lib/

# Copy Share (Errors, Timezones, etc)
cp -r /tmp/pg_install/usr/share/postgresql/* /rootfs/usr/share/postgresql/

# [NEW] Copy ICU Data (Fixes U_FILE_ACCESS_ERROR)
echo ">>> Copying ICU Data files..."
mkdir -p /rootfs/usr/share/icu
if [ -d /usr/share/icu ]; then
    cp -r /usr/share/icu/* /rootfs/usr/share/icu/
fi

# Strip to reduce size
strip /rootfs/usr/bin/* 2>/dev/null || true
strip --strip-unneeded /rootfs/usr/lib/*.so 2>/dev/null || true
strip --strip-unneeded /rootfs/usr/lib/postgresql/*.so 2>/dev/null || true

# Configs
cp /tmp/postgresql.conf /rootfs/usr/local/etc/postgres/postgresql.conf
cp /tmp/pg_hba.conf /rootfs/usr/local/etc/postgres/pg_hba.conf

# Build Init
gcc -O2 -static -o /rootfs/usr/bin/postgres-init /usr/src/postgres-init.c
strip /rootfs/usr/bin/postgres-init

rm -rf /usr/src/postgres /tmp/pg_install