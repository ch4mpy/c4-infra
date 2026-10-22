#!/usr/bin/env bash
# The stand-in host's init: lets nested containers have cgroups (moby's hack/dind, cgroup v2 only),
# starts sshd and dockerd, then waits; `docker stop` stops dockerd cleanly, and its containers.
set -euo pipefail

# cgroup v2: move this container's processes into a child group, so that the controllers can be
# delegated to dockerd's containers (writing subtree_control fails while the root group holds any)
if [ -f /sys/fs/cgroup/cgroup.controllers ]; then
  mkdir -p /sys/fs/cgroup/init
  xargs -rn1 < /sys/fs/cgroup/cgroup.procs > /sys/fs/cgroup/init/cgroup.procs || :
  sed -e 's/ / +/g' -e 's/^/+/' < /sys/fs/cgroup/cgroup.controllers > /sys/fs/cgroup/cgroup.subtree_control
fi

/usr/sbin/sshd
dockerd > /var/log/dockerd.log 2>&1 &
dockerd_pid=$!
trap 'kill -TERM "$dockerd_pid"; wait "$dockerd_pid"; exit 0' TERM INT
sleep infinity &
wait $!
