#!/usr/bin/env bash

set -e

script_path="$( cd "$(dirname "$0")" ; pwd -P )"

: "${HTTP_TLS_CERTIFICATE:?set HTTP_TLS_CERTIFICATE to the ssl certificate path}"
: "${HTTP_TLS_KEY:?set HTTP_TLS_KEY to the ssl key path}"

echo "Starting dash-dev container. Listening on https://dash.dev.localhost"

if command -v docker >/dev/null 2>&1; then
  docker run --rm $@ \
    --net=host \
    --name dash-dev \
    -v ${script_path}/nginx:/etc/nginx:ro \
    -v ${HTTP_TLS_CERTIFICATE}:/certs/ssl.crt:ro \
    -v ${HTTP_TLS_KEY}:/certs/ssl.key:ro \
    --entrypoint /usr/sbin/nginx \
    nginx:1.25.1-alpine-slim -c /etc/nginx/nginx.dev.conf -g "daemon off;"
elif command -v container >/dev/null 2>&1; then
  # Fallback: apple's container tool has no host networking. The container
  # publishes 80/443 and the entrypoint rewrites a copy of the nginx config
  # so the 127.0.0.1 upstreams target the host gateway instead. Services on
  # the host must listen beyond loopback to be reachable from the VM.
  container run --rm $@ \
    --name dash-dev \
    -p 80:80 \
    -p 443:443 \
    -v ${script_path}/nginx:/etc/nginx:ro \
    -v ${HTTP_TLS_CERTIFICATE}:/certs/ssl.crt:ro \
    -v ${HTTP_TLS_KEY}:/certs/ssl.key:ro \
    --entrypoint /bin/sh \
    nginx:1.25.1-alpine-slim -c '
      gw=$(ip route 2>/dev/null | awk "/^default/{print \$3; exit}")
      [ -n "$gw" ] || gw=192.168.64.1
      cp -r /etc/nginx /tmp/ngx
      find /tmp/ngx -name "*.conf" -exec sed -i "s/127\.0\.0\.1/$gw/g" {} +
      sed -i "s#/etc/nginx/servers#/tmp/ngx/servers#" /tmp/ngx/nginx.dev.conf
      exec nginx -p /tmp/ngx -c /tmp/ngx/nginx.dev.conf -g "daemon off;"
    '
else
  echo "error: neither docker nor apple's container tool is installed" >&2
  exit 1
fi
