# Diagnostic CLI image
#   docker build -t diagnostic-tool .
#   docker run --rm diagnostic-tool system
FROM debian:bookworm-slim

LABEL org.opencontainers.image.title="diagnostic" \
      org.opencontainers.image.description="Bash diagnostic tool: system, network and disk checks"

# Tools used by the 'network' command (ping, nc). getent and df ship with the base image.
RUN apt-get update \
    && apt-get install -y --no-install-recommends iputils-ping netcat-openbsd \
    && rm -rf /var/lib/apt/lists/*

# Run as an unprivileged user
RUN useradd --system --create-home --shell /usr/sbin/nologin diag

WORKDIR /app
COPY app/ /app/
RUN chmod 0755 /app/diagnostic.sh /app/health-check.sh \
    && ln -s /app/diagnostic.sh /usr/local/bin/diagnostic

USER diag

HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
    CMD ["/app/health-check.sh"]

# `docker run diagnostic system`  ->  diagnostic system
ENTRYPOINT ["diagnostic"]
CMD ["help"]
