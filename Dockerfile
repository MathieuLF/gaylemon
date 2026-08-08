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
USER gaylemon
ENV GAYLEMON_WEB_LISTEN=:8080 \
    GAYLEMON_PORTAL_ROOT=/app/portal \
    GAYLEMON_ASSET_ROOT=/app/runtime/public-assets
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/gaylemon-web"]
