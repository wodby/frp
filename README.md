# frp docker container images

[![Build Status](https://github.com/wodby/frp/workflows/Build%20docker%20image/badge.svg)](https://github.com/wodby/frp/actions)
[![Docker Pulls](https://img.shields.io/docker/pulls/wodby/frp.svg)](https://hub.docker.com/r/wodby/frp)
[![Docker Stars](https://img.shields.io/docker/stars/wodby/frp.svg)](https://hub.docker.com/r/wodby/frp)

## Image revisions

Use image revision tags such as `wodby/frp:0.69-rN` to select a Wodby image revision.
Major and minor tags use the repository release number. Full-version tags such as
`wodby/frp:0.69.1-r0` start at `r0` for each exact upstream version.
Every published versioned revision tag has a matching annotated Git tag pointing to its release commit.
Existing tags remain available after support for their major or minor version ends.
See [release tags](https://github.com/wodby/frp/tags) for available revisions and the [image revision policy](https://github.com/wodby/images#image-revisions) for upgrade guidance.
Existing SemVer image tags remain available.

## Supported tags and respective `Dockerfile` links

- [`latest` (*Dockerfile*)](https://github.com/wodby/frp/tree/master/Dockerfile)

All images are built for `linux/amd64` and `linux/arm64`.

## FRP server

The image contains both `frpc` and `frps`. It starts `frps` by default and
renders `/etc/frps.toml` from environment variables before startup.

| Variable | Default | Purpose |
| --- | --- | --- |
| `FRPS_BIND_PORT` | `7000` | FRPC control port |
| `FRPS_VHOST_HTTP_PORT` | `8080` | HTTP virtual-host proxy port |
| `FRPS_WEB_SERVER_ADDR` | `127.0.0.1` | Dashboard listen address |
| `FRPS_WEB_SERVER_PORT` | `7500` | Dashboard port |
| `FRPS_WEB_SERVER_USER` | empty | Dashboard Basic Auth username |
| `FRPS_WEB_SERVER_PASSWORD` | empty | Dashboard Basic Auth password |
| `FRPS_AUTH_METHOD` | `token` | Client authentication method |
| `FRPS_AUTH_TOKEN` | empty | Shared FRPC authentication token |
| `FRPS_AUTH_ADDITIONAL_SCOPES` | empty | JSON array of additional token-auth scopes |
| `FRPS_TLS_FORCE` | `false` | Require TLS for client control connections |
| `FRPS_LOG_LEVEL` | `info` | FRPS log level |

Set both dashboard credentials when listening on a non-loopback address. The
Wodby FRPS chart enables TLS for control connections and supplies generated,
stable credentials for token authentication and the dashboard.

## FRP client

When FRPC uses OIDC, set `FRPC_AUTH_ADDITIONAL_SCOPES` to a JSON array to
authenticate the same additional connection types required by FRPS. For
example, `["HeartBeats","NewWorkConns"]` authenticates heartbeat and work
connections as well as the initial control connection.
