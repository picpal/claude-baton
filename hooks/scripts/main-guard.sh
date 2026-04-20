#!/usr/bin/env bash
# Main Guard Hook
# Main Agent가 직접 코드 파일을 수정하는 것을 차단합니다.
# PreToolUse Hook (Edit|Write 매처)
#
# 핵심 로직:
# - Subagent 스택이 비어있으면 = Main Agent가 직접 호출
# - Main Agent는 코드 파일을 직접 수정할 수 없음
# - Worker Agent에게 위임해야 함

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/find-baton-root.sh"
source "$SCRIPT_DIR/stdin-reader.sh"

ensure_baton_dirs

LOG_FILE="$BATON_LOG_DIR/main-guard.log"
AGENT_STACK_FILE="$BATON_LOG_DIR/.agent-stack"

# Cap for the relaxed root-level config/README whitelist (see is_new_whitelist_path).
readonly CONFIG_DIFF_LINE_CAP=20

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# 허용된 경로 패턴 (Main Agent도 수정 가능)
is_allowed_path() {
  local file_path="$1"

  # .baton/ 디렉토리 허용 (상태, 계획, 태스크 파일)
  if [[ "$file_path" == .baton/* ]] || [[ "$file_path" == */.baton/* ]]; then
    return 0
  fi

  # .claude/ 디렉토리 허용 (설정 파일)
  if [[ "$file_path" == .claude/* ]] || [[ "$file_path" == */.claude/* ]]; then
    return 0
  fi

  # .claude-plugin/ 디렉토리 허용 (플러그인 매니페스트)
  if [[ "$file_path" == .claude-plugin/* ]] || [[ "$file_path" == */.claude-plugin/* ]]; then
    return 0
  fi

  # CLAUDE.md 허용
  if [[ "$(basename "$file_path")" == "CLAUDE.md" ]]; then
    return 0
  fi

  # .gitignore 허용
  if [[ "$(basename "$file_path")" == ".gitignore" ]]; then
    return 0
  fi

  return 1
}

# Lockfile 차단 — 경로 depth 무관, 파일명 기준
is_excluded_lockfile() {
  local base
  base="$(basename "$1")"
  case "$base" in
    package-lock.json|yarn.lock|pnpm-lock.yaml|Cargo.lock|go.sum|poetry.lock|composer.lock|Gemfile.lock)
      return 0
      ;;
  esac
  return 1
}

# Pipeline-definition 트리 차단 (agents/commands/skills/hooks) — .baton/.claude/ 내부는 제외
is_excluded_pipeline_def() {
  local file_path="$1"
  # .baton/ 및 .claude/ 내부 경로는 pipeline-def 트리로 취급하지 않음 — 기존 whitelist 우선 보호
  if [[ "$file_path" == .baton/* ]] || [[ "$file_path" == */.baton/* ]]; then
    return 1
  fi
  if [[ "$file_path" == .claude/* ]] || [[ "$file_path" == */.claude/* ]]; then
    return 1
  fi
  local dir
  for dir in agents commands skills hooks; do
    if [[ "$file_path" == "$dir"/* ]] || [[ "$file_path" == */"$dir"/* ]]; then
      return 0
    fi
  done
  return 1
}

# 루트 레벨 config/README whitelist 대상인지 판별
# - 루트 파일만 해당 (nested 경로는 제외)
# - 대상: README.md, *.json, *.yaml, *.yml, *.toml, *.ini
is_new_whitelist_path() {
  local file_path="$1"

  # 루트 여부: 상대경로는 dirname이 '.', 절대경로는 dirname이 BATON_ROOT 와 동일
  local dir
  dir="$(dirname "$file_path")"
  if [[ "$dir" != "." ]] && [[ "$dir" != "$BATON_ROOT" ]]; then
    return 1
  fi

  local base
  base="$(basename "$file_path")"
  if [[ "$base" == "README.md" ]]; then
    return 0
  fi
  case "$base" in
    *.json|*.yaml|*.yml|*.toml|*.ini)
      return 0
      ;;
  esac
  return 1
}

# Edit/Write tool 입력으로부터 diff line count 추정
# - Edit: old_string 개행 수 + new_string 개행 수
# - Write(신규): content 개행 수
# - Write(기존): |파일 라인수 - content 라인수| (절댓값, diff 근사)
# hook_get_field 결과가 비정상이면 9999 반환 → 사실상 cap 초과로 차단 유도
diff_line_count() {
  local tool_name="$1"
  local file_path="$2"

  if [[ "$tool_name" == "Edit" ]]; then
    local old_s new_s
    old_s="$(hook_get_field "tool_input.old_string" 2>/dev/null || echo "")"
    new_s="$(hook_get_field "tool_input.new_string" 2>/dev/null || echo "")"
    local old_n new_n
    old_n=$(printf '%s' "$old_s" | awk 'END{print NR}')
    new_n=$(printf '%s' "$new_s" | awk 'END{print NR}')
    # 비어 있으면 awk가 0을 반환하므로 별도 보정 불필요
    echo $((old_n + new_n))
    return 0
  fi

  if [[ "$tool_name" == "Write" ]]; then
    local content
    content="$(hook_get_field "tool_input.content" 2>/dev/null || echo "")"
    local content_n
    content_n=$(printf '%s' "$content" | awk 'END{print NR}')
    if [ -f "$file_path" ]; then
      local existing_n
      existing_n=$(awk 'END{print NR}' "$file_path" 2>/dev/null || echo 0)
      local diff=$((content_n - existing_n))
      [ "$diff" -lt 0 ] && diff=$((-diff))
      echo "$diff"
    else
      echo "$content_n"
    fi
    return 0
  fi

  # 알 수 없는 tool → cap 초과로 간주하여 차단
  echo 9999
  return 0
}

# Subagent 실행 중인지 확인
is_subagent_active() {
  if [ -f "$AGENT_STACK_FILE" ] 2>/dev/null && [ -s "$AGENT_STACK_FILE" ] 2>/dev/null; then
    return 0
  fi
  return 1
}

main() {
  local file_path tool_name
  file_path=$(hook_get_field "tool_input.file_path" 2>/dev/null || echo "")
  tool_name=$(hook_get_field "tool_name" 2>/dev/null || echo "")

  log "Checking: tool=$tool_name file=$file_path"

  # .baton 디렉토리가 없으면 통과 (pre-init)
  if [ ! -d "$BATON_DIR" ]; then
    log "PASSED: Pre-init (no .baton dir)"
    exit 0
  fi

  # 파일 경로가 없으면 차단 (입력을 판별할 수 없음 → 안전을 위해 차단)
  if [ -z "$file_path" ]; then
    log "BLOCKED: Unable to determine file path from input"
    echo "⛔ [Main Guard] 파일 경로를 판별할 수 없습니다. 안전을 위해 차단합니다."
    exit 2
  fi

  # 보호 대상 파일 차단 (subagent 여부와 무관하게 항상 차단)

  # .agent-stack — always block
  if echo "$file_path" | grep -qE '(^|/)\.agent-stack$'; then
    log "DENIED: Protected pipeline file ($file_path)"
    echo "⛔ [Main Guard] .agent-stack is a protected pipeline file. Direct modification is not allowed."
    exit 1
  fi

  # Subagent 실행 중이면 통과 (Worker가 실행 중)
  if is_subagent_active; then
    local active_agent
    active_agent=$(tail -1 "$AGENT_STACK_FILE" 2>/dev/null | cut -d'|' -f2 || echo "unknown")
    log "PASSED: Subagent active ($active_agent)"
    exit 0
  fi

  # Lockfile 차단 (경로 무관)
  if is_excluded_lockfile "$file_path"; then
    log "BLOCKED: lockfile-excluded ($file_path)"
    cat <<EOF
⛔ [Main Guard] R01 위반 감지! (lockfile-excluded)

Main Orchestrator는 lockfile을 직접 수정할 수 없습니다.

차단된 파일: $file_path

Lockfile은 패키지 매니저를 통해서만 갱신해야 합니다.
reason: lockfile-excluded
EOF
    exit 2
  fi

  # Pipeline-definition 트리 차단 (agents/commands/skills/hooks)
  if is_excluded_pipeline_def "$file_path"; then
    log "BLOCKED: pipeline-def-excluded ($file_path)"
    cat <<EOF
⛔ [Main Guard] R01 위반 감지! (pipeline-def-excluded)

Main Orchestrator는 파이프라인 정의 파일을 직접 수정할 수 없습니다.

차단된 파일: $file_path

agents/, commands/, skills/, hooks/ 트리는 Worker Agent를 통해서만 수정하세요.
reason: pipeline-def-excluded
EOF
    exit 2
  fi

  # 기존 whitelist (.baton/, .claude/, CLAUDE.md, .gitignore) — 무제한 허용
  if is_allowed_path "$file_path"; then
    log "PASSED: Allowed path ($file_path)"
    exit 0
  fi

  # 신규 whitelist — 루트 레벨 config/README (diff ≤ CONFIG_DIFF_LINE_CAP)
  if is_new_whitelist_path "$file_path"; then
    local lines
    lines=$(diff_line_count "$tool_name" "$file_path")
    if [ "$lines" -le "$CONFIG_DIFF_LINE_CAP" ]; then
      log "PASSED: root-config whitelist ($file_path, diff=$lines)"
      exit 0
    fi
    log "BLOCKED: config-lines-exceeded ($file_path, diff=$lines > $CONFIG_DIFF_LINE_CAP)"
    cat <<EOF
⛔ [Main Guard] R01 위반 감지! (config-lines-exceeded)

루트 레벨 설정 파일의 diff가 허용 한도(${CONFIG_DIFF_LINE_CAP}줄)를 초과했습니다.

차단된 파일: $file_path
diff 라인 수: $lines (cap=$CONFIG_DIFF_LINE_CAP)

대규모 변경은 Worker Agent에게 위임하세요.
reason: config-lines-exceeded
EOF
    exit 2
  fi

  # Main Agent가 코드 파일을 직접 수정하려고 함 → 차단
  log "BLOCKED: Main Agent attempted to modify code file: $file_path"

  cat <<EOF
⛔ [Main Guard] R01 위반 감지!

Main Orchestrator는 코드 파일을 직접 수정할 수 없습니다.

차단된 파일: $file_path

허용된 경로:
  - .baton/**/* (파이프라인 상태, 계획, 태스크)
  - .claude/**/* (설정)
  - CLAUDE.md (규칙)
  - .gitignore
  - 루트 레벨 README.md / *.json / *.yaml / *.yml / *.toml / *.ini (≤${CONFIG_DIFF_LINE_CAP} line diff)

올바른 방법:
  Agent(subagent_type="claude-baton:worker-agent",
        description="Worker: {작업명}",
        model="opus" or "sonnet",
        prompt="...")

코드 수정은 반드시 Worker Agent에게 위임하세요.
EOF

  exit 2
}

main
