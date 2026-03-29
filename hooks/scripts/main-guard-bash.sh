#!/usr/bin/env bash
# Main Guard Bash Hook
# Main Agent가 Bash를 통해 코드 파일을 수정하는 것을 차단합니다.
# PreToolUse Hook (Bash 매처)
#
# 핵심 로직:
# - Subagent 스택이 비어있으면 = Main Agent가 직접 호출
# - .baton/ 파일 외 코드 파일에 대한 쓰기 명령 차단
# - 읽기 전용 명령은 허용

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/find-baton-root.sh"
source "$SCRIPT_DIR/stdin-reader.sh"

ensure_baton_dirs

LOG_FILE="$BATON_LOG_DIR/main-guard-bash.log"
AGENT_STACK_FILE="$BATON_LOG_DIR/.agent-stack"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

block() {
  log "BLOCKED: $1"
  echo "$1" >&2
  exit 2
}

# Subagent 실행 중인지 확인
is_subagent_active() {
  if [ -f "$AGENT_STACK_FILE" ] 2>/dev/null && [ -s "$AGENT_STACK_FILE" ] 2>/dev/null; then
    return 0
  fi
  return 1
}

# Check if the command targets only .baton/ paths for write operations
targets_only_baton() {
  local cmd="$1"

  # Redirect targets: check what's after > or >>
  # If all redirects go to .baton/ paths, it's safe
  if [[ "$cmd" =~ \>{1,2}[[:space:]]*([^[:space:]|;&]+) ]]; then
    local target="${BASH_REMATCH[1]}"
    if [[ "$target" == *.baton/* ]] || [[ "$target" == .baton/* ]] || [[ "$target" == */\.baton/* ]]; then
      return 0
    fi
    return 1
  fi

  return 0
}

# Check if command is safe (read-only or allowed operations)
is_safe_command() {
  local cmd="$1"

  # Strip leading whitespace
  cmd="${cmd#"${cmd%%[![:space:]]*}"}"

  # git commands — all allowed
  if [[ "$cmd" =~ ^git[[:space:]] ]] || [[ "$cmd" == "git" ]]; then
    return 0
  fi

  # Directory/navigation commands
  if [[ "$cmd" =~ ^(mkdir|touch|ls|pwd|cd|tree|which|type|command|where|file|stat|wc|du|df)[[:space:]] ]] || \
     [[ "$cmd" =~ ^(mkdir|touch|ls|pwd|cd|tree|which|type|command|where|file|stat|wc|du|df)$ ]]; then
    return 0
  fi

  # Read-only commands (without redirection to non-.baton files)
  if [[ "$cmd" =~ ^(cat|head|tail|less|more|bat)[[:space:]] ]] && ! [[ "$cmd" =~ \>{1,2} ]]; then
    return 0
  fi

  # echo to stdout only (no redirection to non-.baton files)
  if [[ "$cmd" =~ ^(echo|printf)[[:space:]] ]] && ! [[ "$cmd" =~ \>{1,2} ]]; then
    return 0
  fi

  # echo/cat with redirection to .baton/ or /tmp/ or /dev/ paths
  if [[ "$cmd" =~ ^(echo|printf|cat)[[:space:]] ]] && [[ "$cmd" =~ \>{1,2} ]]; then
    if targets_only_baton "$cmd"; then
      return 0
    fi
    # Allow redirects to /tmp/ and /dev/ paths (consistent with is_dangerous_write)
    if [[ "$cmd" =~ \>{1,2}[[:space:]]*([^[:space:]|;&]+) ]]; then
      local redir_target="${BASH_REMATCH[1]}"
      if [[ "$redir_target" == "/tmp/"* ]] || [[ "$redir_target" == "/dev/"* ]]; then
        return 0
      fi
    fi
    return 1
  fi

  # Test runners
  if [[ "$cmd" =~ ^(npm[[:space:]]+(run[[:space:]]+)?test|yarn[[:space:]]+(run[[:space:]]+)?test|pnpm[[:space:]]+(run[[:space:]]+)?test|npx[[:space:]]+jest|npx[[:space:]]+vitest|npx[[:space:]]+mocha) ]]; then
    return 0
  fi
  if [[ "$cmd" =~ ^(pytest|python[[:space:]]+-m[[:space:]]+pytest|python[[:space:]]+-m[[:space:]]+unittest|go[[:space:]]+test|cargo[[:space:]]+test|mvn[[:space:]]+test|gradle[[:space:]]+test|dotnet[[:space:]]+test) ]]; then
    return 0
  fi

  # Commands that only read or inspect
  if [[ "$cmd" =~ ^(grep|rg|ag|egrep|fgrep|find|fd|jq|yq|node[[:space:]]+-e|python3?[[:space:]]+-c|ruby[[:space:]]+-e|diff|md5|shasum|sha256sum|date|env|printenv|uname|hostname|id|whoami)[[:space:]] ]]; then
    if ! [[ "$cmd" =~ \>{1,2} ]]; then
      return 0
    fi
    # If redirecting, check if target is .baton/
    if targets_only_baton "$cmd"; then
      return 0
    fi
    return 1
  fi

  # npm/yarn/pnpm info/list/install (not scripts that might modify)
  if [[ "$cmd" =~ ^(npm|yarn|pnpm)[[:space:]]+(install|ci|list|ls|info|view|outdated|audit|pack|version)[[:space:]] ]] || \
     [[ "$cmd" =~ ^(npm|yarn|pnpm)[[:space:]]+(install|ci|list|ls|info|view|outdated|audit|pack|version)$ ]]; then
    return 0
  fi

  # Commands targeting .baton/ paths exclusively
  if [[ "$cmd" =~ ^[^[:space:]]+[[:space:]]+(.*\.baton/) ]] && ! [[ "$cmd" =~ [[:space:]][^.][^b][^a][^t][^o][^n] ]]; then
    return 0
  fi

  return 1
}

# Remove content inside single and double quotes from a command string.
# Used to prevent false positives when filenames appear only inside quoted arguments
# (e.g. git commit -m "fix: state.json issue").
# NOTE: Only use the stripped result for filename-presence detection.
#       Write-pattern detection (redirects, etc.) must still use the original command.
strip_quoted_strings() {
  echo "$1" | sed -E "s/\"[^\"]*\"//g; s/'[^']*'//g"
}

# .agent-stack write detection — ALWAYS blocked, no exceptions
is_agent_stack_write() {
  local cmd="$1"
  local stripped
  stripped=$(strip_quoted_strings "$cmd")
  # Does command reference .agent-stack at all? (anchored: must be at path boundary)
  # Use stripped string so quoted mentions (e.g. commit messages) are ignored.
  echo "$stripped" | grep -qE '(^|[[:space:]/])\.agent-stack([[:space:]]|$)' || return 1

  # Check for write patterns using the ORIGINAL command (redirects must not be stripped)
  if echo "$cmd" | grep -qE '(>>?|tee|sed\s+-i|rm\s|mv\s|cp\s|\.write\(|open\(.+[wW])'; then
    return 0
  fi
  if echo "$cmd" | grep -qE '(echo|printf).*>>?\s*.*\.agent-stack'; then
    return 0
  fi
  return 1  # Read-only access — allow
}

# state.json write detection — blocked only if state.json already exists (allow init)
is_state_json_write() {
  local cmd="$1"
  local stripped
  stripped=$(strip_quoted_strings "$cmd")
  # Does command reference state.json at all? (anchored: must be at path boundary)
  # Use stripped string so quoted mentions (e.g. commit messages) are ignored.
  echo "$stripped" | grep -qE '(^|[[:space:]/])state\.json([[:space:]]|$|["\x27])' || return 1

  # Check for write patterns using the ORIGINAL command (redirects must not be stripped)
  local is_write=false
  if echo "$cmd" | grep -qE '(>>?|tee|sed\s+-i|rm\s|mv\s|cp\s|\.write\(|open\(.+[wW])'; then
    is_write=true
  fi
  if echo "$cmd" | grep -qE '(echo|printf).*>>?\s*.*state\.json'; then
    is_write=true
  fi

  [ "$is_write" = "false" ] && return 1  # Read-only access — allow

  # Self-sealing: block only if state.json already exists
  if [ -f "$BATON_DIR/state.json" ]; then
    return 0  # EXISTS → block write
  fi

  return 1  # NOT EXISTS → allow init write
}

# Check if command contains dangerous write patterns to non-.baton files
is_dangerous_write() {
  local cmd="$1"

  # sed -i (in-place edit)
  if [[ "$cmd" =~ (^|[[:space:]|;&])sed[[:space:]].*-i ]]; then
    # Allow if all file args are .baton/
    if [[ "$cmd" =~ \.baton/ ]] && ! [[ "$cmd" =~ [[:space:]][^.]*\.[^b] ]]; then
      return 1
    fi
    return 0
  fi

  # awk with output redirection to non-.baton files
  if [[ "$cmd" =~ (^|[[:space:]|;&])awk[[:space:]] ]] && [[ "$cmd" =~ \>{1,2} ]]; then
    if ! targets_only_baton "$cmd"; then
      return 0
    fi
  fi

  # tee to non-.baton files
  if [[ "$cmd" =~ (^|[[:space:]|;&\|])tee[[:space:]] ]]; then
    if ! [[ "$cmd" =~ tee[[:space:]]+(-a[[:space:]]+)?[^[:space:]]*\.baton/ ]]; then
      return 0
    fi
  fi

  # Redirect (> or >>) to non-.baton files (check the final destination in pipes)
  if [[ "$cmd" =~ \>{1,2}[[:space:]]*([^[:space:]|;&]+) ]]; then
    local target="${BASH_REMATCH[1]}"
    if [[ "$target" != *.baton/* ]] && [[ "$target" != .baton/* ]] && [[ "$target" != */\.baton/* ]] && \
       [[ "$target" != "/dev/null" ]] && [[ "$target" != "/tmp/"* ]] && [[ "$target" != "/dev/"* ]]; then
      return 0
    fi
  fi

  # mv/cp targeting non-.baton source files
  if [[ "$cmd" =~ (^|[[:space:]|;&])mv[[:space:]] ]] || [[ "$cmd" =~ (^|[[:space:]|;&])cp[[:space:]] ]]; then
    if ! [[ "$cmd" =~ \.baton/ ]]; then
      return 0
    fi
    # If it involves both .baton and non-.baton paths, still block
    if [[ "$cmd" =~ [[:space:]][^.]*\.(ts|js|py|go|rs|java|rb|c|h|cpp|hpp|swift|kt) ]]; then
      return 0
    fi
  fi

  # rm targeting non-.baton source files (allow temp/build files)
  if [[ "$cmd" =~ (^|[[:space:]|;&])rm[[:space:]] ]]; then
    # Allow rm of .baton/ paths
    if [[ "$cmd" =~ \.baton/ ]]; then
      return 1
    fi
    # Allow rm of common temp/build dirs
    if [[ "$cmd" =~ (node_modules|dist|build|\.cache|__pycache__|\.pyc|\.o|\.class|tmp|temp) ]]; then
      return 1
    fi
    return 0
  fi

  # chmod on source files
  if [[ "$cmd" =~ (^|[[:space:]|;&])chmod[[:space:]] ]]; then
    if ! [[ "$cmd" =~ \.baton/ ]]; then
      return 0
    fi
  fi

  # patch command
  if [[ "$cmd" =~ (^|[[:space:]|;&])patch[[:space:]] ]]; then
    return 0
  fi

  # cat > file or cat >> file (write mode)
  if [[ "$cmd" =~ (^|[[:space:]|;&])cat[[:space:]] ]] && [[ "$cmd" =~ \>{1,2} ]]; then
    if ! targets_only_baton "$cmd"; then
      return 0
    fi
  fi

  return 1
}

main() {
  # .baton 디렉토리가 없으면 통과 (pre-init)
  if [ ! -d "$BATON_DIR" ]; then
    log "PASSED: Pre-init (no .baton dir)"
    exit 0
  fi

  local command
  command=$(hook_get_field "tool_input.command" 2>/dev/null || echo "")

  # ── 1. .agent-stack write → BLOCK (always, for everyone) ──
  if is_agent_stack_write "$command"; then
    log "BLOCKED: Write to .agent-stack"
    block "⛔ [R01] Write to .agent-stack is permanently sealed. No agent may modify .agent-stack via Bash."
  fi

  # ── 2. Subagent active → ALLOW (Worker bypass) ──
  if is_subagent_active; then
    local active_agent
    active_agent=$(tail -1 "$AGENT_STACK_FILE" 2>/dev/null | cut -d'|' -f2 || echo "unknown")
    log "PASSED: Subagent active ($active_agent)"
    exit 0
  fi

  # ── 3. state.json write → EXISTS → BLOCK / NOT EXISTS → ALLOW ──
  if is_state_json_write "$command"; then
    log "BLOCKED: Write to state.json (file already exists)"
    block "⛔ [R01] state.json is sealed after initialization. Cannot be modified via Bash."
  fi

  log "Checking: command=${command:0:100}"

  # 빈 명령 통과
  if [ -z "$command" ]; then
    log "PASSED: Empty command"
    exit 0
  fi

  # Safe command whitelist check
  if is_safe_command "$command"; then
    log "PASSED: Safe command"
    exit 0
  fi

  # Dangerous write pattern check
  if is_dangerous_write "$command"; then
    local truncated="${command:0:100}"
    log "BLOCKED: Dangerous bash command: $truncated"

    cat >&2 <<EOF
⛔ [Main Guard Bash] R01 위반 — Main의 Bash 코드 수정 차단

차단된 명령어: $truncated

코드 수정은 반드시 Worker Agent에게 위임하세요.
EOF

    exit 2
  fi

  local truncated="${command:0:100}"
  log "BLOCKED: Command not in safe whitelist"
  block "⛔ [R01] Bash command blocked — not in safe command whitelist.

Blocked command: $truncated

Allowed: git, ls, pwd, mkdir, cat, head, tail, wc, test runners (npm test, pytest, go test, cargo test, etc.)
For other operations, delegate to a Worker agent."
}

main
