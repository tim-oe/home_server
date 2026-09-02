# Obsidian Remote

Runs [Obsidian](https://obsidian.md/) in the browser via [obsidian-remote](https://github.com/sytone/obsidian-remote), a Docker image that serves a full Obsidian desktop over a guacamole/RDP WebSocket session.

Access at: `https://obsidian.tecronin.uk`

## Volume layout

| Host path | Container path | Purpose |
|---|---|---|
| `./vaults` | `/vaults` | Local writable directory — required so the container init can `chown` it. Not used for vault storage. |
| `/mnt/brain` | `/brain` | NFS network share. Open vaults from `/brain/<vault>` inside Obsidian. |
| `obsidian-config` (named volume) | `/config` | Obsidian config, plugins, and xrdp session state. Persists across restarts. |

### Why the split vault layout

The container's linuxserver.io init always tries to `chown /vaults` to its internal user. The NFS share at `/mnt/brain` is mounted with `root_squash`, so `chown` is not permitted. Mounting the NFS share directly at `/vaults` causes the init to exit with an error, which cascades to break the openbox window manager setup and prevent the desktop from starting.

The fix: mount a local writable directory at `/vaults` (so `chown` succeeds), and mount the NFS share separately at `/brain`. Inside Obsidian, use **Open folder as vault** → `/brain/<vault>`.

## Vault structure convention

```
/mnt/brain/vault/
  <project-name>/          # per-project notes (e.g. home_server/)
    acceptance/            # acceptance criteria for features/stories
    adr/                   # architectural decision records
    specs/                 # feature specifications
  common/                  # shared knowledge across all projects
    standards/             # coding standards, review checklists
    patterns/              # design patterns and conventions
    glossary/              # shared terminology
```

A Cursor rule at `~/.cursor/rules/obsidian-vault-context.mdc` makes the AI automatically reference these notes during code reviews and feature work — pulling in acceptance criteria, ADRs, and shared standards as context.

## Opening your vault

1. Navigate to `https://obsidian.tecronin.uk`
2. In the Obsidian remote desktop, click **Open folder as vault**
3. Navigate to `/brain/vault` (or whichever subfolder you created on the share)

## Deployment

```bash
# Deploy service files
./gradlew deployObsidian

# On the server — first deploy only
mkdir -p /mnt/raid/services/obsidian/vaults

# Start the container
cd /mnt/raid/services/obsidian
docker compose up -d
```

## Updating

```bash
cd /mnt/raid/services/obsidian
docker compose pull
docker compose down && docker compose up -d
```

> **Note:** Obsidian updates itself in-place inside the running container. If the container is recreated, Obsidian will prompt to update again on first launch.
