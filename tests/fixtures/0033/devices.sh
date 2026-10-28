# 0033 fixture (tests/0033-dump-limits.stand-in.sh, tests/0033-copy-limits.stand-in.sh): the tests'
# devices, sourced as root inside the stand-in from /root/devices.sh. Nothing here runs on a real host.

# <fifo>: opened for writing, never written to; /root/opened once a reader opened it
held() { { touch /root/opened; exec sleep 3600; } > "$1"; }

# <fifo> <source>: whole at its first opening; at its second (/root/served), all but its last 100
# bytes, then held open
served() {
  cat "$2" > "$1"
  while find /proc/[0-9]*/fd -lname "$1" 2> /dev/null | grep -q .; do sleep 0.1; done
  { touch /root/served; head -c -100 "$2"; exec sleep 3600; } > "$1"
}

# <file> of a backup replaced by a FIFO, its writer (held or served, from the file's copy in /root) in
# a session of its own, recorded in /root/writers
fifo() { # held|served <backup directory> <file>
  local path=$2/$3
  cp "$path" "/root/$3.whole" && rm "$path" && mkfifo -m 0640 "$path" || return 1
  rm -f /root/opened /root/served
  setsid bash -c '. /root/devices.sh; "$@"' sh "$1" "$path" "/root/$3.whole" < /dev/null > /dev/null 2>&1 &
  echo $! >> /root/writers
}

# The containers of the stack database's image without a compose label, or labelled c4-infra.c4-app
throwaways() {
  local image id
  image=$(docker inspect -f '{{.Image}}' c4-infra.keycloak-db)
  {
    docker ps -aq --no-trunc --filter label=c4-infra.c4-app
    for id in $(docker ps -aq --no-trunc); do
      [ "$(docker inspect -f '{{.Image}}|{{index .Config.Labels "com.docker.compose.project"}}' "$id" 2> /dev/null)" != "$image|" ] || echo "$id"
    done
  } | LC_ALL=C sort -u
}

# The first throwaway that starts, paused (docker events into a file, polled); its id in /root/paused
watch_throwaway() {
  local image
  image=$(docker inspect -f '{{.Image}}' c4-infra.keycloak-db)
  rm -f /root/events /root/paused
  docker events --filter event=start --filter type=container --filter image="$image" --format '{{.Actor.ID}}' \
    > /root/events 2> /dev/null < /dev/null &
  echo $! > /root/watcher.pids
  (
    while :; do
      while read -r id; do
        [ -z "$(docker inspect -f '{{index .Config.Labels "com.docker.compose.project"}}' "$id" 2> /dev/null)" ] || continue
        docker pause "$id" > /dev/null && echo "$id" > /root/paused
        exit
      done < /root/events
      sleep 0.05
    done
  ) < /dev/null > /dev/null 2>&1 &
  echo $! >> /root/watcher.pids
}
unwatch() { [ ! -s /root/watcher.pids ] || kill $(cat /root/watcher.pids) 2> /dev/null; rm -f /root/watcher.pids; }

# What a cut command of Faito's may have left (the code before the fix): c4-app and whatever holds
# Faito's lock, the FIFOs' writers, the watcher, the throwaways, faito.db's pg_dump and pg_restore
# (never one whose parent is postgres: it would take that for a crash); then Faito's containers started
free_faito() {
  local pid id init
  for pid in $(find /proc/[0-9]*/fd -lname /var/lib/c4-apps/.faito.lock 2> /dev/null | cut -d/ -f3 | LC_ALL=C sort -u); do
    kill -KILL "$pid" 2> /dev/null
  done
  pkill -KILL -x c4-app
  if [ -s /root/writers ]; then
    for pid in $(cat /root/writers); do kill -KILL -- "-$pid" 2> /dev/null; done
  fi
  rm -f /root/writers
  unwatch
  for id in $(throwaways); do docker rm -f "$id" > /dev/null; done
  init=$(docker inspect -f '{{.State.Pid}}' faito.db)
  for pid in $(docker top faito.db -eo pid,ppid,comm \
    | awk -v init="$init" '($3 == "pg_dump" || $3 == "pg_restore") && $2 != init { print $1 }'); do
    kill -KILL "$pid" 2> /dev/null
  done
  docker start faito.db faito.files faito.other > /dev/null
}
