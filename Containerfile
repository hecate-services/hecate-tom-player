# hecate-tom-house
#
# TOM, Traders of Macao: the player's house, purse and ship.
#
# THIS IMAGE HAS A DATA VOLUME AND IT IS NOT OPTIONAL. The house keeps its purse,
# every order and how it concluded, and the last picture it had of its ship in an
# append-only log. Run this image without a volume on /var/lib/hecate-tom-house
# and every restart is a new player with a fresh thousand coins, which is a money
# printer with a container runtime attached.

# ⚠ THE RUNTIME IS PINNED HERE AND IN CI AND THEY MUST AGREE. A service that
# builds on one release and tests on another only ever proves that the tests pass
# on the CI release.
FROM docker.io/erlang:28-alpine AS builder
WORKDIR /build

# macula ships a QUIC NIF. MACULA_FORCE_SOURCE_BUILD makes it build here rather
# than fetch a prebuilt binary linked against a different libc: the fetched
# artifact loads on the build host and fails on alpine at runtime.
RUN apk add --no-cache git curl bash build-base cmake perl linux-headers
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
        | sh -s -- -y --default-toolchain stable --profile minimal
ENV PATH="/root/.cargo/bin:${PATH}"
ENV RUSTFLAGS="-C target-feature=-crt-static"
ENV MACULA_FORCE_SOURCE_BUILD=1

RUN curl -fsSL https://s3.amazonaws.com/rebar3/rebar3 -o /usr/local/bin/rebar3 \
    && chmod +x /usr/local/bin/rebar3

# Dependencies resolve from rebar.config alone, so this layer survives every
# change to src/ and config/ and the Rust toolchain is not re-run per commit.
COPY rebar.config ./
RUN rebar3 get-deps

COPY config ./config
COPY src ./src
RUN rebar3 as prod release

FROM docker.io/alpine:3.22
# LINKS THE PACKAGE TO THE REPOSITORY. On registries that read it, ghcr among
# them, a package without this label is an orphan: it does not appear on the
# repository page and does not inherit its visibility.
LABEL org.opencontainers.image.source="https://github.com/hecate-services/hecate-tom-house"
RUN apk add --no-cache ncurses-libs libstdc++ libgcc openssl ca-certificates curl
WORKDIR /app
COPY --from=builder /build/_build/prod/rel/hecate_tom_house ./

ENV HOME=/app
ENV RELX_REPLACE_OS_VARS=true

ENV TOM_COOKIE=hecate_tom_house
ENV TOM_HEALTH_PORT=8460
ENV TOM_WEB_PORT=8461
ENV TOM_REALM_NAME=io.macula
ENV TOM_PLAYER=raf
ENV TOM_SHIP=santa_clara
ENV TOM_HARBOURS=macao,lisbon
ENV TOM_GOODS=pepper,nutmeg,raw_silk,porcelain
ENV TOM_PURSE=1000.0
ENV TOM_LEDGER=/var/lib/hecate-tom-house/house.log
ENV TOM_QUOTE_INTERVAL_MS=5000
ENV TOM_LOCATE_INTERVAL_MS=10000

# TOM_REALM_TAG and TOM_STATION_SEED have NO default on purpose. A house that
# guessed a realm would announce itself where nobody can attribute it and reach
# nobody, which looks exactly like a healthy node.

VOLUME ["/var/lib/hecate-tom-house"]
VOLUME ["/etc/hecate/secrets"]

EXPOSE 8460 8461

# A house with no station under it reports DEGRADED, and that is the honest
# answer: it has its purse, its history and its page, and it cannot do the thing
# it exists to do. Expect a minute of unhealthy while the pool attaches.
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
    CMD curl -fsS "http://127.0.0.1:${TOM_HEALTH_PORT}/health" || exit 1

CMD ["/app/bin/hecate_tom_house", "foreground"]
