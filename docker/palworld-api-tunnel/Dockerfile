FROM alpine:3.22

RUN apk add --no-cache ca-certificates netcat-openbsd openssh-client \
    && addgroup -S tunnel \
    && adduser -S -G tunnel -h /home/tunnel tunnel

COPY docker/palworld-api-tunnel/entrypoint.sh /usr/local/bin/palworld-api-tunnel
RUN chmod +x /usr/local/bin/palworld-api-tunnel

USER tunnel
ENTRYPOINT ["palworld-api-tunnel"]
