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

# Without a plugin address no plugin is configured.
if grep -Fq 'httpPlugins' <<<"$config"; then
  echo "unexpected plugin section" >&2
  exit 1
fi

plugin_env=(
  -e FRPS_AUTH_METHOD=oidc
  -e FRPS_AUTH_OIDC_ISSUER=https://issuer.example.com
  -e FRPS_PLUGIN_ADDR=https://plugin.example.com:443
  -e FRPS_PLUGIN_PATH=/v1/plugin
  -e FRPS_PLUGIN_TLS_VERIFY=true
)
config=$(render "${plugin_env[@]}")

grep -Fqx '[[httpPlugins]]' <<<"$config"
grep -Fqx 'name = "plugin"' <<<"$config"
grep -Fqx 'addr = "https://plugin.example.com:443"' <<<"$config"
grep -Fqx 'path = "/v1/plugin"' <<<"$config"
grep -Fqx 'ops = ["Login","NewProxy"]' <<<"$config"
grep -Fqx 'tlsVerify = true' <<<"$config"

config=$(render -e FRPS_AUTH_TOKEN=test-token -e FRPS_PLUGIN_ADDR=127.0.0.1:9000 -e 'FRPS_PLUGIN_OPS=["NewProxy"]')
grep -Fqx 'addr = "127.0.0.1:9000"' <<<"$config"
grep -Fqx 'ops = ["NewProxy"]' <<<"$config"
if grep -Fq 'tlsVerify' <<<"$config"; then
  echo "unexpected tlsVerify" >&2
  exit 1
fi

docker run --rm -e FRPS_AUTH_TOKEN=test-token -e FRPS_PLUGIN_ADDR=127.0.0.1:9000 -e FRPS_PLUGIN_PATH=/v1/plugin \
  "$image" frps verify -c /etc/frps.toml >/dev/null
