#!/usr/bin/env bash
# mac-maintenance.sh — routine macOS housekeeping, safe for unattended launchd runs
set -euo pipefail

# ── Config ─────────────────────────────────────────────────────────────────────
LOG_DIR="$HOME/Library/Logs/mac-maintenance"
LOG_FILE="$LOG_DIR/$(date +%Y-%m-%d).log"
DRY_RUN=false
LARGE_FILE_MIN_MB=100
LARGE_FILE_MAX_AGE_DAYS=365

# Curated safe cache paths (no blanket wipe)
USER_CACHE_PATHS=(
  "$HOME/Library/Caches/com.apple.Safari"
  "$HOME/Library/Caches/com.apple.mail"
  "$HOME/Library/Caches/com.apple.Music"
  "$HOME/Library/Caches/com.apple.TV"
  "$HOME/Library/Caches/com.apple.dt.Xcode"
  "$HOME/Library/Caches/Homebrew"
  "$HOME/Library/Caches/pip"
  "$HOME/Library/Caches/com.microsoft.VSCode"
  "$HOME/Library/Caches/Google/Chrome/Default/Cache"
  "$HOME/Library/Caches/Firefox/Profiles"
  "$HOME/Library/Caches/JetBrains"
)

USER_LOG_PATHS=(
  "$HOME/Library/Logs/Homebrew"
  "$HOME/Library/Logs/CoreSimulator"
  "$HOME/Library/Logs/DiagnosticReports"
)

XCODE_DERIVED_DATA="$HOME/Library/Developer/Xcode/DerivedData"
XCODE_ARCHIVES="$HOME/Library/Developer/Xcode/Archives"    # reported only, not deleted
IOS_DEVICE_SUPPORT="$HOME/Library/Developer/Xcode/iOS DeviceSupport"
SIMULATOR_RUNTIMES="$HOME/Library/Developer/CoreSimulator/Caches/dyld"

# ── Helpers ─────────────────────────────────────────────────────────────────────
log() { echo "[$(date '+%H:%M:%S')] $*" | tee -a "$LOG_FILE"; }
log_section() { log ""; log "═══ $* ═══"; }

dry() {
  if $DRY_RUN; then
    log "  [DRY-RUN] $*"
  else
    eval "$@"
  fi
}

human_size() {
  # print du output in human-readable form; works without GNU coreutils
  du -sh "$1" 2>/dev/null | cut -f1
}

delete_path() {
  local path="$1"
  if [[ -e "$path" || -L "$path" ]]; then
    local size
    size=$(human_size "$path")
    log "  Removing $path ($size)"
    dry "rm -rf $(printf '%q' "$path")"
  fi
}

delete_contents() {
  local dir="$1"
  if [[ -d "$dir" ]]; then
    local size
    size=$(human_size "$dir")
    log "  Clearing contents of $dir ($size)"
    # Delete entries individually so the directory itself is preserved
    dry "find $(printf '%q' "$dir") -mindepth 1 -maxdepth 1 -exec rm -rf {} +"
  fi
}

require_sudo() {
  if [[ $EUID -ne 0 ]]; then
    log "  [SKIP] Requires sudo — re-run with sudo or via launchd as root"
    return 1
  fi
  return 0
}

# ── Argument parsing ─────────────────────────────────────────────────────────────
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    --help)
      echo "Usage: mac-maintenance.sh [--dry-run]"
      echo "  --dry-run   Print what would be deleted/run without making changes"
      exit 0 ;;
    *) echo "Unknown argument: $arg" >&2; exit 1 ;;
  esac
done

# ── Setup ─────────────────────────────────────────────────────────────────────
mkdir -p "$LOG_DIR"
log "╔══════════════════════════════════════════╗"
log "  mac-maintenance  $(date '+%Y-%m-%d %H:%M:%S')"
$DRY_RUN && log "  MODE: DRY-RUN (nothing will be changed)"
log "╚══════════════════════════════════════════╝"

# ── 1. User cache clearing ───────────────────────────────────────────────────────
log_section "User cache clearing"
for path in "${USER_CACHE_PATHS[@]}"; do
  if [[ -e "$path" ]]; then
    delete_contents "$path"
  fi
done

# ── 2. User log clearing ─────────────────────────────────────────────────────────
log_section "User log clearing"
for path in "${USER_LOG_PATHS[@]}"; do
  if [[ -d "$path" ]]; then
    # Only delete files older than 7 days to avoid clobbering active logs
    log "  Pruning logs older than 7 days in $path"
    dry "find $(printf '%q' "$path") -type f -mtime +7 -delete"
  fi
done

# ── 3. Xcode artifacts ───────────────────────────────────────────────────────────
log_section "Xcode artifacts"

if [[ -d "$XCODE_DERIVED_DATA" ]]; then
  log "  Clearing DerivedData"
  delete_contents "$XCODE_DERIVED_DATA"
fi

if [[ -d "$IOS_DEVICE_SUPPORT" ]]; then
  log "  Clearing old iOS DeviceSupport (keeps nothing — re-downloaded on demand)"
  delete_contents "$IOS_DEVICE_SUPPORT"
fi

if [[ -d "$SIMULATOR_RUNTIMES" ]]; then
  log "  Clearing CoreSimulator dyld cache"
  delete_contents "$SIMULATOR_RUNTIMES"
fi

if [[ -d "$XCODE_ARCHIVES" ]]; then
  size=$(human_size "$XCODE_ARCHIVES")
  log "  Xcode Archives: $size — not deleted (manage via Xcode Organizer)"
fi

# ── 4. Homebrew cleanup ──────────────────────────────────────────────────────────
log_section "Homebrew cleanup"
if command -v brew &>/dev/null; then
  log "  brew cleanup --prune=all"
  dry "brew cleanup --prune=all 2>&1 | tee -a $(printf '%q' "$LOG_FILE")"
else
  log "  Homebrew not found — skipping"
fi

# ── 5. Trash emptying ───────────────────────────────────────────────────────────
log_section "Trash"
TRASH="$HOME/.Trash"
if [[ -d "$TRASH" ]] && [[ -n "$(ls -A "$TRASH" 2>/dev/null)" ]]; then
  size=$(human_size "$TRASH")
  log "  Emptying Trash ($size)"
  dry "rm -rf $(printf '%q' "$TRASH")/* $(printf '%q' "$TRASH")/.[!.]*"
else
  log "  Trash already empty"
fi

# ── 6. Periodic tasks ────────────────────────────────────────────────────────────
log_section "Periodic maintenance (daily / weekly / monthly)"
if require_sudo; then
  log "  Running: periodic daily weekly monthly"
  dry "periodic daily weekly monthly 2>&1 | tee -a $(printf '%q' "$LOG_FILE")"
fi

# ── 7. DNS cache flush ───────────────────────────────────────────────────────────
log_section "DNS cache flush"
# dscacheutil runs fine as a regular user; killall -HUP mDNSResponder requires root.
log "  dscacheutil -flushcache"
dry "dscacheutil -flushcache"
if [[ $EUID -eq 0 ]]; then
  log "  killall -HUP mDNSResponder"
  dry "killall -HUP mDNSResponder"
else
  log "  [SKIP] killall -HUP mDNSResponder requires sudo"
fi

# ── 8. locate database rebuild ───────────────────────────────────────────────────
log_section "locate database"
if require_sudo; then
  log "  Rebuilding locate database (background)"
  dry "sudo /usr/libexec/locate.updatedb &"
fi

# ── 9. Large/old file report ─────────────────────────────────────────────────────
log_section "Large file report (>=${LARGE_FILE_MIN_MB}MB, untouched ≥${LARGE_FILE_MAX_AGE_DAYS} days)"
REPORT_DIRS=("$HOME/Downloads" "$HOME/Documents" "$HOME/Desktop" "$HOME/Movies")
log "  Searching: ${REPORT_DIRS[*]}"
log "  ── Results ──"
find "${REPORT_DIRS[@]}" \
  -type f \
  -size +"${LARGE_FILE_MIN_MB}"M \
  -mtime +"${LARGE_FILE_MAX_AGE_DAYS}" \
  2>/dev/null \
| while IFS= read -r f; do
    size=$(du -sh "$f" 2>/dev/null | cut -f1)
    echo "  $size  $f"
  done \
| sort -rh \
| head -30 \
| tee -a "$LOG_FILE" \
|| true

# ── 10. Disk usage summary ───────────────────────────────────────────────────────
log_section "Disk usage summary"
df -h / | tee -a "$LOG_FILE"

# ── Done ─────────────────────────────────────────────────────────────────────────
log ""
log "Done. Log: $LOG_FILE"
