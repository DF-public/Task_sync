# Installation Guide

Complete installation guide for Unified Task Sync with Claude Code MCP integration.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Detailed Installation](#detailed-installation)
- [Claude Code Integration](#claude-code-integration)
- [Cloudflare Tunnel Setup](#cloudflare-tunnel-setup)
- [Sync Configuration](#sync-configuration)
- [Verification](#verification)
- [Troubleshooting](#troubleshooting)

---

## Prerequisites

### System Requirements

- **OS:** Linux (Ubuntu 20.04+, Debian 11+, or similar)
- **RAM:** 2GB minimum (4GB recommended)
- **Storage:** 10GB free space
- **Docker:** 20.10+ with Docker Compose v2
- **Network:** Internet access for container pulls

### Software Requirements

```bash
# Verify Docker installation
docker --version
docker compose version

# Install if needed (Ubuntu/Debian)
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
```

### Optional Requirements

- **CasaOS:** 0.4.4+ for app store integration
- **Cloudflare account:** For Zero Trust tunnel (remote access)
- **Claude Code CLI:** For AI-assisted task management

---

## Quick Start

For basic local deployment:

```bash
# 1. Clone repository
git clone https://github.com/DF_public/unified-task-sync.git
cd unified-task-sync

# 2. Configure environment
cp .env.example .env

# 3. Generate secrets
echo "VIKUNJA_SERVICE_JWTSECRET=$(openssl rand -base64 32)" >> .env
echo "MYSQL_ROOT_PASSWORD=$(openssl rand -base64 24)" >> .env
echo "MYSQL_PASSWORD=$(openssl rand -base64 24)" >> .env

# 4. Start core services
docker compose up -d vikunja db

# 5. Access Vikunja
open http://localhost:3456
```

---

## Detailed Installation

### Step 1: Clone and Configure

```bash
# Clone the repository
git clone https://github.com/DF_public/unified-task-sync.git
cd unified-task-sync

# Copy environment template
cp .env.example .env

# Edit configuration
nano .env  # or use your preferred editor
```

### Step 2: Generate Secure Secrets

```bash
# Generate all required secrets
cat >> .env << EOF

# Generated secrets - $(date)
VIKUNJA_SERVICE_JWTSECRET=$(openssl rand -base64 32)
MYSQL_ROOT_PASSWORD=$(openssl rand -base64 24)
MYSQL_PASSWORD=$(openssl rand -base64 24)
MCP_AUTH_TOKEN=$(openssl rand -hex 32)
EOF
```

### Step 3: Start Core Services

```bash
# Start Vikunja and database
docker compose up -d vikunja db

# Wait for services to be ready
docker compose logs -f vikunja
# Press Ctrl+C when you see "Starting server..."
```

### Step 4: Initial Vikunja Setup

1. Open http://localhost:3456 in your browser
2. Create your admin account
3. Go to **Settings > API Tokens**
4. Create a new API token with full permissions
5. Copy the token and add to `.env`:

```bash
echo "VIKUNJA_API_TOKEN=your-token-here" >> .env
```

### Step 5: Start MCP Server

```bash
# Build and start MCP server
docker compose up -d vikunja-mcp

# Verify it's running
docker compose ps vikunja-mcp
curl http://localhost:3100/health
```

---

## Claude Code Integration

### Install Claude Code

```bash
# Install globally via npm
npm install -g @anthropic-ai/claude-code

# Or use npx
npx @anthropic-ai/claude-code
```

### Configure MCP Connection

```bash
# Run the configuration script
./scripts/configure-mcp.sh --local

# Or for remote access via Cloudflare tunnel
./scripts/configure-mcp.sh --remote mcp.yourdomain.com
```

### Authorize Claude Code

```bash
# Check authorization status
./scripts/authorize-claude-code.sh --status

# Set up authorization
./scripts/authorize-claude-code.sh --login
```

### Test MCP Integration

```bash
# Start Claude Code
claude

# In Claude Code, test the connection
/mcp
# Should show "vikunja" as an available server

# Try a command
"List all my Vikunja projects"
```

---

## Cloudflare Tunnel Setup

For secure remote access to MCP server.

### Step 1: Create Tunnel in Cloudflare

1. Go to [Cloudflare Zero Trust Dashboard](https://one.dash.cloudflare.com/)
2. Navigate to **Access > Tunnels**
3. Click **Create a tunnel**
4. Name it `unified-task-sync`
5. Copy the tunnel token

### Step 2: Configure Tunnel

```bash
# Add tunnel token to .env
echo "CLOUDFLARE_TUNNEL_TOKEN=your-token" >> .env
echo "MCP_DOMAIN=mcp.yourdomain.com" >> .env
```

### Step 3: Configure Public Hostname

In Cloudflare dashboard:
1. Select your tunnel
2. Click **Configure**
3. Add public hostname:
   - **Subdomain:** mcp
   - **Domain:** yourdomain.com
   - **Service:** http://vikunja-mcp:3100

### Step 4: Start Tunnel

```bash
# Start with tunnel profile
docker compose --profile tunnel up -d

# Verify tunnel is connected
docker compose logs cloudflared
```

### Step 5: Configure Access Policy (Recommended)

1. Go to **Access > Applications**
2. Create new application
3. Set URL to your MCP domain
4. Configure authentication (e.g., email OTP, SSO)

---

## Sync Configuration

### YouTrack Integration

1. In YouTrack, go to **Profile > Authentication > Tokens**
2. Create new token with read access
3. Add to `.env`:

```bash
YOUTRACK_URL=https://youtrack.example.com
YOUTRACK_TOKEN=your-token
```

### Jira Integration

1. Go to [Atlassian API Tokens](https://id.atlassian.com/manage-profile/security/api-tokens)
2. Create new API token
3. Add to `.env`:

```bash
JIRA_URL=https://company.atlassian.net
JIRA_EMAIL=your-email@example.com
JIRA_TOKEN=your-token
```

### Enable Scheduled Sync

```bash
# Start sync scheduler
docker compose --profile scheduler up -d

# Check sync logs
docker compose logs sync-scheduler
```

### Manual Sync

```bash
# Run sync manually
./scripts/sync-tasks.sh --source all --verbose

# Dry run (no changes)
./scripts/sync-tasks.sh --dry-run
```

---

## Verification

### Health Checks

```bash
# Check all services
docker compose ps

# Check Vikunja
curl -s http://localhost:3456/api/v1/info | jq

# Check MCP server
curl -s http://localhost:3100/health

# Check database
docker compose exec db mysql -u vikunja -p -e "SELECT 1"
```

### Test Sync

```bash
# Test YouTrack connection
./scripts/sync-tasks.sh --source youtrack --dry-run

# Test Jira connection
./scripts/sync-tasks.sh --source jira --dry-run
```

### View Logs

```bash
# All services
docker compose logs

# Specific service
docker compose logs vikunja-mcp

# Follow logs
docker compose logs -f

# Sync logs
docker compose exec sync-scheduler cat /var/log/sync/cron.log
```

---

## Troubleshooting

### Common Issues

#### MCP Server Won't Start

```bash
# Check logs
docker compose logs vikunja-mcp

# Verify Vikunja is running
curl http://localhost:3456/api/v1/info

# Rebuild
docker compose build vikunja-mcp
docker compose up -d vikunja-mcp
```

#### Database Connection Errors

```bash
# Check database is running
docker compose ps db

# Check database logs
docker compose logs db

# Reset database (WARNING: destroys data)
docker compose down -v
docker compose up -d
```

#### Cloudflare Tunnel Not Connecting

```bash
# Check tunnel logs
docker compose logs cloudflared

# Verify token is set
grep CLOUDFLARE_TUNNEL_TOKEN .env

# Restart tunnel
docker compose --profile tunnel restart cloudflared
```

#### Sync Failing

```bash
# Check configuration
./scripts/sync-tasks.sh --dry-run --verbose

# Verify API tokens are valid
curl -H "Authorization: Bearer $YOUTRACK_TOKEN" $YOUTRACK_URL/api/issues

# Check Vikunja API token
curl -H "Authorization: Bearer $VIKUNJA_API_TOKEN" http://localhost:3456/api/v1/user
```

### Reset Everything

```bash
# Stop all services
docker compose --profile tunnel --profile scheduler down

# Remove volumes (WARNING: destroys all data)
docker compose down -v

# Start fresh
docker compose up -d
```

### Get Help

- **Issues:** https://github.com/DF_public/unified-task-sync/issues
- **Vikunja Docs:** https://vikunja.io/docs/
- **Claude Code Docs:** https://docs.anthropic.com/en/docs/claude-code

---

## Security Best Practices

1. **Never commit `.env` files** - Always use `.env.example` as template
2. **Rotate tokens regularly** - Regenerate API tokens periodically
3. **Use Cloudflare Access** - Protect remote MCP endpoints with authentication
4. **Disable registration** - Set `VIKUNJA_SERVICE_ENABLEREGISTRATION=false` after setup
5. **Use strong passwords** - Generate with `openssl rand -base64 24`
6. **Keep containers updated** - Run `docker compose pull` regularly
