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
    echo "  Use: $0 add <name>"
  fi
  echo ""
}

cmd_add() {
  local name="${1:-}"
  [[ -z "$name" ]] && die "Usage: $0 add <name> [public-key]"

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
  [[ -z "$name" ]] && die "Usage: $0 update <name> [public-key]"

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
  [[ -z "$name" ]] && die "Usage: $0 enable <name>"
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
  [[ -z "$name" ]] && die "Usage: $0 disable <name>"
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
  [[ -z "$name" ]] && die "Usage: $0 remove <name>"
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
  [[ -z "$name" ]] && die "Usage: $0 show <name>"
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
  [[ -z "$file" ]] && die "Usage: $0 restore <backup-filename>"
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
  echo -e "${BOLD}  ssh-manager — SSH access manager for collaborators${RESET}"
  echo ""
  echo "  Usage: $0 <command> [arguments]"
  echo ""
  echo -e "  ${CYAN}Main commands:${RESET}"
  echo "    list               List all collaborators and their status"
  echo "    add    <name>      Add a collaborator (3 input modes, see below)"
  echo "    update <name>      Replace a collaborator's SSH key (keeps enabled/disabled state)"
  echo "    enable  <name>     Enable SSH access"
  echo "    disable <name>     Disable SSH access (key is kept, not deleted)"
  echo "    remove  <name>     Permanently remove a collaborator"
  echo "    show    <name>     Show details for a collaborator"
  echo ""
  echo -e "  ${CYAN}Backups:${RESET}"
  echo "    backups            List available authorized_keys backups"
  echo "    restore <file>     Restore a specific backup"
  echo ""
  echo -e "  ${CYAN}Environment variables:${RESET}"
  echo "    SSH_DIR    SSH directory       (default: ~/.ssh)"
  echo "    KEYS_DIR   Public keys folder  (default: ~/.ssh/collaborators)"
  echo ""
  echo -e "  ${CYAN}add / update — 3 input modes:${RESET}"
  echo "    $0 add    juan                                # interactive: prompts to paste the key"
  echo "    $0 add    juan 'ssh-ed25519 AAAA...'          # key passed directly as argument"
  echo "    echo 'ssh-ed25519 AAAA...' | $0 add    juan  # key via stdin / pipe"
  echo "    $0 update juan 'ssh-ed25519 AAAA_new...'     # same modes work for update"
  echo ""
  echo -e "  ${CYAN}More examples:${RESET}"
  echo "    $0 disable juan"
  echo "    $0 enable  juan"
  echo "    $0 list"
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
