# =============================================================================
# Vikunja MCP Server Dockerfile
# =============================================================================
# Multi-stage build for the MCP server that integrates Vikunja with Claude Code.
# =============================================================================

# Build stage
FROM node:20-alpine AS builder

WORKDIR /app

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm ci --only=production

# Production stage
FROM node:20-alpine

WORKDIR /app

# Install curl for health checks
RUN apk add --no-cache curl tini

# Copy dependencies from builder
COPY --from=builder /app/node_modules ./node_modules

# Copy application code
COPY package*.json ./
COPY src ./src

# Create non-root user
RUN addgroup -g 1001 -S mcp && \
    adduser -S mcp -u 1001 -G mcp

USER mcp

# Environment defaults
ENV NODE_ENV=production \
    LOG_LEVEL=info \
    MCP_SERVER_PORT=3100

# Expose MCP server port
EXPOSE 3100

# Use tini for proper signal handling
ENTRYPOINT ["/sbin/tini", "--"]

# Start the MCP server
CMD ["node", "src/index.js"]
