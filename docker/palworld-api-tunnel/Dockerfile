FROM alpine:3.22

RUN apk add --no-cache ca-certificates netcat-openbsd openssh-client

COPY docker/palworld-api-tunnel/entrypoint.sh /usr/local/bin/palworld-api-tunnel
RUN chmod +x /usr/local/bin/palworld-api-tunnel

ENTRYPOINT ["palworld-api-tunnel"]
