# The shared reverse proxy, in dev as on the demo host: Caddy with the rate-limit module (intent
# 0013: the realms' client registration endpoint, caddy/Caddyfile), which the stock image hasn't.
# The module is pinned by commit: its last tag (v0.1.0) is far behind; Dependabot doesn't follow it.
ARG CADDY_VERSION=2.11.4

FROM caddy:${CADDY_VERSION}-builder-alpine AS build
RUN xcaddy build --with github.com/mholt/caddy-ratelimit@5625512f24f6

FROM caddy:${CADDY_VERSION}-alpine
COPY --from=build /usr/bin/caddy /usr/bin/caddy
