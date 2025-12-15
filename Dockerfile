FROM alpine:3.23

ARG TARGETPLATFORM
ARG TARGETARCH
ARG VERSION

RUN set -ex;  \
    apk add --no-cache bash curl kubectl; \
    dockerplatform=${TARGETPLATFORM:-linux/amd64};\
    gotpl_url="https://github.com/wodby/gotpl/releases/latest/download/gotpl-${TARGETPLATFORM/\//-}.tar.gz"; \
    wget -qO- "${gotpl_url}" | tar xz --no-same-owner -C /usr/local/bin; \
    wget -qO- "https://github.com/fatedier/frp/releases/download/v${VERSION}/frp_${VERSION}_linux_${TARGETARCH}.tar.gz" | tar xz --strip-components=1 -C /tmp; \
    mv /tmp/frpc /usr/local/bin; \
    mv /tmp/frps /usr/local/bin; \
    rm -rf /tmp/*   

COPY docker-entrypoint.sh /usr/local/bin/
COPY templates /etc/gotpl

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["frps", "-c", "/etc/frps.toml"]
