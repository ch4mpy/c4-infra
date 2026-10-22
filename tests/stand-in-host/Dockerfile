# A stand-in demo host, for the tests only (tests/lib/stand-in-host.sh): Ubuntu running Docker and
# sshd, with the tools the deployment and the host's bootstrap use. Started --privileged, so that
# its own dockerd runs; never deployed anywhere.
FROM ubuntu:24.04

RUN apt-get update \
  && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    docker.io docker-compose-v2 sudo openssh-server rsync jq cron curl ca-certificates iptables ufw \
  && rm -rf /var/lib/apt/lists/* \
  && mkdir -p /run/sshd \
  && ssh-keygen -A

COPY entrypoint.sh /usr/local/bin/stand-in-entrypoint
RUN chmod 755 /usr/local/bin/stand-in-entrypoint
ENTRYPOINT ["/usr/local/bin/stand-in-entrypoint"]
