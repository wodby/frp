#!/usr/bin/env bash

set -euo pipefail

image="${1:?image is required}"

render() {
  docker run --rm --entrypoint gotpl "$@" "$image" /etc/gotpl/frpc.toml.tmpl
}

config=$(render -e FRPC_CLEAR_AUTHORIZATION_HEADER=1)
grep -Fqx 'requestHeaders.set.Authorization = ""' <<<"$config"
if grep -Fq 'requestHeaders.set.Authorization = "Bearer ' <<<"$config"; then
  echo "clear mode unexpectedly rendered a bearer token" >&2
  exit 1
fi

docker run --rm \
  -e FRPC_SERVER_ADDR=127.0.0.1 \
  -e FRPC_SERVER_PORT=7000 \
  -e FRPC_AUTH_METHOD=token \
  -e FRPC_AUTH_TOKEN=test-token \
  -e FRPC_NAME=test \
  -e FRPC_LOCAL_PORT=8001 \
  -e FRPC_CUSTOM_DOMAIN=test.example.com \
  -e FRPC_CLEAR_AUTHORIZATION_HEADER=1 \
  "$image" frpc verify -c /etc/frpc.toml >/dev/null

config=$(render -e FRPC_SET_AUTHORIZATION_BEARER_TOKEN=1 -e TOKEN=test-token)
grep -Fqx 'requestHeaders.set.Authorization = "Bearer test-token"' <<<"$config"

config=$(render \
  -e FRPC_AUTH_METHOD=oidc \
  -e 'FRPC_AUTH_ADDITIONAL_SCOPES=["HeartBeats","NewWorkConns"]')
grep -Fqx 'auth.additionalScopes = ["HeartBeats","NewWorkConns"]' <<<"$config"

config=$(render)
if grep -Fq 'requestHeaders.set.Authorization' <<<"$config"; then
  echo "default mode unexpectedly rendered an authorization override" >&2
  exit 1
fi
