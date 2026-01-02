/**
 * HTTP Proxy Wrapper for MCP Server
 *
 * Handles HEAD requests (required by Claude Custom Connectors)
 * and proxies all other requests to mcp-proxy.
 */

const http = require('http');

const MCP_PROXY_PORT = 8081; // mcp-proxy runs on this port
const LISTEN_PORT = 8080;    // We listen on this port

const server = http.createServer((req, res) => {
  // Add CORS headers to all responses
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, HEAD, OPTIONS, DELETE');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, mcp-session-id, MCP-Protocol-Version, Accept');

  // Handle HEAD requests - Claude uses this to validate the server
  if (req.method === 'HEAD') {
    res.setHeader('MCP-Protocol-Version', '2025-06-18');
    res.setHeader('Content-Type', 'application/json');
    res.writeHead(200);
    res.end();
    return;
  }

  // Handle OPTIONS preflight
  if (req.method === 'OPTIONS') {
    res.setHeader('Access-Control-Max-Age', '86400');
    res.writeHead(200);
    res.end('OK');
    return;
  }

  // Proxy all other requests to mcp-proxy
  const proxyReq = http.request(
    {
      hostname: '127.0.0.1',
      port: MCP_PROXY_PORT,
      path: req.url,
      method: req.method,
      headers: req.headers,
    },
    (proxyRes) => {
      // Copy headers from proxy response
      Object.keys(proxyRes.headers).forEach((key) => {
        res.setHeader(key, proxyRes.headers[key]);
      });
      res.writeHead(proxyRes.statusCode);
      proxyRes.pipe(res);
    }
  );

  proxyReq.on('error', (err) => {
    console.error('Proxy error:', err.message);
    res.writeHead(502);
    res.end('Bad Gateway');
  });

  req.pipe(proxyReq);
});

server.listen(LISTEN_PORT, '0.0.0.0', () => {
  console.log(`MCP HTTP Proxy listening on port ${LISTEN_PORT}`);
  console.log(`Proxying to mcp-proxy on port ${MCP_PROXY_PORT}`);
});
