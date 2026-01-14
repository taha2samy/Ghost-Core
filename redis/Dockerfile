# ==============================================================================
# BASE BUILDER: Prepare environment, scripts, and common dependencies
# ==============================================================================
FROM cgr.dev/chainguard/wolfi-base AS base-builder

ARG REDIS_VERSION
ARG REDIS_SHA256

# Install build dependencies and jemalloc
RUN apk add --no-cache \
    build-base pkgconf wget openssl-dev linux-headers \
    coreutils gd-dev libxml2-dev binutils scanelf posix-libc-utils bash \
    tzdata ca-certificates jemalloc jemalloc-dev

# Copy scripts and configs
COPY scripts/extract_libs.sh /usr/bin/extract_libs.sh
COPY redis/build.sh /usr/bin/build_redis.sh
COPY redis/src/redis-init.c /usr/src/redis-init.c

RUN chmod +x /usr/bin/build_redis.sh /usr/bin/extract_libs.sh

# ==============================================================================
# STAGE 1: SERVER BUILDER (High Performance / JEMALLOC)
# ==============================================================================
FROM base-builder AS server-builder
ARG REDIS_VERSION
ARG REDIS_SHA256

# Build ONLY redis-server using jemalloc
# Args: Version, Hash, Target(s), Allocator
RUN build_redis.sh "${REDIS_VERSION}" "${REDIS_SHA256}" "redis-server" "jemalloc"

# ==============================================================================
# STAGE 2: TOOLS BUILDER (High Compatibility / LIBC)
# ==============================================================================
FROM base-builder AS tools-builder
ARG REDIS_VERSION
ARG REDIS_SHA256

# Build tools using standard libc to avoid linking errors
# Args: Version, Hash, Target(s), Allocator
RUN build_redis.sh "${REDIS_VERSION}" "${REDIS_SHA256}" "redis-cli redis-benchmark redis-check-aof redis-check-rdb redis-sentinel" "libc"

# ==============================================================================
# STAGE 3: ASSEMBLER & SCAVENGER
# Collect binaries and extract required libraries
# ==============================================================================
FROM base-builder AS assembler

# 1. Collect Binaries
COPY --from=server-builder /rootfs/usr/bin/redis-server /rootfs/usr/bin/
COPY --from=server-builder /rootfs/etc /rootfs/etc
COPY --from=server-builder /rootfs/usr/local/etc/redis /rootfs/usr/local/etc/redis

COPY --from=tools-builder /rootfs/usr/bin/redis-cli /rootfs/usr/bin/
COPY --from=tools-builder /rootfs/usr/bin/redis-benchmark /rootfs/usr/bin/
COPY --from=tools-builder /rootfs/usr/bin/redis-check-aof /rootfs/usr/bin/
COPY --from=tools-builder /rootfs/usr/bin/redis-check-rdb /rootfs/usr/bin/
COPY --from=tools-builder /rootfs/usr/bin/redis-sentinel /rootfs/usr/bin/

# 2. Setup Directories & Permissions
RUN mkdir -p /rootfs/data /rootfs/var/run /rootfs/tmp \
    && chown -R 999:999 /rootfs/data /rootfs/var/run /rootfs/tmp /rootfs/usr/local/etc/redis \
    && chmod 1777 /rootfs/tmp

# 3. Build redis-init (Static Wrapper)
RUN gcc -O2 -static -o /rootfs/usr/bin/redis-init /usr/src/redis-init.c \
    && strip --strip-all /rootfs/usr/bin/redis-init

# 4. Extract Dependencies (The Magic Step)
# This will pull libjemalloc for the server and libc for the tools
RUN extract_libs.sh \
    /rootfs/usr/bin/redis-server \
    /rootfs/usr/bin/redis-cli \
    /rootfs/usr/bin/redis-benchmark \
    /rootfs/usr/bin/redis-check-aof \
    /rootfs/usr/bin/redis-check-rdb \
    /rootfs/usr/bin/redis-sentinel \
    /rootfs/usr/bin/redis-init

# 5. Finalize Library Cache in RootFS
RUN /sbin/ldconfig -r /rootfs

# ==============================================================================
# TARGET 1: DOCKER (Standard)
# ==============================================================================
FROM cgr.dev/chainguard/static:latest AS docker

ARG REDIS_VERSION
LABEL org.opencontainers.image.title="Ghost Core Redis (Docker)"
LABEL org.opencontainers.image.version="${REDIS_VERSION}"
LABEL org.opencontainers.image.vendor="Taha2Samy"

# Copy Files
COPY --from=assembler /rootfs/etc/passwd /etc/passwd
COPY --from=assembler /rootfs/etc/group /etc/group
COPY --from=assembler /rootfs/etc/ld.so.cache /etc/ld.so.cache
COPY --from=assembler /usr/share/zoneinfo /usr/share/zoneinfo
COPY --from=assembler /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/

COPY --from=assembler /rootfs/usr/bin/redis-server /usr/bin/redis-server
COPY --from=assembler /rootfs/usr/bin/redis-init /usr/bin/redis-init

COPY --from=assembler --chown=999:999 /rootfs/usr/local/etc/redis /usr/local/etc/redis
COPY --from=assembler /rootfs/usr/lib/ /usr/lib/
COPY --from=assembler --chown=999:999 /rootfs/data /data
COPY --from=assembler --chown=999:999 /rootfs/var/run /var/run
COPY --from=assembler --chown=999:999 /rootfs/tmp /tmp
COPY redis/config/redis.conf /usr/local/etc/redis/redis.conf

VOLUME /data
WORKDIR /data
EXPOSE 6379

USER 0
ENTRYPOINT ["/usr/bin/redis-init"]
CMD ["/usr/local/etc/redis/redis.conf"]

# ==============================================================================
# TARGET 2: KUBERNETES (Minimal / Rootless)
# ==============================================================================
FROM cgr.dev/chainguard/static:latest AS k8s

ARG REDIS_VERSION
LABEL org.opencontainers.image.title="Ghost Core Redis (K8s)"
LABEL org.opencontainers.image.version="${REDIS_VERSION}"
LABEL org.opencontainers.image.vendor="Taha2Samy"

# Copy Files (Identical structure, different User/Entrypoint)
COPY --from=assembler /rootfs/etc/passwd /etc/passwd
COPY --from=assembler /rootfs/etc/group /etc/group
COPY --from=assembler /rootfs/etc/ld.so.cache /etc/ld.so.cache
COPY --from=assembler /usr/share/zoneinfo /usr/share/zoneinfo
COPY --from=assembler /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/

COPY --from=assembler /rootfs/usr/bin/redis-server /usr/bin/redis-server
COPY --from=assembler --chown=999:999 /rootfs/usr/local/etc/redis /usr/local/etc/redis
COPY --from=assembler /rootfs/usr/lib/ /usr/lib/
COPY --from=assembler --chown=999:999 /rootfs/data /data
COPY --from=assembler --chown=999:999 /rootfs/var/run /var/run
COPY --from=assembler --chown=999:999 /rootfs/tmp /tmp
COPY redis/config/redis.conf /usr/local/etc/redis/redis.conf

VOLUME /data
WORKDIR /data
EXPOSE 6379

USER 999
ENTRYPOINT ["/usr/bin/redis-server"]
CMD ["/usr/local/etc/redis/redis.conf"]

# ==============================================================================
# TARGET 3: DEVELOPMENT (Debug Tools Included)
# ==============================================================================
FROM cgr.dev/chainguard/wolfi-base:latest AS dev

ARG REDIS_VERSION
LABEL org.opencontainers.image.title="Ghost Core Redis (Dev)"
LABEL org.opencontainers.image.version="${REDIS_VERSION}"

# Install debug tools
RUN apk add --no-cache bash curl vim tree bind-tools busybox

# Copy Files
COPY --from=assembler /rootfs/etc/passwd /etc/passwd
COPY --from=assembler /rootfs/etc/group /etc/group
COPY --from=assembler /rootfs/etc/ld.so.cache /etc/ld.so.cache
COPY --from=assembler /usr/share/zoneinfo /usr/share/zoneinfo
COPY --from=assembler /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
COPY --from=assembler /rootfs/usr/bin/ /usr/bin/
COPY --from=assembler --chown=999:999 /rootfs/usr/local/etc/redis /usr/local/etc/redis
COPY --from=assembler /rootfs/usr/lib/ /usr/lib/
COPY --from=assembler --chown=999:999 /rootfs/data /data
COPY --from=assembler --chown=999:999 /rootfs/var/run /var/run
COPY --from=assembler --chown=999:999 /rootfs/tmp /tmp
COPY redis/config/redis.conf /usr/local/etc/redis/redis.conf

VOLUME /data
WORKDIR /data
EXPOSE 6379

USER 0
ENTRYPOINT ["/usr/bin/redis-init"]
CMD ["/usr/local/etc/redis/redis.conf"]