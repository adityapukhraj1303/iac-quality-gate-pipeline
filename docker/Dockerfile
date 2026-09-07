# ==============================================================================
# Hardened Alpine Base for Bash HTTP Microservice
# ==============================================================================
FROM alpine:3.19

# Install runtime dependencies (bash, socat, curl for health checks)
RUN apk update && apk add --no-cache \
    bash \
    socat \
    curl \
    coreutils \
    tzdata \
    && rm -rf /var/cache/apk/*

WORKDIR /app

# Copy application files
COPY app/server.sh /app/server.sh
COPY app/VERSION /app/VERSION

# Security hardening: Run as non-root user
RUN chmod +x /app/server.sh && \
    addgroup -g 10001 -S appgroup && \
    adduser -u 10001 -S appuser -G appgroup && \
    chown -R appuser:appgroup /app

USER appuser

EXPOSE 8080

ENV PORT=8080

HEALTHCHECK --interval=10s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

ENTRYPOINT ["/bin/bash", "/app/server.sh"]
