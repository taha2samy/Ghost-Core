FROM cgr.dev/chainguard/wolfi-base AS builder

ARG NGINX_VERSION
ARG NGINX_SHA256

ARG BUILD_MODE="core"

RUN apk add --no-cache \
    build-base pkgconf wget openssl-dev pcre-dev zlib-dev linux-headers \
    coreutils gd-dev libxml2-dev libxslt-dev geoip-dev libmaxminddb-dev \
    binutils scanelf posix-libc-utils bash tzdata ca-certificates perl perl-dev


RUN ln -sf /usr/lib/libz.so.1 /usr/lib/libz.so

COPY scripts/extract_libs.sh /usr/bin/extract_libs.sh
COPY nginx/build.sh /usr/bin/build_nginx.sh
RUN chmod +x /usr/bin/build_nginx.sh /usr/bin/extract_libs.sh
COPY nginx/modules.conf /modules.conf
COPY nginx/profiles.conf /profiles.conf
COPY nginx/scripts/ /usr/bin/scripts/

RUN chmod -R +x /usr/bin/scripts/

RUN build_nginx.sh "${NGINX_VERSION}" "${NGINX_SHA256}" "${BUILD_MODE}" ""

RUN /bin/bash -c "extract_libs.sh /rootfs/usr/sbin/nginx /rootfs/usr/lib/nginx/modules/*.so"


RUN mkdir -p /rootfs/var/log/nginx /rootfs/var/cache/nginx /rootfs/var/run /rootfs/tmp /rootfs/etc \
    && chown -R 101:101 /rootfs/var/log/nginx /rootfs/var/cache/nginx /rootfs/var/run /rootfs/tmp \
    && chmod 1777 /rootfs/tmp \
    && echo 'hosts: files dns' > /rootfs/etc/nsswitch.conf


FROM cgr.dev/chainguard/static:latest AS final

ARG NGINX_VERSION
ARG VCS_REF
ARG BUILD_DATE
ARG CONFIG_FILE=nginx.conf

LABEL org.opencontainers.image.title="Ghost Core (Distroless)"
LABEL org.opencontainers.image.description="Secure Nginx ${NGINX_VERSION}"
LABEL org.opencontainers.image.version="${NGINX_VERSION}"
LABEL org.opencontainers.image.revision="${VCS_REF}"
LABEL org.opencontainers.image.created="${BUILD_DATE}"
LABEL org.opencontainers.image.vendor="Taha2Samy"

COPY --from=builder /rootfs/etc/passwd /etc/passwd
COPY --from=builder /rootfs/etc/group /etc/group
COPY --from=builder /rootfs/etc/nsswitch.conf /etc/nsswitch.conf
COPY --from=builder /rootfs/etc/ld.so.cache /etc/ld.so.cache

COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/

COPY --from=builder /rootfs/usr/sbin/nginx /usr/sbin/nginx
COPY --from=builder /rootfs/etc/nginx /etc/nginx
COPY --from=builder /rootfs/usr/lib/ /usr/lib/
COPY --from=builder /rootfs/usr/share/ /usr/share/
COPY --from=builder /rootfs/usr/local/lib/ /usr/local/lib
COPY --from=builder --chown=101:101 /rootfs/var/log/nginx /var/log/nginx
COPY --from=builder --chown=101:101 /rootfs/var/cache/nginx /var/cache/nginx
COPY --from=builder --chown=101:101 /rootfs/var/run /var/run
COPY --from=builder --chown=101:101 /rootfs/tmp /tmp

COPY --chown=101:101 nginx/static /usr/share/nginx/html
COPY --chown=101:101 nginx/config/mime.types /etc/nginx/mime.types
COPY --chown=101:101 nginx/config/conf.d/ /etc/nginx/conf.d/
COPY --chown=101:101 nginx/config/${CONFIG_FILE} /etc/nginx/nginx.conf

EXPOSE 8080
STOPSIGNAL SIGQUIT
USER 101

CMD ["nginx", "-g", "daemon off;", "-e", "/var/log/nginx/error.log"]

FROM cgr.dev/chainguard/wolfi-base:latest AS dev

ARG CONFIG_FILE=nginx.conf

RUN apk add --no-cache bash curl vim tree bind-tools

COPY --from=builder /rootfs/etc/passwd /etc/passwd
COPY --from=builder /rootfs/etc/group /etc/group
COPY --from=builder /rootfs/etc/nsswitch.conf /etc/nsswitch.conf
COPY --from=builder /rootfs/etc/ld.so.cache /etc/ld.so.cache

COPY --from=builder /usr/share/zoneinfo /usr/share/zoneinfo
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/

COPY --from=builder /rootfs/usr/sbin/nginx /usr/sbin/nginx
COPY --from=builder /rootfs/etc/nginx /etc/nginx
COPY --from=builder /rootfs/usr/lib/ /usr/lib/

COPY --from=builder /rootfs/usr/lib/ /usr/lib/
COPY --from=builder /rootfs/usr/share/ /usr/share/
COPY --from=builder /rootfs/usr/local/lib/ /usr/local/lib

COPY --from=builder --chown=101:101 /rootfs/var/log/nginx /var/log/nginx
COPY --from=builder --chown=101:101 /rootfs/var/cache/nginx /var/cache/nginx
COPY --from=builder --chown=101:101 /rootfs/var/run /var/run
COPY --from=builder --chown=101:101 /rootfs/tmp /tmp


COPY --chown=101:101 nginx/static /usr/share/nginx/html
COPY --chown=101:101 nginx/config/mime.types /etc/nginx/mime.types
COPY --chown=101:101 nginx/config/conf.d/ /etc/nginx/conf.d/
COPY --chown=101:101 nginx/config/${CONFIG_FILE} /etc/nginx/nginx.conf


EXPOSE 8080
STOPSIGNAL SIGQUIT
USER 101

CMD ["nginx", "-g", "daemon off;", "-e", "/var/log/nginx/error.log"]
