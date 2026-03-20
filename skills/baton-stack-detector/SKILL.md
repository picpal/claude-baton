---
name: baton-stack-detector
description: |
  MUST USE for codebase analysis and tech stack detection.
  Activate whenever the user asks to analyze a codebase, detect what technologies or frameworks
  are used, identify the project's tech stack, or when any other baton skill needs stack information.
  Triggers on: "코드베이스 분석", "스택이 뭐야", "프로젝트 구조 파악", "기술 스택 확인",
  "analyze codebase", "what stack", "detect framework", "what technologies".
  Also activates automatically as part of the baton-orchestrator pipeline during the Analysis phase.
  Reads build files (package.json, build.gradle, go.mod, Cargo.toml, etc.) to confirm stacks.
  Never assumes — always reads from actual files to verify.
allowed-tools: Read, Glob, Bash, Write
---

# Codebase Scanner

## Core Principle
Never assume the stack. Always read build files to confirm. Detection results go into .baton/complexity-score.md.

## Detection Priority
1. Build files first (package.json, build.gradle, pom.xml, go.mod, Cargo.toml, etc.)
2. Dependency analysis within build files (determines sub-stack like expo vs react-native)
3. File extensions as fallback only

Use `scripts/detect-stack.sh <directory>` for automated detection.
For detailed rules → references/detection-rules.md

## Quick Decision Tree

**package.json found?**
→ expo dep? → expo | react-native dep? → react-native | next dep? → next | react dep? → react | else → typescript/node

**build.gradle/pom.xml found?**
→ spring-boot plugin? → spring-boot | kotlin plugin? → kotlin | else → java

**Other build files?**
→ requirements.txt/pyproject.toml → python | go.mod → go | Cargo.toml → rust | Package.swift → swift

## Multi-Stack Handling
- Scan each top-level directory independently
- Map each directory to its detected stack
- If cross-stack API interfaces exist → mark "contract test required: YES"

## Output Format (.baton/complexity-score.md)
```
## Detected Stack
| Path | Stack | Evidence File |
|------|-------|--------------|

## File → Stack Mapping
(extension → stack per directory)

## Multi-Stack Status
- Multi-stack: YES/NO
- API contract test required: YES/NO

## Complexity Score
→ Total: Npt → Tier N
```
