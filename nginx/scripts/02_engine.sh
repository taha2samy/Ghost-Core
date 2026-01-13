wget -qO nginx.tar.gz "http://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz"
if [ -n "$NGINX_SHA256" ]; then echo "$NGINX_SHA256  nginx.tar.gz" | sha256sum -c -; fi
tar -xzf nginx.tar.gz
cd nginx-${NGINX_VERSION}

./configure "$@" || { echo "Configure Failed"; cat objs/autoconf.err; exit 1; }

make -j"$(nproc)"
make install DESTDIR=/rootfs

strip /rootfs/usr/sbin/nginx
find /rootfs/usr/lib/nginx/modules -name "*.so" -exec strip {} \;