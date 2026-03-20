# Stack Detection Rules — Detailed Reference

## Build File Detection (Priority Order)

### 1. package.json (JS/TS Family)
Check `dependencies` and `devDependencies` in order:

| Dependency | Detected Stack | Notes |
|-----------|---------------|-------|
| `expo` | expo | react-native extends |
| `react-native` | react-native | Check for bare vs Expo workflow |
| `next` | next | SSR/SSG framework |
| `react` (alone) | react | No RN/Next/Expo present |
| None of above | typescript / node | Check for `typescript` in devDeps |

#### Expo vs React Native Disambiguation
- `app.json` with `expo` key → **expo**
- `app.config.js` / `app.config.ts` present → **expo**
- `react-native` without expo indicators → **react-native** (bare workflow)

### 2. build.gradle / build.gradle.kts (JVM Family)

| Plugin/Dependency | Detected Stack |
|------------------|---------------|
| `org.springframework.boot` | spring-boot (extends java) |
| `kotlin` plugin / `org.jetbrains.kotlin` | kotlin (extends java) |
| Both Spring + Kotlin | spring-boot + kotlin |
| Neither | java (pure) |

### 3. pom.xml (Maven)

| Parent/Dependency | Detected Stack |
|------------------|---------------|
| `spring-boot-starter-parent` | spring-boot |
| `kotlin-maven-plugin` | kotlin |
| Neither | java |

### 4. Other Build Files

| File | Detected Stack |
|------|---------------|
| `requirements.txt` / `pyproject.toml` / `setup.py` / `Pipfile` | python |
| `go.mod` | go |
| `Cargo.toml` | rust |
| `Package.swift` / `*.xcodeproj` / `*.xcworkspace` | swift |

## File Extension Fallback (when build files are ambiguous)

| Extension | Stack | Rule |
|-----------|-------|------|
| `*.java` | java | Unless Spring detected → spring-boot |
| `*.kt` | kotlin | Unless Spring detected → spring-boot + kotlin |
| `*.swift` | swift | Always swift |
| `*.py` | python | Always python |
| `*.go` | go | Always go |
| `*.rs` | rust | Always rust |
| `*.tsx`, `*.ts` | (varies) | Follow parent directory's build file detection |
| `*.jsx`, `*.js` | (varies) | Follow parent directory's build file detection |

## Multi-Stack Project Detection

### Directory-Level Scanning
Scan each top-level directory independently:
```
project/
├── backend/    → build.gradle → spring-boot
├── mobile/     → package.json → expo
├── web/        → package.json → next
└── shared/     → Follow consumers' stacks
```

### Cross-Stack API Interface Detection
When multiple stacks are found, check for:
- REST API definitions in one stack consumed by another
- Shared type definitions / API schemas
- GraphQL schemas referenced across stacks
- If found → mark "contract test required: YES"

## Monorepo Support
- Check for `workspaces` in root package.json
- Check for `lerna.json` or `nx.json`
- Scan each workspace/package independently
- Each workspace gets its own stack tag
