
# --------------------------------------------------
# Stage 1: Dependency installation
# --------------------------------------------------
FROM node:22.14.0-alpine3.21 AS dependencies

WORKDIR /app

COPY package.json package-lock.json ./

# Install production dependencies only
RUN npm ci --omit=dev --ignore-scripts \
    && npm cache clean --force


# --------------------------------------------------
# Stage 2: Production runtime
# --------------------------------------------------
FROM node:22.14.0-alpine3.21 AS runtime

# OCI image metadata
LABEL org.opencontainers.image.title="DevOps Task Service" \
      org.opencontainers.image.description="Node.js REST API with Prometheus metrics and health checks" \
      org.opencontainers.image.version="1.0.0" \
      org.opencontainers.image.vendor="DevOps Task" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.source="https://github.com/OWNER/REPOSITORY" \
      org.opencontainers.image.base.name="node:22.14.0-alpine3.21"

WORKDIR /app

# Copy only production dependencies
COPY --from=dependencies --chown=node:node /app/node_modules ./node_modules

# Copy application source
COPY --chown=node:node package.json ./
COPY --chown=node:node src ./src

# Runtime configuration defaults
ENV NODE_ENV=production \
    PORT=3000 \
    LOG_LEVEL=info \
    ENVIRONMENT=production \
    APP_VERSION=1.0.0

EXPOSE 3000

# Run as non-root user
USER node

# Docker health check
HEALTHCHECK --interval=30s \
            --timeout=5s \
            --start-period=10s \
            --retries=3 \
    CMD node -e "fetch('http://127.0.0.1:' + (process.env.PORT || 3000) + '/health').then(r => process.exit(r.ok ? 0 : 1)).catch(() => process.exit(1))"

# Start application
CMD ["node", "src/server.js"]
