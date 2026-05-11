#!/bin/bash
# ============================================================
#  ssh-manager.sh — SSH access manager for collaborators
#  Compatible with EC2 Bitnami (user: bitnami)
# ============================================================

set -euo pipefail

# ---------- Config ----------
SSH_DIR="${SSH_DIR:-$HOME/.ssh}"
AUTH_KEYS="$SSH_DIR/authorized_keys"
KEYS_DIR="${KEYS_DIR:-$SSH_DIR/collaborators}"   # stores a copy of each public key
BACKUP_DIR="$SSH_DIR/.ssh_manager_backups"
LOG_FILE="$SSH_DIR/.ssh_manager.log"

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

# ---------- Helpers ----------
log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"; }
info() { echo -e "${CYAN}i${RESET}  $*"; }
ok()   { echo -e "${GREEN}✓${RESET}  $*"; log "OK: $*"; }
warn() { echo -e "${YELLOW}!${RESET}  $*"; log "WARN: $*"; }
err()  { echo -e "${RED}✗${RESET}  $*" >&2; log "ERR: $*"; }
die()  { err "$*"; exit 1; }

ensure_dirs() {
  mkdir -p "$KEYS_DIR" "$BACKUP_DIR"
  touch "$AUTH_KEYS" "$LOG_FILE"
  chmod 700 "$SSH_DIR"
  chmod 600 "$AUTH_KEYS"
}

backup_auth_keys() {
  local ts; ts=$(date '+%Y%m%d_%H%M%S')
  cp "$AUTH_KEYS" "$BACKUP_DIR/authorized_keys.$ts"
}

# Returns 0 if collaborator is active (not prefixed with #DISABLED)
is_enabled() {
  local name="$1"
  grep -q "^[^#].*#collab:${name}$" "$AUTH_KEYS" 2>/dev/null
}

is_disabled() {
  local name="$1"
  grep -q "^#DISABLED.*#collab:${name}$" "$AUTH_KEYS" 2>/dev/null
}

exists_collab() {
  local name="$1"
  grep -q "#collab:${name}$" "$AUTH_KEYS" 2>/dev/null
}

# ---------- Commands ----------

cmd_list() {
  ensure_dirs
  echo ""
  echo -e "${BOLD}  Collaborators with SSH access${RESET}"
  echo "  ────────────────────────────────────────"

  local found=0
  while IFS= read -r line; do
    if [[ "$line" =~ \#collab:([^[:space:]]+)$ ]]; then
      local name="${BASH_REMATCH[1]}"
      if [[ "$line" =~ ^#DISABLED ]]; then
        echo -e "  ${RED}●${RESET} ${BOLD}${name}${RESET}  [disabled]"
      else
        local fingerprint
        fingerprint=$(echo "$line" | ssh-keygen -lf /dev/stdin 2>/dev/null | awk '{print $2}' || echo "—")
        echo -e "  ${GREEN}●${RESET} ${BOLD}${name}${RESET}  [active]   $fingerprint"
      fi
      ((found++))
    fi
  done < "$AUTH_KEYS"

  if [[ $found -eq 0 ]]; then
    warn "No collaborators registered yet."
    echo "  Use: ssh-manager add <name>"
  fi
  echo ""
}

cmd_add() {
  local name="${1:-}"
  [[ -z "$name" ]] && die "Usage: ssh-manager add <name> [public-key]"

  ensure_dirs
  exists_collab "$name" && die "Collaborator '$name' already exists. Use 'update' to replace their key."

  local pubkey=""

  # Mode 1: key passed directly as second argument
  if [[ -n "${2:-}" ]]; then
    pubkey="${2}"

  # Mode 2: key coming from stdin (pipe or heredoc)
  elif ! [ -t 0 ]; then
    pubkey=$(cat)

  # Mode 3: interactive — prompt the user to paste the key
  else
    echo -e "${CYAN}Paste the public key for '${name}' and press Enter:${RESET}"
    echo -e "${YELLOW}(single line starting with ssh-rsa, ssh-ed25519, ecdsa-sha2-*, etc.)${RESET}"
    echo -n "> "
    read -r pubkey
  fi

  # Strip trailing whitespace / carriage returns
  pubkey=$(echo "$pubkey" | tr -d '\r' | xargs)

  [[ -z "$pubkey" ]] && die "No key received."

  # Basic format validation
  if ! echo "$pubkey" | grep -qE '^(ssh-rsa|ssh-ed25519|ssh-dss|ecdsa-sha2-nistp(256|384|521)) '; then
    die "Key doesn't look valid. It must start with ssh-rsa, ssh-ed25519, ecdsa-sha2-*, etc."
  fi

  # Deeper validation with ssh-keygen if available
  if command -v ssh-keygen &>/dev/null; then
    echo "$pubkey" | ssh-keygen -lf /dev/stdin &>/dev/null \
      || die "ssh-keygen rejected the key. Make sure it's complete and has no line breaks."
  fi

  backup_auth_keys

  # Append to authorized_keys with collaborator tag
  echo "${pubkey} #collab:${name}" >> "$AUTH_KEYS"

  # Save a copy in the collaborators folder
  echo "$pubkey" > "$KEYS_DIR/${name}.pub"

  ok "Collaborator '${name}' added and enabled."
  log "ADD: $name"
}

cmd_update() {
  local name="${1:-}"
  [[ -z "$name" ]] && die "Usage: ssh-manager update <name> [public-key]"

  ensure_dirs
  exists_collab "$name" || die "Collaborator '$name' not found. Use 'add' to register them first."

  local pubkey=""

  # Mode 1: key passed directly as second argument
  if [[ -n "${2:-}" ]]; then
    pubkey="${2}"

  # Mode 2: key coming from stdin (pipe or heredoc)
  elif ! [ -t 0 ]; then
    pubkey=$(cat)

  # Mode 3: interactive — prompt the user to paste the new key
  else
    echo -e "${CYAN}Paste the new public key for '${name}' and press Enter:${RESET}"
    echo -e "${YELLOW}(single line starting with ssh-rsa, ssh-ed25519, ecdsa-sha2-*, etc.)${RESET}"
    echo -n "> "
    read -r pubkey
  fi

  # Strip trailing whitespace / carriage returns
  pubkey=$(echo "$pubkey" | tr -d '\r' | xargs)

  [[ -z "$pubkey" ]] && die "No key received."

  # Basic format validation
  if ! echo "$pubkey" | grep -qE '^(ssh-rsa|ssh-ed25519|ssh-dss|ecdsa-sha2-nistp(256|384|521)) '; then
    die "Key doesn't look valid. It must start with ssh-rsa, ssh-ed25519, ecdsa-sha2-*, etc."
  fi

  # Deeper validation with ssh-keygen if available
  if command -v ssh-keygen &>/dev/null; then
    echo "$pubkey" | ssh-keygen -lf /dev/stdin &>/dev/null \
      || die "ssh-keygen rejected the key. Make sure it's complete and has no line breaks."
  fi

  backup_auth_keys

  # Preserve disabled state if the collaborator was disabled
  local was_disabled=false
  is_disabled "$name" && was_disabled=true

  # Replace the existing line (whether enabled or disabled) with the new key (enabled)
  sed -i "/#collab:${name}$/d" "$AUTH_KEYS"
  echo "${pubkey} #collab:${name}" >> "$AUTH_KEYS"

  # Update the saved copy
  echo "$pubkey" > "$KEYS_DIR/${name}.pub"

  # Re-disable if they were disabled before
  if $was_disabled; then
    sed -i "s|^\(.*#collab:${name}\)$|#DISABLED \1|" "$AUTH_KEYS"
    ok "Key updated for '${name}' (still disabled)."
  else
    ok "Key updated for '${name}'."
  fi

  log "UPDATE: $name"
}

cmd_enable() {
  local name="${1:-}"
  [[ -z "$name" ]] && die "Usage: ssh-manager enable <name>"
  ensure_dirs
  exists_collab "$name" || die "Collaborator '$name' not found."

  if is_enabled "$name"; then
    warn "'${name}' is already enabled."
    return 0
  fi

  backup_auth_keys
  # Remove the #DISABLED prefix
  sed -i "s|^#DISABLED \(.*#collab:${name}\)$|\1|" "$AUTH_KEYS"
  ok "SSH access enabled for '${name}'."
  log "ENABLE: $name"
}

cmd_disable() {
  local name="${1:-}"
  [[ -z "$name" ]] && die "Usage: ssh-manager disable <name>"
  ensure_dirs
  exists_collab "$name" || die "Collaborator '$name' not found."

  if is_disabled "$name"; then
    warn "'${name}' is already disabled."
    return 0
  fi

  backup_auth_keys
  # Prefix the line with #DISABLED (key is kept, just blocked)
  sed -i "s|^\(.*#collab:${name}\)$|#DISABLED \1|" "$AUTH_KEYS"
  ok "SSH access disabled for '${name}'."
  log "DISABLE: $name"
}

cmd_remove() {
  local name="${1:-}"
  [[ -z "$name" ]] && die "Usage: ssh-manager remove <name>"
  ensure_dirs
  exists_collab "$name" || die "Collaborator '$name' not found."

  echo -ne "${YELLOW}Permanently remove '${name}'? [y/N]:${RESET} "
  read -r confirm
  [[ "$confirm" =~ ^[yY]$ ]] || { info "Cancelled."; return 0; }

  backup_auth_keys
  sed -i "/#collab:${name}$/d" "$AUTH_KEYS"
  [[ -f "$KEYS_DIR/${name}.pub" ]] && rm -f "$KEYS_DIR/${name}.pub"
  ok "Collaborator '${name}' removed."
  log "REMOVE: $name"
}

cmd_show() {
  local name="${1:-}"
  [[ -z "$name" ]] && die "Usage: ssh-manager show <name>"
  ensure_dirs
  exists_collab "$name" || die "Collaborator '$name' not found."

  echo ""
  local line; line=$(grep "#collab:${name}$" "$AUTH_KEYS")
  local status
  if [[ "$line" =~ ^#DISABLED ]]; then
    status="${RED}disabled${RESET}"
  else
    status="${GREEN}active${RESET}"
  fi

  echo -e "  ${BOLD}Name:${RESET}         $name"
  echo -e "  ${BOLD}Status:${RESET}       $status"
  if [[ -f "$KEYS_DIR/${name}.pub" ]]; then
    local fp; fp=$(ssh-keygen -lf "$KEYS_DIR/${name}.pub" 2>/dev/null || echo "—")
    echo -e "  ${BOLD}Fingerprint:${RESET}  $fp"
  fi
  echo ""
}

cmd_backup_list() {
  ensure_dirs
  echo ""
  echo -e "${BOLD}  Available backups${RESET}"
  echo "  ────────────────────────"
  ls -lt "$BACKUP_DIR" 2>/dev/null | grep "authorized_keys\." \
    | awk '{print "  "$NF" ("$5" bytes, "$6" "$7" "$8")"}' \
    || warn "No backups yet."
  echo ""
}

cmd_restore() {
  local file="${1:-}"
  [[ -z "$file" ]] && die "Usage: ssh-manager restore <backup-filename>"
  local path="$BACKUP_DIR/$file"
  [[ -f "$path" ]] || die "Backup not found: $path"

  echo -ne "${YELLOW}Restore '$file'? This will overwrite authorized_keys. [y/N]:${RESET} "
  read -r confirm
  [[ "$confirm" =~ ^[yY]$ ]] || { info "Cancelled."; return 0; }

  backup_auth_keys
  cp "$path" "$AUTH_KEYS"
  chmod 600 "$AUTH_KEYS"
  ok "Restored from $file."
  log "RESTORE: $file"
}

cmd_help() {
  echo ""
  echo -e "  ${BOLD}╔══════════════════════════════════════════╗${RESET}"
  echo -e "  ${BOLD}║        ssh-manager  v1.0                 ║${RESET}"
  echo -e "  ${BOLD}║  SSH access manager for collaborators    ║${RESET}"
  echo -e "  ${BOLD}╚══════════════════════════════════════════╝${RESET}"
  echo ""
  echo -e "  ${BOLD}Usage:${RESET}  ssh-manager <command> [name] [key]"
  echo ""
  echo -e "  ${CYAN}┌─ Collaborators ────────────────────────────────────────────┐${RESET}"
  echo -e "  ${CYAN}│${RESET}  ${GREEN}list${RESET}              List all collaborators and their status  ${CYAN}│${RESET}"
  echo -e "  ${CYAN}│${RESET}  ${GREEN}add    <name>${RESET}     Add a new collaborator                   ${CYAN}│${RESET}"
  echo -e "  ${CYAN}│${RESET}  ${GREEN}update <name>${RESET}     Replace a collaborator's SSH key         ${CYAN}│${RESET}"
  echo -e "  ${CYAN}│${RESET}  ${GREEN}enable <name>${RESET}     Enable SSH access                        ${CYAN}│${RESET}"
  echo -e "  ${CYAN}│${RESET}  ${GREEN}disable <name>${RESET}    Disable SSH access (key kept on file)    ${CYAN}│${RESET}"
  echo -e "  ${CYAN}│${RESET}  ${GREEN}remove <name>${RESET}     Permanently delete a collaborator        ${CYAN}│${RESET}"
  echo -e "  ${CYAN}│${RESET}  ${GREEN}show <name>${RESET}       Show details and fingerprint             ${CYAN}│${RESET}"
  echo -e "  ${CYAN}└────────────────────────────────────────────────────────────┘${RESET}"
  echo ""
  echo -e "  ${CYAN}┌─ Backups ──────────────────────────────────────────────────┐${RESET}"
  echo -e "  ${CYAN}│${RESET}  ${GREEN}backups${RESET}           List available backups                  ${CYAN}│${RESET}"
  echo -e "  ${CYAN}│${RESET}  ${GREEN}restore <file>${RESET}    Restore a specific backup               ${CYAN}│${RESET}"
  echo -e "  ${CYAN}└────────────────────────────────────────────────────────────┘${RESET}"
  echo ""
  echo -e "  ${CYAN}┌─ add / update accept 3 input modes ───────────────────────┐${RESET}"
  echo -e "  ${CYAN}│${RESET}  ${YELLOW}ssh-manager add juan${RESET}                    ← interactive    ${CYAN}│${RESET}"
  echo -e "  ${CYAN}│${RESET}  ${YELLOW}ssh-manager add juan 'ssh-ed25519 AAAA...'${RESET} ← inline key   ${CYAN}│${RESET}"
  echo -e "  ${CYAN}│${RESET}  ${YELLOW}echo 'ssh-ed25519 AAAA...' | ssh-manager add juan${RESET} ← pipe  ${CYAN}│${RESET}"
  echo -e "  ${CYAN}└────────────────────────────────────────────────────────────┘${RESET}"
  echo ""
}

# ---------- Main ----------
ensure_dirs

case "${1:-help}" in
  list)           cmd_list ;;
  add)            cmd_add     "${2:-}" "${3:-}" ;;
  update)         cmd_update  "${2:-}" "${3:-}" ;;
  enable)         cmd_enable  "${2:-}" ;;
  disable)        cmd_disable "${2:-}" ;;
  remove|rm)      cmd_remove  "${2:-}" ;;
  show)           cmd_show    "${2:-}" ;;
  backups)        cmd_backup_list ;;
  restore)        cmd_restore "${2:-}" ;;
  help|--help|-h) cmd_help ;;
  *)              err "Unknown command: ${1}"; cmd_help; exit 1 ;;
esac
