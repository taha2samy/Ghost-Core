FROM cgr.dev/chainguard/wolfi-base AS builder

ARG PG_VERSION
ARG PG_SHA256

RUN apk add --no-cache \
    build-base pkgconf wget openssl-dev linux-headers \
    coreutils binutils scanelf posix-libc-utils bash \
    libxml2-dev icu-dev zlib-dev tzdata \
    flex bison perl zlib
RUN ln -sf /usr/lib/libz.so.1 /usr/lib/libz.so

COPY scripts/extract_libs.sh /usr/bin/extract_libs.sh
COPY postgres/build.sh /usr/bin/build_postgres.sh
COPY postgres/src/postgres-init.c /usr/src/postgres-init.c
COPY postgres/config/postgresql.conf /tmp/postgresql.conf
COPY postgres/config/pg_hba.conf /tmp/pg_hba.conf

RUN chmod +x /usr/bin/build_postgres.sh /usr/bin/extract_libs.sh

RUN build_postgres.sh "${PG_VERSION}" "${PG_SHA256}"

RUN extract_libs.sh \
    /rootfs/usr/bin/postgres \
    /rootfs/usr/bin/initdb \
    /rootfs/usr/bin/pg_ctl \
    /rootfs/usr/bin/psql

RUN mkdir -p /rootfs/var/lib/postgresql/data \
    /rootfs/var/run/postgresql \
    /rootfs/tmp \
    && chown -R 999:999 /rootfs/var/lib/postgresql \
    /rootfs/var/run/postgresql \
    /rootfs/tmp \
    && chmod 1777 /rootfs/tmp \
    && chmod 0775 /rootfs/var/run/postgresql

# ==========================================
# Final Stage
# ==========================================
FROM cgr.dev/chainguard/static:latest AS final

LABEL org.opencontainers.image.title="Ghost Core PostgreSQL"

COPY --from=builder /rootfs/etc/passwd /etc/passwd
COPY --from=builder /rootfs/etc/group /etc/group

COPY --from=builder /usr/share/zoneinfo /usr/share/zoneinfo
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/

COPY --from=builder /rootfs/usr/bin/ /usr/bin/
COPY --from=builder /rootfs/usr/lib/ /usr/lib/
COPY --from=builder /rootfs/usr/share/postgresql /usr/share/postgresql
COPY --from=builder /rootfs/usr/local/etc/postgres /usr/local/etc/postgres

COPY --from=builder --chown=999:999 /rootfs/var/lib/postgresql /var/lib/postgresql
COPY --from=builder --chown=999:999 /rootfs/var/run/postgresql /var/run/postgresql
COPY --from=builder --chown=999:999 /rootfs/tmp /tmp

ENV PGDATA /var/lib/postgresql/data

VOLUME /var/lib/postgresql/data
WORKDIR /var/lib/postgresql
EXPOSE 5432

USER 0

ENTRYPOINT ["/usr/bin/postgres-init"]
CMD ["postgres"]

# ==========================================
# Dev Stage
# ==========================================
FROM cgr.dev/chainguard/wolfi-base:latest AS dev

RUN apk add --no-cache bash curl vim tree

COPY --from=builder /rootfs/etc/passwd /etc/passwd
COPY --from=builder /rootfs/etc/group /etc/group

COPY --from=builder /usr/share/zoneinfo /usr/share/zoneinfo
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/

COPY --from=builder /rootfs/usr/bin/ /usr/bin/
COPY --from=builder /rootfs/usr/lib/ /usr/lib/
COPY --from=builder /rootfs/usr/share/postgresql /usr/share/postgresql
COPY --from=builder /rootfs/usr/local/etc/postgres /usr/local/etc/postgres

COPY --from=builder --chown=999:999 /rootfs/var/lib/postgresql /var/lib/postgresql
COPY --from=builder --chown=999:999 /rootfs/var/run/postgresql /var/run/postgresql
COPY --from=builder --chown=999:999 /rootfs/tmp /tmpذ

ENV PGDATA /var/lib/postgresql/data

VOLUME /var/lib/postgresql/data
WORKDIR /var/lib/postgresql
EXPOSE 5432

USER 0

ENTRYPOINT ["/usr/bin/postgres-init"]
CMD ["postgres"]