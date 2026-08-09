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

FROM golang:1.26-alpine AS build

WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY cmd ./cmd
COPY db ./db
COPY internal ./internal
ARG GAYLEMON_VERSION=dev
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -mod=mod -trimpath -ldflags="-s -w -X main.version=${GAYLEMON_VERSION}" -o /out/gaylemon-web ./cmd/gaylemon-web

FROM alpine:3.22
RUN apk add --no-cache ca-certificates tzdata \
    && addgroup -S -g 10001 gaylemon \
    && adduser -S -D -H -u 10001 -G gaylemon gaylemon
WORKDIR /app
COPY --from=build /out/gaylemon-web /usr/local/bin/gaylemon-web
COPY portal /app/portal
RUN mkdir -p /app/runtime/public-assets \
    && chown -R gaylemon:gaylemon /app/runtime
COPY --from=game-assets --chown=gaylemon:gaylemon /assets/ /app/runtime/public-assets/
USER gaylemon
ENV GAYLEMON_WEB_LISTEN=:8080 \
    GAYLEMON_PORTAL_ROOT=/app/portal \
    GAYLEMON_ASSET_ROOT=/app/runtime/public-assets
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/gaylemon-web"]
