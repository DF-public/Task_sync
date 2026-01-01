# =============================================================================
# Vikunja MCP HTTP Wrapper
# =============================================================================
# Wraps the @democratize-technology/vikunja-mcp STDIO server with mcp-proxy
# to expose it via HTTP/SSE for Claude Custom Connectors.
#
# Architecture:
#   Claude.ai → mcp-proxy:8080 (HTTP/SSE) → vikunja-mcp (STDIO) → Vikunja API
# =============================================================================

FROM node:20-alpine

# Install Python and mcp-proxy
RUN apk add --no-cache python3 py3-pip curl && \
    pip3 install --break-system-packages mcp-proxy

# Install vikunja-mcp globally
RUN npm install -g @democratize-technology/vikunja-mcp

# Create non-root user
RUN addgroup -g 1001 -S mcp && \
    adduser -S mcp -u 1001 -G mcp

USER mcp

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s \
    CMD curl -f http://localhost:8080/sse || exit 1

EXPOSE 8080

# Environment defaults
ENV VIKUNJA_URL="" \
    VIKUNJA_API_TOKEN="" \
    LOG_LEVEL="info"

# Run mcp-proxy wrapping vikunja-mcp
# --pass-environment ensures VIKUNJA_URL and VIKUNJA_API_TOKEN are passed to vikunja-mcp
ENTRYPOINT ["mcp-proxy", "--port", "8080", "--host", "0.0.0.0", "--pass-environment"]
CMD ["vikunja-mcp"]
