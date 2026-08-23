FROM alpine:3.22 AS game-assets

ARG PALWORLD_SAVE_TOOLS_REPOSITORY=https://github.com/MathieuLF/PalworldSaveTools.git
ARG PALWORLD_SAVE_TOOLS_COMMIT=ea6592ebfbb79389b6f4570002c71f9b25040641
RUN apk add --no-cache git \
    && git init --quiet /source \
    && git -C /source remote add origin "${PALWORLD_SAVE_TOOLS_REPOSITORY}" \
    && git -C /source fetch --quiet --filter=blob:none --depth 1 origin "${PALWORLD_SAVE_TOOLS_COMMIT}" \
    && git -C /source sparse-checkout init --cone \
    && git -C /source sparse-checkout set resources/game_data/icons resources/assets/maps \
    && git -C /source checkout --quiet --detach FETCH_HEAD \
    && test "$(git -C /source rev-parse HEAD)" = "${PALWORLD_SAVE_TOOLS_COMMIT}" \
    && mkdir -p /assets/icons /assets/maps \
    && cp -a /source/resources/game_data/icons/. /assets/icons/ \
    && cp /source/resources/assets/maps/T_WorldMap.webp /source/resources/assets/maps/T_TreeMap.webp /assets/maps/ \
    && printf '%s docker-v1\n' "${PALWORLD_SAVE_TOOLS_COMMIT}" > /assets/.source-commit

FROM alpine:3.24 AS build

ARG GO_VERSION=1.27.0
ARG GO_LINUX_AMD64_SHA256=675c26c449cbb18fc24b74650de1eabbae6e16f64326fd85a283fb3b58280685
RUN apk add --no-cache ca-certificates \
    && wget -q "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz" -O /tmp/go.tar.gz \
    && echo "${GO_LINUX_AMD64_SHA256}  /tmp/go.tar.gz" | sha256sum -c - \
    && tar -C /usr/local -xzf /tmp/go.tar.gz \
    && rm /tmp/go.tar.gz
ENV PATH="/usr/local/go/bin:${PATH}"

WORKDIR /src
COPY go.mod go.sum ./
RUN test "$(go env GOVERSION)" = "go${GO_VERSION}" \
    && go mod download
COPY cmd ./cmd
COPY db ./db
COPY internal ./internal
COPY VERSION ./VERSION
ARG GAYLEMON_VERSION
ARG GAYLEMON_COMMIT=unknown
ARG GAYLEMON_CHANNEL=development
RUN release="${GAYLEMON_VERSION:-$(tr -d '\r\n' < VERSION)}" \
    && test -n "${release}" \
    && CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -mod=mod -trimpath -ldflags="-s -w -X main.version=${release} -X main.commit=${GAYLEMON_COMMIT} -X main.channel=${GAYLEMON_CHANNEL}" -o /out/gaylemon-web ./cmd/gaylemon-web

FROM alpine:3.22
RUN apk add --no-cache ca-certificates tzdata \
    && addgroup -S -g 10001 gaylemon \
    && adduser -S -D -H -u 10001 -G gaylemon gaylemon
WORKDIR /app
COPY --from=build /out/gaylemon-web /usr/local/bin/gaylemon-web
COPY portal /app/portal
RUN find /app/portal -type d -exec chmod 0755 {} + \
    && find /app/portal -type f -exec chmod 0644 {} + \
    && mkdir -p /app/runtime/public-assets \
    && chown -R gaylemon:gaylemon /app/runtime
COPY --from=game-assets --chown=gaylemon:gaylemon /assets/ /app/runtime/public-assets/
USER gaylemon
ENV GAYLEMON_WEB_LISTEN=:8080 \
    GAYLEMON_PORTAL_ROOT=/app/portal \
    GAYLEMON_ASSET_ROOT=/app/runtime/public-assets
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/gaylemon-web"]
