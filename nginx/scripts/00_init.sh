mkdir -p /rootfs/usr/sbin \
         /rootfs/usr/lib/nginx/modules \
         /rootfs/etc/nginx \
         /rootfs/var/log/nginx \
         /rootfs/var/cache/nginx \
         /rootfs/var/run \
         /rootfs/usr/local/lib \
         /rootfs/usr/share

mkdir -p /src/modules

echo 'nginx:x:101:101:nginx:/var/cache/nginx:/sbin/nologin' >> /rootfs/etc/passwd
echo 'nginx:x:101:' >> /rootfs/etc/group

ZLIB_CFLAGS=$(pkg-config --cflags zlib)
ZLIB_LDFLAGS=$(pkg-config --libs zlib)
HARDENING_CFLAGS="-fstack-protector-strong -D_FORTIFY_SOURCE=2 -fPIC"
HARDENING_LDFLAGS="-Wl,-z,relro -Wl,-z,now -fPIC"
CC_OPT="-Wno-error $ZLIB_CFLAGS $HARDENING_CFLAGS"
LD_OPT="$ZLIB_LDFLAGS $HARDENING_LDFLAGS"

set -- \
    --prefix=/etc/nginx \
    --sbin-path=/usr/sbin/nginx \
    --modules-path=/usr/lib/nginx/modules \
    --conf-path=/etc/nginx/nginx.conf \
    --user=nginx --group=nginx \
    --with-compat --with-file-aio --with-threads \
    --with-http_ssl_module --with-http_v2_module --with-http_realip_module \
    --with-http_gunzip_module --with-http_gzip_static_module --with-http_stub_status_module \
    --with-cc-opt="$CC_OPT" \
    --with-ld-opt="$LD_OPT"