#!/usr/bin/env bash
# Main Guard Bash Hook
# Main Agent의 위험한 파일 쓰기 명령만 차단합니다 (블랙리스트 방식)
# PreToolUse Hook (Bash 매처)
#
# 핵심 로직:
# - Subagent 스택이 비어있으면 = Main Agent가 직접 호출
# - .agent-stack 쓰기 차단 (항상)
# - is_dangerous_write() 패턴만 차단, 나머지는 모두 허용

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

# Remove content inside single and double quotes from a command string.
# Used to prevent false positives when filenames appear only inside quoted arguments
# (e.g. git commit -m "fix: state.json issue").
# NOTE: Only use the stripped result for filename-presence detection.
#       Write-pattern detection (redirects, etc.) must still use the original command.
strip_quoted_strings() {
  echo "$1" | sed -E "s/\"[^\"]*\"//g; s/'[^']*'//g"
}

# Remove heredoc body content, preserving command lines with << markers.
# Handles <<EOF, <<'EOF', <<"EOF", <<-EOF variants.
strip_heredoc_bodies() {
  echo "$1" | awk '
    /<<-?'\''?"?[A-Za-z_][A-Za-z_0-9]*'\''?"?/ {
      delim=$0
      sub(/.*<<-?'\''?"?/, "", delim)
      sub(/[^A-Za-z_0-9].*/, "", delim)
      if (delim != "") { in_heredoc=1; heredoc_delim=delim; print; next }
    }
    in_heredoc && $0 == heredoc_delim { in_heredoc=0; next }
    !in_heredoc { print }
  '
}

# .agent-stack write detection — ALWAYS blocked, no exceptions
# Heredoc bodies and quoted strings are stripped before presence check
# to avoid false positives from commit messages or documentation text.
is_agent_stack_write() {
  local cmd="$1"
  local no_heredoc
  no_heredoc=$(strip_heredoc_bodies "$cmd")
  local stripped
  stripped=$(strip_quoted_strings "$no_heredoc")
  # Does command reference .agent-stack at all? (anchored: must be at path boundary)
  # Use stripped string so quoted mentions (e.g. commit messages) are ignored.
  echo "$stripped" | grep -qE '(^|[[:space:]/])\.agent-stack([[:space:]]|$)' || return 1

  # Check for write patterns using the ORIGINAL command (redirects must not be stripped)
  # Strip fd redirects (2>/dev/null, 2>&1) first to avoid false positives
  local cmd_no_fd
  cmd_no_fd=$(echo "$cmd" | sed -E 's/[0-9]+>&[0-9]+//g; s/[0-9]+>>[[:space:]]*[^[:space:]]+//g; s/[0-9]+>[[:space:]]*[^[:space:]]+//g')
  if echo "$cmd_no_fd" | grep -qE '(>>?|tee|sed\s+-i|rm\s|mv\s|cp\s|\.write\(|open\(.+[wW])'; then
    return 0
  fi
  if echo "$cmd" | grep -qE '(echo|printf).*>>?\s*.*\.agent-stack'; then
    return 0
  fi
  return 1  # Read-only access — allow
}

# 탐색 행위 차단 — 보호 경로 대상 read-only 명령
# 차단 verbs: cat, head, tail, less, grep, rg, find, fd, awk, sed
# 허용: git, jq, ls, wc, stat, file, echo, printf, 보호 경로 미포함 명령
# 반환: 차단할 verb를 echo (차단 메시지에 사용), 미발견 시 빈 문자열
is_dangerous_explore() {
  local cmd="$1"
  # 따옴표 / heredoc 본문 제거하여 메시지 내 경로 노이즈 차단
  local no_heredoc stripped
  no_heredoc=$(strip_heredoc_bodies "$cmd")
  stripped=$(strip_quoted_strings "$no_heredoc")

  # 보호 경로 정규식 (단어 경계: 공백 시작/슬래시 / 앞 또는 줄 시작)
  local protected_re='(^|[[:space:]/])(\.?/)?(agents|skills|commands|hooks|src|test|tests|lib)(/|[[:space:]]|$)'

  # 보호 경로 미포함 → 통과
  echo "$stripped" | grep -qE "$protected_re" || return 1

  # 첫 토큰 (verb) 추출 — 파이프/세미콜론으로 분리된 각 절을 검사하면 좋지만
  # 단순 첫 토큰 + 절 분리(파이프/세미콜론 단위) 검사로 충분
  # 절(clause) 단위로 분리하여 각 절 verb 검사
  local clauses
  # |, ;, &&, || 로 절 분리 — sed 로 \n 변환
  clauses=$(echo "$stripped" | sed -E 's/(\|\||&&|[|;&])/\n/g')

  local clause first
  while IFS= read -r clause; do
    # 앞쪽 공백 제거
    clause=$(echo "$clause" | sed -E 's/^[[:space:]]+//')
    [ -z "$clause" ] && continue
    # 절 안에 보호 경로 없으면 skip
    echo "$clause" | grep -qE "$protected_re" || continue

    # 첫 토큰 추출
    first=$(echo "$clause" | awk '{print $1}')
    # 절대경로 verb (e.g. /bin/cat) → basename
    first=$(basename "$first" 2>/dev/null || echo "$first")

    case "$first" in
      cat|head|tail|less|grep|rg|find|fd|awk|sed)
        # head -n N 의 경우 N >= 50 만 차단 (소량 peek 허용)
        if [ "$first" = "head" ]; then
          # -n N 또는 -nN 형태 추출
          local n
          n=$(echo "$clause" | grep -oE '\-n[[:space:]]*[0-9]+|\-[0-9]+' | head -1 | grep -oE '[0-9]+' | head -1)
          if [ -n "$n" ] && [ "$n" -lt 50 ] 2>/dev/null; then
            continue
          fi
          # n 미지정 (default 10) 도 허용
          if [ -z "$n" ]; then
            continue
          fi
        fi
        echo "$first"
        return 0
        ;;
    esac
  done <<< "$clauses"

  return 1
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
  # BATON_GUARD_DISABLE 우회 (디버깅용) — 모든 분기 이전에 처리
  if [ "${BATON_GUARD_DISABLE:-}" = "1" ]; then
    log "PASSED: BATON_GUARD_DISABLE=1"
    exit 0
  fi

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

  # ── 2. Subagent active → ALLOW (Worker / Explore agent bypass) ──
  if is_subagent_active; then
    local active_agent
    active_agent=$(tail -1 "$AGENT_STACK_FILE" 2>/dev/null | cut -d'|' -f2 || echo "unknown")
    log "PASSED: Subagent active ($active_agent)"
    exit 0
  fi

  log "Checking: command=${command:0:100}"

  # 빈 명령 통과
  if [ -z "$command" ]; then
    log "PASSED: Empty command"
    exit 0
  fi

  # Dangerous write pattern check (blacklist)
  if is_dangerous_write "$command"; then
    local truncated="${command:0:100}"
    log "BLOCKED: Dangerous bash command: $truncated"

    echo "⛔ [R01] Bash write blocked: $truncated — delegate to Worker agent." >&2
    exit 2
  fi

  # 탐색 행위 차단 (보호 경로 대상 read-only verbs)
  local explore_verb
  explore_verb=$(is_dangerous_explore "$command")
  if [ -n "$explore_verb" ]; then
    log "BLOCKED: Explore verb '$explore_verb' on protected path"
    echo "[main-guard-bash] BLOCKED $explore_verb on protected path — use Explore agent for read-only inspection" >&2
    exit 2
  fi

  # Default: allow everything else
  log "PASSED: No dangerous pattern detected"
  exit 0
}

main
