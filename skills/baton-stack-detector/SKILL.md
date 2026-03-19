---
name: baton-stack-detector
description: |
  Tech stack auto-detection skill.
  Activates on codebase analysis requests.
  Reads build files (package.json, build.gradle, go.mod, etc.)
  to confirm stacks and records them in complexity-score.md.
  Never assumes — always reads from files.
allowed-tools: Read, Glob, Bash, Write
---

# Codebase Scanner Skill

## Role
Analyze codebase structure and automatically detect the tech stack.
Detection results are recorded in complexity-score.md and referenced whenever any agent is spawned afterward.
Never assume the stack. Always read from files to confirm.

## Primary Scan (performed in parallel while waiting for interview)

### Stack Auto-Detection Order
1. Search for the following files in root and each directory:
   - package.json            → Identify JS/TS family
   - build.gradle            → Identify Java / Kotlin / Spring Boot
   - pom.xml                 → Identify Java / Maven
   - requirements.txt / pyproject.toml → Identify Python
   - go.mod                  → Identify Go
   - Cargo.toml              → Identify Rust
   - Package.swift / *.xcodeproj → Identify Swift
   - app.json / app.config.js → Identify Expo

2. When package.json is found, check dependencies:
   - "react-native" present   → react-native
   - "expo" present            → expo (react-native extends)
   - "next" present            → next
   - "react" present (none above) → react
   - None of the above        → typescript (or node)

3. When build.gradle / pom.xml is found:
   - "org.springframework.boot" present → spring-boot (java extends)
   - kotlin plugin present              → kotlin (java extends)
   - None of the above                  → java

4. Confirm per-directory mapping:
   e.g.) backend/ → spring-boot, mobile/ → expo

### File → Stack Mapping Rules (supplementary)
- *.java, *.kt    → java / kotlin
- *.swift         → swift
- *.py            → python
- *.go            → go
- *.rs            → rust
- *.tsx, *.ts     → Follow parent directory stack (build file detection takes priority)

## Secondary Scan (after requirements are confirmed)
- List of files affected by changes
- Related interfaces and type definitions
- Dependency graph (based on change targets)
- Check for cross-stack API interfaces (determine if contract tests are needed for multi-stack)

## Output: complexity-score.md Format
```
## Detected Stack
| Path      | Stack       | Evidence File                          |
|-----------|-------------|----------------------------------------|
| backend/  | spring-boot | build.gradle (spring-boot-starter-web) |
| mobile/   | expo        | package.json (expo ^51.0.0)            |

## File → Stack Mapping
*.java, *.kt (backend/) → spring-boot / kotlin
*.tsx, *.ts  (mobile/)  → expo / react-native

## Multi-Stack Status
- Multi-stack: YES
- API contract test required: YES (interface exists between backend ↔ mobile)

## Complexity Score
- Estimated files to change: N files (Npt)
- Cross-service dependency: Yes/No
- New feature: Yes/No
- Architecture decision: Yes/No
- Security-related: Yes/No
→ Total: Npt → Tier N
```
