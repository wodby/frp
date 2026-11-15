FROM golang:1.26-alpine AS kube-token-proxy

WORKDIR /src
COPY kube-token-proxy/ ./
RUN set -ex; \
    CGO_ENABLED=0 go test ./...; \
    CGO_ENABLED=0 go build -trimpath -ldflags "-s -w" -o /kube-token-proxy .

FROM alpine:3.23

ARG TARGETPLATFORM
ARG TARGETARCH
ARG FRP_VERSION
# Official kubectl build: Alpine's package lags Go and module security fixes. kubectl only runs
# `kubectl proxy` and simple object deletes here, so any version within the supported skew works.
ARG KUBECTL_VERSION=1.34.13

RUN set -ex;  \
    apk add --no-cache bash curl; \
    kubectl_url="https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/${TARGETARCH}/kubectl"; \
    wget -qO /usr/local/bin/kubectl "${kubectl_url}"; \
    echo "$(wget -qO- "${kubectl_url}.sha256")  /usr/local/bin/kubectl" | sha256sum -c -; \
    chmod 0755 /usr/local/bin/kubectl; \
    dockerplatform=${TARGETPLATFORM:-linux/amd64};\
    gotpl_url="https://github.com/wodby/gotpl/releases/latest/download/gotpl-${TARGETPLATFORM/\//-}.tar.gz"; \
    wget -qO- "${gotpl_url}" | tar xz --no-same-owner -C /usr/local/bin; \
    wget -qO- "https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/frp_${FRP_VERSION}_linux_${TARGETARCH}.tar.gz" | tar xz --strip-components=1 -C /tmp; \
    mv /tmp/frpc /usr/local/bin; \
    mv /tmp/frps /usr/local/bin; \
    rm -rf /tmp/*   

COPY --from=kube-token-proxy /kube-token-proxy /usr/local/bin/
COPY docker-entrypoint.sh /usr/local/bin/
COPY templates /etc/gotpl

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["frps", "-c", "/etc/frps.toml"]
