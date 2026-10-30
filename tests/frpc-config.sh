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

shell_route=(
  -e FRPC_SHELL_LOCATION=/.shell/org-cluster/
  -e FRPC_SHELL_HTTP_USER=shell-user
  -e FRPC_SHELL_HTTP_PASSWORD=shell-password
)

config=$(render -e FRPC_NAME=test -e FRPC_CUSTOM_DOMAIN=test.example.com "${shell_route[@]}")
grep -Fqx 'name = "test-shell"' <<<"$config"
grep -Fqx 'localPort = 8002' <<<"$config"
grep -Fqx 'locations = ["/.shell/org-cluster/"]' <<<"$config"
grep -Fqx 'httpUser = "shell-user"' <<<"$config"
grep -Fqx 'httpPassword = "shell-password"' <<<"$config"
grep -Fqx 'requestHeaders.set.Authorization = ""' <<<"$config"

docker run --rm \
  -e FRPC_SERVER_ADDR=127.0.0.1 \
  -e FRPC_SERVER_PORT=7000 \
  -e FRPC_AUTH_METHOD=token \
  -e FRPC_AUTH_TOKEN=test-token \
  -e FRPC_NAME=test \
  -e FRPC_LOCAL_PORT=8001 \
  -e FRPC_CUSTOM_DOMAIN=test.example.com \
  -e FRPC_CLEAR_AUTHORIZATION_HEADER=1 \
  "${shell_route[@]}" \
  "$image" frpc verify -c /etc/frpc.toml >/dev/null

# Without Basic Auth the terminal route would expose the Kubernetes API.
for missing in FRPC_SHELL_HTTP_USER FRPC_SHELL_HTTP_PASSWORD; do
  args=(-e FRPC_SHELL_LOCATION=/.shell/org-cluster/ -e FRPC_SHELL_HTTP_USER=shell-user -e FRPC_SHELL_HTTP_PASSWORD=shell-password -e "$missing=")
  config=$(render "${args[@]}")
  if grep -Fq 'name = "frpc-shell"' <<<"$config"; then
    echo "terminal route rendered without $missing" >&2
    exit 1
  fi
done

# The proxy ships in the image and refuses to start without its route prefix.
docker run --rm --entrypoint sh "$image" -c 'command -v kube-token-proxy' >/dev/null
if docker run --rm --entrypoint kube-token-proxy "$image" 2>/dev/null; then
  echo "kube-token-proxy started without a prefix" >&2
  exit 1
fi
