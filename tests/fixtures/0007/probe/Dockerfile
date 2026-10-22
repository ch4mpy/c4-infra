# 0007: the probe the isolation tests run as an application's container (tests/0007-*.stand-in.sh,
# built in the stand-in's daemon as c4-test/probe): an echo on :7080, which answers its command's
# last argument (the container's name, in the fixtures' compose files), and the tools that try every
# way out of its network (curl, nmap, nc). Never deployed anywhere.
FROM caddy:2.11.4-alpine
RUN apk add --no-cache curl nmap netcat-openbsd
CMD ["caddy", "respond", "--listen", ":7080", "probe"]
