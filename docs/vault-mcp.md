# Vault MCP Server for Cursor

A lightweight MCP (Model Context Protocol) server that exposes a local markdown
vault to Cursor AI. The AI can search, read, and write notes automatically
during code reviews and feature work — no manual `@` file references needed.

Designed around a per-project vault structure with shared common knowledge:

```
<VAULT_PATH>/
  <project>/
    acceptance/    ← acceptance criteria for features/stories
    adr/           ← architectural decision records
    specs/         ← feature specifications
  common/          ← shared across all projects
    standards/     ← coding standards, review checklists
    patterns/      ← design patterns and conventions
    glossary/      ← shared terminology
```

---

## vault used:

[obsidian](https://obsidian.md/)

## Prerequisites

- Python 3.10+
- [uv](https://docs.astral.sh/uv/) — Python package runner (like npx for Python)

### Install uv

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
source ~/.local/bin/env
```

---

## Setup

### 1. Create the server directory

```bash
mkdir -p ~/.cursor/mcp-vault
```

### 2. Create `~/.cursor/mcp-vault/pyproject.toml`

```toml
[project]
name = "vault-server"
version = "0.1.0"
requires-python = ">=3.10"
dependencies = ["mcp[cli]>=1.0.0"]
```

### 3. Create `~/.cursor/mcp-vault/vault_server.py`

```python
"""
Vault MCP server — exposes a local markdown vault to Cursor AI.

Set the VAULT_ROOT environment variable to point at your vault, or update the
default path in the fallback below.

Vault layout expected:
  VAULT_ROOT/
    <project>/
      acceptance/   ← acceptance criteria
      adr/          ← architectural decision records
      specs/        ← feature specifications
    common/         ← shared knowledge across projects
"""

import os
from pathlib import Path
from mcp.server.fastmcp import FastMCP

# Set VAULT_ROOT env var or replace the fallback path with your vault location
VAULT_ROOT = Path(os.environ.get("VAULT_ROOT", "/path/to/your/vault"))  # <-- SET THIS

mcp = FastMCP("vault")


def _rel(path: Path) -> str:
    return str(path.relative_to(VAULT_ROOT))


def _note_files(root: Path) -> list[Path]:
    if not root.exists():
        return []
    return sorted(root.rglob("*.md"))


@mcp.tool()
def list_notes(project: str = "", folder: str = "") -> str:
    """List notes in the vault, optionally scoped to a project and/or subfolder.

    Args:
        project: Project name (e.g. 'my-project') or 'common'. Empty = all.
        folder:  Subfolder within the project (e.g. 'acceptance', 'adr', 'specs').
    """
    base = VAULT_ROOT
    if project:
        base = base / project
    if folder:
        base = base / folder
    files = _note_files(base)
    if not files:
        return f"No notes found under '{base}'"
    return "\n".join(_rel(f) for f in files)


@mcp.tool()
def read_note(path: str) -> str:
    """Read the full contents of a vault note.

    Args:
        path: Path relative to vault root (e.g. 'my-project/acceptance/feature.md').
    """
    target = VAULT_ROOT / path
    if not target.exists():
        return f"Note not found: {path}"
    return target.read_text(encoding="utf-8")


@mcp.tool()
def search_notes(query: str, project: str = "") -> str:
    """Search vault notes by filename or content (case-insensitive).

    Args:
        query:   Search term.
        project: Limit search to a project folder. Empty = search all.
    """
    base = VAULT_ROOT / project if project else VAULT_ROOT
    files = _note_files(base)
    q = query.lower()
    results: list[str] = []
    for f in files:
        rel = _rel(f)
        try:
            content = f.read_text(encoding="utf-8")
        except Exception:
            continue
        if q in rel.lower() or q in content.lower():
            snippet = next(
                (line.strip() for line in content.splitlines() if q in line.lower()),
                "(matched in filename)",
            )
            results.append(f"{rel}\n  → {snippet}")
    if not results:
        return f"No notes matching '{query}'"
    return "\n".join(results)


@mcp.tool()
def get_acceptance_criteria(project: str) -> str:
    """Return all acceptance criteria notes for a project, concatenated.

    Args:
        project: Project name (e.g. 'my-project').
    """
    base = VAULT_ROOT / project / "acceptance"
    files = _note_files(base)
    if not files:
        return f"No acceptance criteria found for project '{project}'"
    parts = []
    for f in files:
        parts.append(f"# {_rel(f)}\n")
        parts.append(f.read_text(encoding="utf-8"))
        parts.append("\n---\n")
    return "\n".join(parts)


@mcp.tool()
def write_note(path: str, content: str, overwrite: bool = False) -> str:
    """Create or update a vault note.

    Args:
        path:      Path relative to vault root (e.g. 'my-project/acceptance/feature.md').
        content:   Full markdown content to write.
        overwrite: If false (default), refuses to overwrite an existing note.
    """
    target = VAULT_ROOT / path
    if target.exists() and not overwrite:
        return f"Note already exists: {path}. Pass overwrite=true to replace it."
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(content, encoding="utf-8")
    return f"Written: {path}"


def main():
    mcp.run()


if __name__ == "__main__":
    main()
```

### 4. Create `~/.cursor/mcp.json`

```json
{
  "mcpServers": {
    "vault": {
      "command": "/home/<USER>/.local/bin/uv",
      "args": [
        "run",
        "--directory", "/home/<USER>/.cursor/mcp-vault",
        "python", "vault_server.py"
      ],
      "env": {
        "VAULT_ROOT": "/path/to/your/vault"
      }
    }
  }
}
```

Replace `<USER>` with your username and set `VAULT_ROOT` to your vault path.
If `uv` is on your `PATH` you can use `"command": "uv"` instead of the full path.

### 5. Create the vault folder structure

```bash
mkdir -p /path/to/your/vault/my-project/{acceptance,adr,specs}
mkdir -p /path/to/your/vault/common/{standards,patterns,glossary}
```

### 6. Restart Cursor

`Ctrl+Shift+P` → `Developer: Reload Window`

The `vault` server should appear as active in the MCP panel.

---

## Cursor rule

Create `~/.cursor/rules/vault-context.mdc` to make the AI use the vault
automatically across all projects:

```markdown
---
description: Use vault notes as acceptance criteria and project context during code reviews and feature work
alwaysApply: true
---

# Vault Context

The vault is the source of truth for project specs, acceptance criteria, and
shared engineering standards. Use the vault MCP tools to access it.

## Vault structure

VAULT_ROOT/
  <project>/
    acceptance/    ← acceptance criteria for features/stories
    adr/           ← architectural decision records
    specs/         ← feature specifications
  common/          ← shared knowledge across all projects
    standards/     ← coding standards, review checklists
    patterns/      ← design patterns and conventions
    glossary/      ← shared terminology

## During code and PR reviews

1. Call `get_acceptance_criteria` or `search_notes` to find criteria relevant
   to the changes being reviewed.
2. Check `common/standards/` for shared review standards.
3. Explicitly report which acceptance criteria pass or fail.
4. If no note exists for the feature being reviewed, flag it as a gap and
   offer to create one with `write_note`.

## During feature implementation

- Call `search_notes` to find specs and ADRs before writing code.
- Call `list_notes` with folder="adr" to check prior architectural decisions.
- Call `write_note` to capture new ADRs or decisions as they are made.

## Acceptance criteria note format

# <Feature name>

## Acceptance criteria
- [ ] <criterion>
- [ ] <criterion>

## Out of scope
- <item>

## References
- <link to spec, ticket, etc.>
```

---

## Available MCP tools

| Tool | Description |
|---|---|
| `list_notes` | List notes, optionally scoped to a `project` and/or `folder` |
| `read_note` | Read a note by path relative to vault root |
| `search_notes` | Case-insensitive search across filenames and content |
| `get_acceptance_criteria` | All AC notes for a project concatenated |
| `write_note` | Create or update a note (safe by default — won't overwrite without `overwrite=true`) |

---

## Obsidian Remote (optional)

[obsidian-remote](https://github.com/sytone/obsidian-remote) runs Obsidian as
a full desktop in the browser via a guacamole/RDP WebSocket session. It is
**not required** for the MCP integration — the MCP server reads vault files
directly from the filesystem. Use obsidian-remote if you want browser-based
access to the Obsidian UI (graph view, plugins, etc.) from any device.

### Example `docker-compose.yml`

The image's init script always tries to `chown /vaults` to its internal user.
If your vault lives on an NFS share with `root_squash` this will fail and break
the desktop startup. The workaround is to mount a local writable directory at
`/vaults` (so the `chown` succeeds) and mount your actual vault storage at a
separate path (e.g. `/brain`). Inside Obsidian, open the vault from `/brain`.

```yaml
# https://github.com/sytone/obsidian-remote
services:
  obsidian:
    image: ghcr.io/sytone/obsidian-remote:latest
    container_name: obsidian
    hostname: obsidian
    restart: unless-stopped
    ports:
      - 8954:8080
    volumes:
      - ./vaults:/vaults:rw          # local writable dir — satisfies chown on init
      - /path/to/your/vault:/brain:rw  # <-- SET THIS: your vault storage
      - obsidian-config:/config:rw
      - /etc/timezone:/etc/timezone:ro
      - /etc/localtime:/etc/localtime:ro
    environment:
      - TZ=Europe/London             # <-- SET THIS: your timezone
volumes:
  obsidian-config:
    name: obsidian-config
```

> If your vault is on a **local filesystem** (not NFS) you can mount it
> directly at `/vaults` and skip the split layout.

### Routing

Routing is [Traefik](../src/services/traefik/README.md) labels on the container itself, so there is
no separate proxy config to edit:

```yaml
    labels:
      - traefik.enable=true
      - traefik.http.routers.obsidian.rule=Host(`obsidian.example.com`)  # <-- SET THIS
      - traefik.http.routers.obsidian.entrypoints=websecure
      - traefik.http.services.obsidian.loadbalancer.server.port=8080
```

The guacamole session needs a WebSocket upgrade over a long-lived, unbuffered connection. Traefik
performs the upgrade automatically and does not buffer, so the `proxy_http_version 1.1`,
`Connection`/`Upgrade` headers, `proxy_buffering off` and hour-long `proxy_read_timeout` that the
old nginx vhost required have no equivalent to set here.

### First launch

1. Start the container: `docker compose up -d`
2. Open `https://obsidian.example.com` in a browser
3. In the Obsidian desktop, click **Open folder as vault** and navigate to `/brain`

---

## Troubleshooting

**Server not appearing in MCP panel**

Check `uv` is reachable and the server starts without errors:
```bash
cd ~/.cursor/mcp-vault
uv run python vault_server.py
```

**`VAULT_ROOT` not found errors**

Ensure the `env.VAULT_ROOT` value in `mcp.json` points at an existing directory.

**Slow first start**

`uv` downloads and caches `mcp[cli]` on first run. Subsequent starts are instant.
