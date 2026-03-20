#!/usr/bin/env bash
# tag-stack.sh — Detect the technology stack for a given file path.
# Usage: ./tag-stack.sh <filepath>
# Returns a single stack identifier to stdout (e.g., "spring-boot", "expo", "python").

set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: $0 <filepath>" >&2
  exit 1
fi

FILEPATH="$1"
FILENAME="$(basename "$FILEPATH")"
EXT="${FILENAME##*.}"
DIR="$(dirname "$FILEPATH")"

# --- Directory-based heuristics (checked first, more specific) ---

# Spring Boot / Java (Maven or Gradle project with src/main/java)
if echo "$DIR" | grep -qiE '(src/main/java|src/test/java)'; then
  echo "spring-boot"
  exit 0
fi

# Expo / React Native
if echo "$DIR" | grep -qiE '(expo|react-native)' || [ "$FILENAME" = "app.json" ] && grep -qs '"expo"' "$FILEPATH" 2>/dev/null; then
  echo "expo"
  exit 0
fi

# Next.js
if echo "$DIR" | grep -qiE '(pages|app)' && [ -f "$(git rev-parse --show-toplevel 2>/dev/null)/next.config" ] 2>/dev/null; then
  echo "nextjs"
  exit 0
fi
if echo "$DIR" | grep -qiE '/next' || [ "$FILENAME" = "next.config.js" ] || [ "$FILENAME" = "next.config.mjs" ] || [ "$FILENAME" = "next.config.ts" ]; then
  echo "nextjs"
  exit 0
fi

# Django
if echo "$DIR" | grep -qiE '(django|management/commands)' || [ "$FILENAME" = "manage.py" ] || [ "$FILENAME" = "wsgi.py" ] || [ "$FILENAME" = "asgi.py" ]; then
  echo "django"
  exit 0
fi

# Flask
if [ "$FILENAME" = "app.py" ] || [ "$FILENAME" = "wsgi.py" ]; then
  # Check for Flask import if possible
  if grep -qs 'from flask\|import flask' "$FILEPATH" 2>/dev/null; then
    echo "flask"
    exit 0
  fi
fi

# FastAPI
if grep -qs 'from fastapi\|import fastapi' "$FILEPATH" 2>/dev/null; then
  echo "fastapi"
  exit 0
fi

# NestJS
if echo "$DIR" | grep -qiE 'nest' || [ "$FILENAME" = "nest-cli.json" ]; then
  echo "nestjs"
  exit 0
fi

# Terraform / Infrastructure
if echo "$DIR" | grep -qiE '(terraform|infra|infrastructure)'; then
  echo "terraform"
  exit 0
fi

# Docker / DevOps
if [ "$FILENAME" = "Dockerfile" ] || [ "$FILENAME" = "docker-compose.yml" ] || [ "$FILENAME" = "docker-compose.yaml" ]; then
  echo "docker"
  exit 0
fi

# --- Extension-based heuristics (fallback) ---

case "$EXT" in
  java)
    echo "spring-boot"
    ;;
  kt|kts)
    echo "kotlin"
    ;;
  py)
    echo "python"
    ;;
  ts|tsx)
    # Distinguish React from generic TypeScript
    if echo "$FILEPATH" | grep -qiE '(component|screen|page|hook|\.tsx)'; then
      echo "react"
    else
      echo "typescript"
    fi
    ;;
  js|jsx)
    if echo "$FILEPATH" | grep -qiE '(component|screen|page|hook|\.jsx)'; then
      echo "react"
    else
      echo "javascript"
    fi
    ;;
  go)
    echo "golang"
    ;;
  rs)
    echo "rust"
    ;;
  rb)
    echo "ruby"
    ;;
  swift)
    echo "swift"
    ;;
  dart)
    echo "flutter"
    ;;
  tf|tfvars)
    echo "terraform"
    ;;
  sql)
    echo "sql"
    ;;
  yml|yaml)
    if echo "$FILENAME" | grep -qiE '(docker-compose|compose)'; then
      echo "docker"
    elif echo "$DIR" | grep -qiE '(\.github|ci|cd)'; then
      echo "ci-cd"
    else
      echo "config"
    fi
    ;;
  *)
    echo "unknown"
    ;;
esac
