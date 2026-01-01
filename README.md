# Unified Task Sync

**Consolidate tasks from multiple project management systems into one self-hosted interface**

[![Docker](https://img.shields.io/badge/Docker-Compose-2496ED?logo=docker&logoColor=white)](https://docs.docker.com/compose/)
[![Claude Code](https://img.shields.io/badge/Claude%20Code-MCP-7C3AED?logo=anthropic&logoColor=white)](https://claude.ai)
[![Self-Hosted](https://img.shields.io/badge/Self--Hosted-Privacy%20First-22C55E?logo=homeassistant&logoColor=white)](https://vikunja.io)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](./LICENSE)

---

## Why This Project?

### The Problem

As a technical consultant working with multiple clients, I faced a common challenge:

- **Client 1** uses YouTrack for project management
- **Client 2** uses Jira for issue tracking
- **My personal projects** live in various places

Switching between systems throughout the day creates cognitive overhead. Worse, consolidating tasks in a third-party tool (like Todoist or Notion) risks exposing sensitive client information.

### The Solution

**Unified Task Sync** provides a single pane of glass for all your tasks:

- **Self-hosted** on your own infrastructure (no data leaves your network)
- **Privacy-first** design (sync only task titles, not sensitive descriptions)
- **Automated** synchronization using Claude Code CLI and MCP servers
- **Zero-trust** security configuration (separate tokens, minimal permissions)

### Benefits

| For Consultants | For Developers | For Security-Conscious |
|-----------------|----------------|------------------------|
| One view of all client work | Extensible with MCP | Data stays on-premises |
| No context switching | Scriptable automation | Minimal API permissions |
| Professional time tracking | Docker-native | Audit-friendly |

---

## Features

- **Self-hosted with Vikunja** - Open-source, privacy-respecting task management
- **Automated daily sync via Claude Code + MCP** - Hands-off synchronization
- **Privacy-first design** - Only task titles synced, no descriptions or attachments
- **Bidirectional status sync** - Complete tasks anywhere, sync everywhere
- **Zero-trust security** - Separate read-only tokens, minimal API scopes
- **CasaOS compatible** - Easy deployment on home servers

---

## Tech Stack

| Component | Technology | Purpose |
|-----------|------------|---------|
| **Task Manager** | [Vikunja](https://vikunja.io) | Self-hosted task management UI |
| **Database** | MariaDB 10.x | Persistent data storage |
| **Orchestration** | [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) | AI-powered automation |
| **Sync Protocol** | [MCP Servers](https://modelcontextprotocol.io) | YouTrack & Atlassian integration |
| **Infrastructure** | Docker Compose | Container orchestration |
| **Hosting** | [CasaOS](https://casaos.io) | Home server platform |

---

## Quick Start

> **Note:** Detailed installation guide coming in Phase 2. Below is the basic setup.

### Prerequisites

- Docker & Docker Compose installed
- 1GB RAM minimum (2GB recommended)
- CasaOS (optional, for home server deployment)

### Installation

1. **Clone the repository**
   ```bash
   git clone https://github.com/DF_public/unified-task-sync.git
   cd unified-task-sync
   ```

2. **Configure environment**
   ```bash
   cp .env.example .env

   # Generate secure secrets
   echo "VIKUNJA_SERVICE_JWTSECRET=$(openssl rand -base64 32)" >> .env
   echo "MYSQL_ROOT_PASSWORD=$(openssl rand -base64 24)" >> .env
   echo "MYSQL_PASSWORD=$(openssl rand -base64 24)" >> .env
   ```

3. **Start services**
   ```bash
   docker-compose up -d
   ```

4. **Access Vikunja**

   Open http://localhost:3456 and create your first account.

### Verify Installation

```bash
# Check running containers
docker-compose ps

# View logs
docker-compose logs -f vikunja
```

---

## Architecture

```
                    +------------------+
                    |   Your Browser   |
                    +--------+---------+
                             |
                             v
+----------------------------+----------------------------+
|                     CasaOS / Docker Host                |
|                                                         |
|  +----------------+          +----------------------+   |
|  |    Vikunja     |<-------->|      MariaDB         |   |
|  |   (Port 3456)  |          |   (Internal Only)    |   |
|  +-------+--------+          +----------------------+   |
|          ^                                              |
|          |  API                                         |
|          v                                              |
|  +-------+--------+                                     |
|  |  Claude Code   |                                     |
|  |  + MCP Servers |                                     |
|  +-------+--------+                                     |
|          |                                              |
+----------+----------------------------------------------+
           |
           v
    +------+------+          +-------------+
    |  YouTrack   |          |    Jira     |
    |   (MCP)     |          |   (MCP)     |
    +-------------+          +-------------+
```

> Detailed architecture documentation: [docs/architecture.md](./docs/architecture.md)

---

## Project Structure

```
unified-task-sync/
├── README.md              # This file
├── LICENSE                # MIT License
├── .gitignore             # Security-conscious exclusions
├── docker-compose.yml     # Vikunja + MariaDB configuration
├── .env.example           # Environment template (never commit .env!)
├── docs/
│   ├── architecture.md    # System architecture details
│   ├── INSTALLATION.md    # Detailed setup guide
│   └── screenshots/       # Visual documentation
└── scripts/               # Automation scripts (Phase 2)
```

---

## Roadmap

### Phase 1: Foundation (Day 1)
- [x] Repository structure and documentation
- [x] Docker Compose configuration for Vikunja
- [x] Security-first `.gitignore` and `.env.example`
- [x] Professional README

### Phase 2: Automation (Day 2)
- [ ] Claude Code slash command (`/sync-tasks`)
- [ ] MCP server configuration (`.mcp.json`)
- [ ] Sync script (`scripts/sync.sh`)
- [ ] Zero-trust configuration script
- [ ] Complete installation guide

### Phase 3: Polish (Day 3)
- [ ] End-to-end testing
- [ ] Screenshots and visual documentation
- [ ] Performance optimization
- [ ] Troubleshooting guide

### Future Ideas
- [ ] Webhook support for real-time sync
- [ ] Additional MCP integrations (GitHub Issues, Linear)
- [ ] Mobile-friendly dashboard
- [ ] Sync conflict resolution UI

---

## Security Considerations

This project follows zero-trust principles:

| Practice | Implementation |
|----------|----------------|
| **Minimal permissions** | Read-only tokens for source systems |
| **Data minimization** | Only task titles synced (no descriptions) |
| **Network isolation** | Database not exposed to host |
| **Secret management** | All secrets in `.env`, never committed |
| **Audit trail** | Sync operations logged with timestamps |

### What's NOT Synced (by design)

- Task descriptions (may contain sensitive client info)
- Attachments
- Comments
- Internal project metadata

---

## Contributing

This is a personal portfolio project demonstrating:
- Self-hosted infrastructure design
- AI-assisted automation with Claude Code
- Security-first development practices

**Issues and suggestions are welcome!** If you find this useful or have ideas for improvement, please open an issue.

---

## Related Projects

- [Vikunja](https://vikunja.io) - The open-source task manager powering this project
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) - CLI tool for AI-assisted development
- [Model Context Protocol](https://modelcontextprotocol.io) - The protocol enabling MCP integrations

---

## License

This project is licensed under the MIT License - see the [LICENSE](./LICENSE) file for details.

---

<p align="center">
  <sub>Built with self-hosting principles and AI automation</sub>
</p>
