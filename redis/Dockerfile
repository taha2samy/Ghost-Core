FROM cgr.dev/chainguard/wolfi-base AS builder

ARG REDIS_VERSION
ARG REDIS_SHA256

RUN apk add --no-cache \
    build-base pkgconf wget openssl-dev linux-headers \
    coreutils gd-dev libxml2-dev binutils scanelf posix-libc-utils bash \
    tzdata ca-certificates

COPY scripts/extract_libs.sh /usr/bin/extract_libs.sh
COPY redis/build.sh /usr/bin/build_redis.sh
COPY redis/src/redis-init.c /usr/src/redis-init.c
COPY redis/config/redis.conf /tmp/redis.conf

RUN chmod +x /usr/bin/build_redis.sh /usr/bin/extract_libs.sh

RUN build_redis.sh "${REDIS_VERSION}" "${REDIS_SHA256}"

RUN extract_libs.sh \
    /rootfs/usr/bin/redis-server \
    /rootfs/usr/bin/redis-cli \
    /rootfs/usr/bin/redis-benchmark \
    /rootfs/usr/bin/redis-check-aof \
    /rootfs/usr/bin/redis-check-rdb \
    /rootfs/usr/bin/redis-sentinel \
    /rootfs/usr/bin/redis-init

RUN mkdir -p /rootfs/data /rootfs/var/run /rootfs/tmp \
    && chown -R 999:999 /rootfs/data /rootfs/var/run /rootfs/tmp /rootfs/usr/local/etc/redis \
    && chmod 1777 /rootfs/tmp

# ==========================================
# Final Stage
# ==========================================
FROM cgr.dev/chainguard/static:latest AS final

ARG REDIS_VERSION
ARG VCS_REF
ARG BUILD_DATE

LABEL org.opencontainers.image.title="Ghost Core Redis"
LABEL org.opencontainers.image.description="Secure Redis ${REDIS_VERSION}"
LABEL org.opencontainers.image.version="${REDIS_VERSION}"
LABEL org.opencontainers.image.revision="${VCS_REF}"
LABEL org.opencontainers.image.created="${BUILD_DATE}"
LABEL org.opencontainers.image.vendor="Taha2Samy"

COPY --from=builder /rootfs/etc/passwd /etc/passwd
COPY --from=builder /rootfs/etc/group /etc/group
COPY --from=builder /rootfs/etc/ld.so.cache /etc/ld.so.cache

COPY --from=builder /usr/share/zoneinfo /usr/share/zoneinfo
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/

COPY --from=builder /rootfs/usr/bin/ /usr/bin/
COPY --from=builder --chown=999:999 /rootfs/usr/local/etc/redis /usr/local/etc/redis
COPY --from=builder /rootfs/usr/lib/ /usr/lib/

COPY --from=builder --chown=999:999 /rootfs/data /data
COPY --from=builder --chown=999:999 /rootfs/var/run /var/run
COPY --from=builder --chown=999:999 /rootfs/tmp /tmp

VOLUME /data
WORKDIR /data
EXPOSE 6379

USER 999

ENTRYPOINT ["/usr/bin/redis-init"]
CMD ["/usr/local/etc/redis/redis.conf"]

# ==========================================
# Dev Stage
# ==========================================
FROM cgr.dev/chainguard/wolfi-base:latest AS dev

RUN apk add --no-cache bash curl vim tree bind-tools

COPY --from=builder /rootfs/etc/passwd /etc/passwd
COPY --from=builder /rootfs/etc/group /etc/group
COPY --from=builder /rootfs/etc/ld.so.cache /etc/ld.so.cache

COPY --from=builder /usr/share/zoneinfo /usr/share/zoneinfo
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/

COPY --from=builder /rootfs/usr/bin/ /usr/bin/
COPY --from=builder --chown=999:999 /rootfs/usr/local/etc/redis /usr/local/etc/redis
COPY --from=builder /rootfs/usr/lib/ /usr/lib/

COPY --from=builder --chown=999:999 /rootfs/data /data
COPY --from=builder --chown=999:999 /rootfs/var/run /var/run
COPY --from=builder --chown=999:999 /rootfs/tmp /tmp

VOLUME /data
WORKDIR /data
EXPOSE 6379

USER 999

ENTRYPOINT ["/usr/bin/redis-init"]
CMD ["/usr/local/etc/redis/redis.conf"]