#!/bin/sh
# Start mcp-proxy in background on port 8081
mcp-proxy --port 8081 --host 127.0.0.1 --pass-environment --allow-origin='*' node src/index.js &

# Wait for mcp-proxy to start
sleep 2

# Start HTTP proxy on port 8080 (foreground)
node /app/proxy.js
