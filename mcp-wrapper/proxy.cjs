/**
 * HTTP Proxy Wrapper for MCP Server with OAuth 2.1 Support
 *
 * Implements simplified OAuth for Claude Custom Connectors:
 * - /.well-known/oauth-authorization-server - OAuth metadata
 * - /register - Dynamic Client Registration (DCR)
 * - /authorize - Authorization endpoint
 * - /token - Token exchange
 * - /mcp - Protected MCP endpoint (requires Bearer token)
 */

const http = require('http');
const crypto = require('crypto');
const url = require('url');

const MCP_PROXY_PORT = 8081;
const LISTEN_PORT = 8080;

// OAuth configuration from environment
const OAUTH_CLIENT_ID = process.env.OAUTH_CLIENT_ID || 'claude-connector';
const OAUTH_CLIENT_SECRET = process.env.OAUTH_CLIENT_SECRET || 'default-secret-change-me';
const OAUTH_ISSUER = process.env.OAUTH_ISSUER || 'https://todo_mcp.smartautomatica.com';

// In-memory storage for auth codes and tokens
const authCodes = new Map(); // code -> { clientId, redirectUri, codeChallenge, expiresAt }
const accessTokens = new Map(); // token -> { clientId, expiresAt }

// Generate random string
function generateRandomString(length = 32) {
  return crypto.randomBytes(length).toString('hex');
}

// Clean up expired entries
function cleanupExpired() {
  const now = Date.now();
  for (const [key, value] of authCodes) {
    if (value.expiresAt < now) authCodes.delete(key);
  }
  for (const [key, value] of accessTokens) {
    if (value.expiresAt < now) accessTokens.delete(key);
  }
}
setInterval(cleanupExpired, 60000); // Clean up every minute

// Parse request body
function parseBody(req) {
  return new Promise((resolve, reject) => {
    let body = '';
    req.on('data', chunk => body += chunk);
    req.on('end', () => {
      try {
        const contentType = req.headers['content-type'] || '';
        if (contentType.includes('application/json')) {
          resolve(JSON.parse(body || '{}'));
        } else if (contentType.includes('application/x-www-form-urlencoded')) {
          resolve(Object.fromEntries(new URLSearchParams(body)));
        } else {
          resolve(body);
        }
      } catch (e) {
        reject(e);
      }
    });
    req.on('error', reject);
  });
}

// PKCE: Verify code challenge
function verifyCodeChallenge(codeVerifier, codeChallenge) {
  const hash = crypto.createHash('sha256').update(codeVerifier).digest();
  const computed = hash.toString('base64url');
  return computed === codeChallenge;
}

// Add CORS headers
function addCorsHeaders(res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, HEAD, OPTIONS, DELETE');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization, mcp-session-id, MCP-Protocol-Version, Accept');
  res.setHeader('Access-Control-Expose-Headers', 'mcp-session-id, MCP-Protocol-Version, WWW-Authenticate');
}

// Send JSON response
function sendJson(res, statusCode, data) {
  res.setHeader('Content-Type', 'application/json');
  res.writeHead(statusCode);
  res.end(JSON.stringify(data));
}

// Validate Bearer token
function validateToken(req) {
  const authHeader = req.headers['authorization'];
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return null;
  }
  const token = authHeader.slice(7);
  const tokenData = accessTokens.get(token);
  if (!tokenData || tokenData.expiresAt < Date.now()) {
    return null;
  }
  return tokenData;
}

const server = http.createServer(async (req, res) => {
  addCorsHeaders(res);

  const parsedUrl = url.parse(req.url, true);
  const pathname = parsedUrl.pathname;

  console.log(`${req.method} ${pathname}`);

  // Handle OPTIONS preflight
  if (req.method === 'OPTIONS') {
    res.setHeader('Access-Control-Max-Age', '86400');
    res.writeHead(200);
    res.end();
    return;
  }

  // OAuth Metadata Discovery
  if (pathname === '/.well-known/oauth-authorization-server') {
    sendJson(res, 200, {
      issuer: OAUTH_ISSUER,
      authorization_endpoint: `${OAUTH_ISSUER}/authorize`,
      token_endpoint: `${OAUTH_ISSUER}/token`,
      registration_endpoint: `${OAUTH_ISSUER}/register`,
      response_types_supported: ['code'],
      grant_types_supported: ['authorization_code'],
      code_challenge_methods_supported: ['S256'],
      token_endpoint_auth_methods_supported: ['client_secret_post', 'client_secret_basic'],
      scopes_supported: ['mcp'],
    });
    return;
  }

  // Dynamic Client Registration (DCR)
  if (pathname === '/register' && req.method === 'POST') {
    try {
      const body = await parseBody(req);
      console.log('DCR request:', JSON.stringify(body));

      // Return preconfigured client credentials
      sendJson(res, 201, {
        client_id: OAUTH_CLIENT_ID,
        client_secret: OAUTH_CLIENT_SECRET,
        client_name: body.client_name || 'Claude Connector',
        redirect_uris: body.redirect_uris || [],
        grant_types: ['authorization_code'],
        response_types: ['code'],
        token_endpoint_auth_method: 'client_secret_post',
      });
    } catch (e) {
      console.error('DCR error:', e);
      sendJson(res, 400, { error: 'invalid_request' });
    }
    return;
  }

  // Authorization Endpoint
  if (pathname === '/authorize' && req.method === 'GET') {
    const query = parsedUrl.query;
    const { client_id, redirect_uri, response_type, state, code_challenge, code_challenge_method } = query;

    console.log('Auth request:', JSON.stringify(query));

    // Validate request
    if (response_type !== 'code') {
      sendJson(res, 400, { error: 'unsupported_response_type' });
      return;
    }

    if (client_id !== OAUTH_CLIENT_ID) {
      sendJson(res, 400, { error: 'invalid_client' });
      return;
    }

    // Generate authorization code
    const code = generateRandomString(32);
    authCodes.set(code, {
      clientId: client_id,
      redirectUri: redirect_uri,
      codeChallenge: code_challenge,
      codeChallengeMethod: code_challenge_method,
      expiresAt: Date.now() + 5 * 60 * 1000, // 5 minutes
    });

    // Redirect back with code
    const redirectUrl = new URL(redirect_uri);
    redirectUrl.searchParams.set('code', code);
    if (state) redirectUrl.searchParams.set('state', state);

    console.log('Redirecting to:', redirectUrl.toString());
    res.writeHead(302, { Location: redirectUrl.toString() });
    res.end();
    return;
  }

  // Token Endpoint
  if (pathname === '/token' && req.method === 'POST') {
    try {
      const body = await parseBody(req);
      console.log('Token request:', JSON.stringify(body));

      const { grant_type, code, redirect_uri, client_id, client_secret, code_verifier } = body;

      if (grant_type !== 'authorization_code') {
        sendJson(res, 400, { error: 'unsupported_grant_type' });
        return;
      }

      // Validate auth code
      const codeData = authCodes.get(code);
      if (!codeData) {
        sendJson(res, 400, { error: 'invalid_grant', error_description: 'Invalid or expired code' });
        return;
      }

      // Validate client
      if (client_id !== OAUTH_CLIENT_ID || client_secret !== OAUTH_CLIENT_SECRET) {
        sendJson(res, 401, { error: 'invalid_client' });
        return;
      }

      // Validate PKCE if code challenge was provided
      if (codeData.codeChallenge && code_verifier) {
        if (!verifyCodeChallenge(code_verifier, codeData.codeChallenge)) {
          sendJson(res, 400, { error: 'invalid_grant', error_description: 'Invalid code_verifier' });
          return;
        }
      }

      // Delete used code
      authCodes.delete(code);

      // Generate access token
      const accessToken = generateRandomString(32);
      accessTokens.set(accessToken, {
        clientId: client_id,
        expiresAt: Date.now() + 60 * 60 * 1000, // 1 hour
      });

      sendJson(res, 200, {
        access_token: accessToken,
        token_type: 'Bearer',
        expires_in: 3600,
        scope: 'mcp',
      });
    } catch (e) {
      console.error('Token error:', e);
      sendJson(res, 400, { error: 'invalid_request' });
    }
    return;
  }

  // HEAD request for MCP protocol version
  if (req.method === 'HEAD') {
    res.setHeader('MCP-Protocol-Version', '2025-06-18');
    res.setHeader('Content-Type', 'application/json');
    res.writeHead(200);
    res.end();
    return;
  }

  // Protected MCP endpoints - require Bearer token
  if (pathname === '/mcp' || pathname.startsWith('/mcp/')) {
    const tokenData = validateToken(req);
    if (!tokenData) {
      res.setHeader('WWW-Authenticate', `Bearer realm="${OAUTH_ISSUER}", resource_metadata="${OAUTH_ISSUER}/.well-known/oauth-authorization-server"`);
      sendJson(res, 401, { error: 'unauthorized', error_description: 'Valid Bearer token required' });
      return;
    }

    // Proxy to mcp-proxy
    const proxyReq = http.request(
      {
        hostname: '127.0.0.1',
        port: MCP_PROXY_PORT,
        path: req.url,
        method: req.method,
        headers: req.headers,
      },
      (proxyRes) => {
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
    return;
  }

  // Fallback - 404
  sendJson(res, 404, { error: 'not_found' });
});

server.listen(LISTEN_PORT, '0.0.0.0', () => {
  console.log(`MCP OAuth Proxy listening on port ${LISTEN_PORT}`);
  console.log(`OAuth Issuer: ${OAUTH_ISSUER}`);
  console.log(`Client ID: ${OAUTH_CLIENT_ID}`);
  console.log(`Proxying MCP to port ${MCP_PROXY_PORT}`);
});
