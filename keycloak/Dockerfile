# The shared Keycloak, in dev as on the demo host: one realm (or more) per application. Pinned to a
# version (intent 0013): a floating minor would let a rebuild change Keycloak unannounced, while the
# demo host's image is tagged by this directory's content.
ARG KC_VERSION=26.8.1

FROM quay.io/keycloak/keycloak:${KC_VERSION}

# Build-time options: PostgreSQL, served under /auth like each project's Keycloak was, health and
# metrics on the management port, a single node.
ENV KC_DB=postgres
ENV KC_HTTP_RELATIVE_PATH=/auth
ENV KC_HEALTH_ENABLED=true
ENV KC_METRICS_ENABLED=true
ENV KC_CACHE=local
# The features every application shares (intent 0013, README.md "Design"): the delegated token
# exchange and the parameterized scopes it uses (preview: Turu's agents act for a user, the token's
# act claim naming them), and the client ID metadata documents (experimental: an MCP client's
# registration by its URL, which a realm opts into with its client policies). Nothing else.
ENV KC_FEATURES=token-exchange-delegation,parameterized-scopes,cimd

# The stack's own login themes (the simulated providers' realms, intent 0016), a theme JAR among the
# providers: keycloak/themes/ is the applications', mounted whole over /opt/keycloak/themes. Built
# with the image's jar tool, before kc.sh build.
COPY --chown=keycloak:root stack-themes /opt/keycloak/stack-themes
RUN java -m jdk.jartool/sun.tools.jar.Main --create --file /opt/keycloak/providers/c4-infra-stack-themes.jar \
  -C /opt/keycloak/stack-themes .

RUN /opt/keycloak/bin/kc.sh build

# The healthcheck (the image has no curl), compiled once here rather than by every probe. The
# image ships a JRE without javac, but with the compiler module.
COPY --chown=keycloak:root HealthCheck.java /opt/keycloak/healthcheck/HealthCheck.java
RUN java -m jdk.compiler/com.sun.tools.javac.Main -d /opt/keycloak/healthcheck /opt/keycloak/healthcheck/HealthCheck.java
