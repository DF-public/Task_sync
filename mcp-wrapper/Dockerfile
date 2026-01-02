# =============================================================================
# Vikunja MCP HTTP Wrapper
# =============================================================================
# Wraps our custom vikunja-mcp STDIO server with mcp-proxy
# to expose it via HTTP/SSE for Claude Custom Connectors.
#
# Architecture:
#   Claude.ai → mcp-proxy:8080 (HTTP/SSE) → vikunja-mcp (STDIO) → Vikunja API
#
# Build context must be the repo root:
#   docker build -f mcp-wrapper/Dockerfile .
# =============================================================================

FROM node:20-alpine

# Install Python and mcp-proxy
RUN apk add --no-cache python3 py3-pip curl && \
    pip3 install --break-system-packages mcp-proxy

# Create app directory
WORKDIR /app

# Copy custom MCP server code (build context is repo root)
COPY mcp-server/package.json ./
COPY mcp-server/src ./src/

# Copy HTTP proxy wrapper
COPY mcp-wrapper/proxy.js ./proxy.js
COPY mcp-wrapper/start.sh ./start.sh
RUN chmod +x ./start.sh

# Install dependencies
RUN npm install --omit=dev

# Create non-root user
RUN addgroup -g 1001 -S mcp && \
    adduser -S mcp -u 1001 -G mcp && \
    chown -R mcp:mcp /app

USER mcp

# Health check - use /mcp endpoint with timeout (SSE keeps connections open)
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s \
    CMD curl -sf --max-time 5 -o /dev/null http://localhost:8080/mcp || exit 1

EXPOSE 8080

# Environment defaults (our custom server uses VIKUNJA_API_URL with /api/v1 suffix)
ENV VIKUNJA_API_URL="" \
    VIKUNJA_API_TOKEN="" \
    LOG_LEVEL="info"

# Run the startup script which:
# 1. Starts mcp-proxy on port 8081 (internal)
# 2. Starts HTTP proxy on port 8080 (handles HEAD requests for Claude)
CMD ["./start.sh"]
