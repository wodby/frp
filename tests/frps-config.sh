#!/usr/bin/env bash

set -euo pipefail

image="${1:?image is required}"

render() {
  docker run --rm --entrypoint gotpl "$@" "$image" /etc/gotpl/frps.toml.tmpl
}

config=$(render \
  -e FRPS_AUTH_TOKEN=test-token \
  -e 'FRPS_AUTH_ADDITIONAL_SCOPES=["HeartBeats","NewWorkConns"]' \
  -e FRPS_WEB_SERVER_ADDR=0.0.0.0 \
  -e FRPS_WEB_SERVER_USER=admin \
  -e FRPS_WEB_SERVER_PASSWORD=test-password \
  -e FRPS_TLS_FORCE=true)

grep -Fqx 'bindPort = 7000' <<<"$config"
grep -Fqx 'vhostHTTPPort = 8080' <<<"$config"
grep -Fqx 'auth.method = "token"' <<<"$config"
grep -Fqx 'auth.token = "test-token"' <<<"$config"
grep -Fqx 'auth.additionalScopes = ["HeartBeats","NewWorkConns"]' <<<"$config"
grep -Fqx 'webServer.user = "admin"' <<<"$config"
grep -Fqx 'webServer.password = "test-password"' <<<"$config"
grep -Fqx 'transport.tls.force = true' <<<"$config"

docker run --rm \
  -e FRPS_AUTH_TOKEN=test-token \
  -e 'FRPS_AUTH_ADDITIONAL_SCOPES=["HeartBeats","NewWorkConns"]' \
  -e FRPS_WEB_SERVER_ADDR=0.0.0.0 \
  -e FRPS_WEB_SERVER_USER=admin \
  -e FRPS_WEB_SERVER_PASSWORD=test-password \
  -e FRPS_TLS_FORCE=true \
  "$image" frps verify -c /etc/frps.toml >/dev/null
