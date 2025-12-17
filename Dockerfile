FROM ubuntu:24.04

# renovate: datasource=github-releases depName=mm503/nordvpn-versions
ARG NORDVPN_VERSION=4.3.1
ARG GIT_REVISION=unknown

LABEL org.opencontainers.image.source="https://github.com/mm503/nordvpn-sidecar" \
      org.opencontainers.image.url="https://github.com/mm503/nordvpn-sidecar" \
      org.opencontainers.image.title="NordVPN Sidecar Container" \
      org.opencontainers.image.description="A lightweight sidecar VPN solution for Kubernetes pods that redirects all pod traffic through NordVPN with optional split tunneling support" \
      org.opencontainers.image.version="${NORDVPN_VERSION}" \
      org.opencontainers.image.revision="${GIT_REVISION}" \
      org.opencontainers.image.vendor="mm503"

RUN apt-get update && \
  apt-get full-upgrade -y && \
  apt-get install -y --no-install-recommends wget apt-transport-https ca-certificates && \
  wget -qO /etc/apt/trusted.gpg.d/nordvpn_public.asc https://repo.nordvpn.com/gpg/nordvpn_public.asc && \
  echo "deb https://repo.nordvpn.com/deb/nordvpn/debian stable main" > /etc/apt/sources.list.d/nordvpn.list && \
  apt-get update && \
  apt-get install -y --no-install-recommends nordvpn=${NORDVPN_VERSION} && \
  apt-get install -y --no-install-recommends curl && \
  apt-get clean && \
  rm -rf /var/lib/apt/lists/* && \
  nordvpn --version | grep "${NORDVPN_VERSION}"

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT [ "/entrypoint.sh" ]
