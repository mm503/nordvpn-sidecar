FROM ubuntu:24.04

# renovate: datasource=github-releases depName=mm503/nordvpn-versions
ARG NORDVPN_VERSION=4.2.2

RUN apt-get update && \
  apt-get install -y --no-install-recommends wget apt-transport-https ca-certificates && \
  wget -qO /etc/apt/trusted.gpg.d/nordvpn_public.asc https://repo.nordvpn.com/gpg/nordvpn_public.asc && \
  echo "deb https://repo.nordvpn.com/deb/nordvpn/debian stable main" > /etc/apt/sources.list.d/nordvpn.list && \
  apt-get update && \
  apt-get install -y --no-install-recommends nordvpn && \
  apt-get install -y --no-install-recommends curl && \
  apt-get clean && \
  rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT [ "/entrypoint.sh" ]
