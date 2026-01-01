# Unified Task Sync - CasaOS App Store

Custom CasaOS app store for the Unified Task Sync project.

## Available Apps

| App | Description | Category |
|-----|-------------|----------|
| **Vikunja** | Self-hosted task management | Utilities |

## Installation

### Adding This App Store to CasaOS

1. Open your CasaOS dashboard
2. Navigate to the **App Store**
3. Click **Add Source** (top right, above the apps list)
4. Paste the following URL:

```
https://github.com/DF_public/unified-task-sync/releases/latest/download/casaos-appstore.zip
```

5. Click **Add** and wait for installation

> **Note:** Custom app stores require CasaOS version 0.4.4 or higher.

### Alternative: Manual Installation

1. Download the app's `docker-compose.yml` from the `Apps/` directory
2. In CasaOS, go to App Store > **Custom Install**
3. Upload or paste the docker-compose content

## Post-Installation Setup

After installing Vikunja:

1. **Access the Web UI** at `http://your-casaos-ip:3456`
2. **Create your account**
3. **Secure the installation:**
   - Edit the app settings in CasaOS
   - Change `VIKUNJA_SERVICE_JWTSECRET` to a random string
   - Change database passwords
   - Set `VIKUNJA_SERVICE_ENABLEREGISTRATION` to `false`

## Requirements

- CasaOS 0.4.4 or higher
- 512MB RAM minimum (1GB recommended)
- 1GB storage for database and files

## Support

For issues with this app store, please open an issue at:
https://github.com/DF_public/unified-task-sync/issues

## License

AGPL-3.0 - See [LICENSE](../LICENSE) for details.
