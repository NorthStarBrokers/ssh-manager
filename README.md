# ssh-manager

SSH access manager for collaborators on EC2 / Linux servers.

Manages `authorized_keys` entries without ever deleting keys permanently — disabling a collaborator just blocks them, keeping the key on file for easy re-enabling. Every destructive operation creates an automatic backup.

---

## Installation

Run this on each server:

```bash
curl -fsSL https://raw.githubusercontent.com/YOUR-ORG/ssh-manager/main/ssh-manager.sh \
  -o /usr/local/bin/ssh-manager && chmod +x /usr/local/bin/ssh-manager
```

> Replace `YOUR-ORG` with your GitHub organization name.

**Requirements:** `bash`, `ssh-keygen` — both present on any standard Linux / Bitnami EC2.

---

## Usage

```
ssh-manager <command> [arguments]
```

### Commands

| Command | Description |
|---|---|
| `list` | List all collaborators and their status |
| `add <name>` | Add a new collaborator |
| `update <name>` | Replace a collaborator's SSH key |
| `enable <name>` | Enable SSH access |
| `disable <name>` | Disable SSH access (key is kept, not deleted) |
| `remove <name>` | Permanently remove a collaborator |
| `show <name>` | Show details and fingerprint for a collaborator |
| `backups` | List available authorized_keys backups |
| `restore <file>` | Restore a specific backup |

---

## Adding a collaborator — 3 input modes

**Interactive** (prompts you to paste the key):
```bash
ssh-manager add juan
```

**Inline** (key passed directly as argument):
```bash
ssh-manager add juan 'ssh-ed25519 AAAA...'
```

**Pipe / stdin:**
```bash
echo 'ssh-ed25519 AAAA...' | ssh-manager add juan
```

The same three modes work for `update`.

---

## Examples

```bash
# Add a collaborator
ssh-manager add maria 'ssh-ed25519 AAAAC3Nza...'

# Replace their key
ssh-manager update maria 'ssh-ed25519 AAAAC3Nzb...'

# Temporarily block access
ssh-manager disable maria

# Re-enable later
ssh-manager enable maria

# Check who has access
ssh-manager list

# See details for one collaborator
ssh-manager show maria

# Permanently remove
ssh-manager remove maria

# View backups
ssh-manager backups

# Restore a backup
ssh-manager restore authorized_keys.20250510_143022
```

---

## How it works

Each collaborator entry in `authorized_keys` is tagged with a comment:

```
ssh-ed25519 AAAA... #collab:maria          ← active
#DISABLED ssh-ed25519 AAAA... #collab:juan ← disabled
```

- **Disable** prefixes the line with `#DISABLED` — SSH ignores it, but the key is preserved.
- **Update** replaces the key and preserves the enabled/disabled state.
- **Remove** deletes the line entirely.
- A copy of each public key is saved under `~/.ssh/collaborators/<name>.pub`.
- Every write operation backs up `authorized_keys` to `~/.ssh/.ssh_manager_backups/`.

---

## Environment variables

| Variable | Default | Description |
|---|---|---|
| `SSH_DIR` | `~/.ssh` | SSH directory |
| `KEYS_DIR` | `~/.ssh/collaborators` | Folder where public key copies are stored |

---

## Updating the script

To pull the latest version on a server:

```bash
curl -fsSL https://raw.githubusercontent.com/YOUR-ORG/ssh-manager/main/ssh-manager.sh \
  -o /usr/local/bin/ssh-manager && chmod +x /usr/local/bin/ssh-manager
```

Same install command — it overwrites the existing version.
