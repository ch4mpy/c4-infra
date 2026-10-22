# The shared Keycloak, in dev as on the demo host: one realm (or more) per application.
ARG KC_VERSION=26.7

FROM quay.io/keycloak/keycloak:${KC_VERSION}

# Build-time options: PostgreSQL, served under /auth like each project's Keycloak was, health and
# metrics on the management port, a single node.
ENV KC_DB=postgres
ENV KC_HTTP_RELATIVE_PATH=/auth
ENV KC_HEALTH_ENABLED=true
ENV KC_METRICS_ENABLED=true
ENV KC_CACHE=local

RUN /opt/keycloak/bin/kc.sh build

# The healthcheck (the image has no curl), compiled once here rather than by every probe. The
# image ships a JRE without javac, but with the compiler module.
COPY --chown=keycloak:root HealthCheck.java /opt/keycloak/healthcheck/HealthCheck.java
RUN java -m jdk.compiler/com.sun.tools.javac.Main -d /opt/keycloak/healthcheck /opt/keycloak/healthcheck/HealthCheck.java
