#!/usr/bin/env bash
# detect-stack.sh — Auto-detect tech stack for a given directory
# Usage: ./detect-stack.sh [directory]
# Default: current directory

set -euo pipefail

DIR="${1:-.}"

if [ ! -d "$DIR" ]; then
    echo "Error: $DIR is not a directory" >&2
    exit 1
fi

echo "=== Stack Detection: $DIR ==="

detect_js_stack() {
    local pkg="$1/package.json"
    if [ ! -f "$pkg" ]; then return; fi

    local deps
    deps=$(cat "$pkg")

    if echo "$deps" | grep -q '"expo"'; then
        echo "  expo (react-native extends)"
    elif echo "$deps" | grep -q '"react-native"'; then
        echo "  react-native"
    elif echo "$deps" | grep -q '"next"'; then
        echo "  next"
    elif echo "$deps" | grep -q '"react"'; then
        echo "  react"
    elif echo "$deps" | grep -q '"typescript"'; then
        echo "  typescript"
    else
        echo "  node"
    fi
}

detect_jvm_stack() {
    local dir="$1"
    local stack=""

    if [ -f "$dir/build.gradle" ] || [ -f "$dir/build.gradle.kts" ]; then
        local gradle_file
        gradle_file=$(ls "$dir"/build.gradle* 2>/dev/null | head -1)
        if grep -q "springframework\|spring-boot" "$gradle_file" 2>/dev/null; then
            stack="spring-boot"
        fi
        if grep -q "kotlin\|org.jetbrains.kotlin" "$gradle_file" 2>/dev/null; then
            if [ -n "$stack" ]; then
                stack="$stack + kotlin"
            else
                stack="kotlin"
            fi
        fi
        if [ -z "$stack" ]; then
            stack="java"
        fi
        echo "  $stack"
    elif [ -f "$dir/pom.xml" ]; then
        if grep -q "spring-boot" "$dir/pom.xml" 2>/dev/null; then
            stack="spring-boot"
        else
            stack="java (maven)"
        fi
        echo "  $stack"
    fi
}

detect_other_stack() {
    local dir="$1"

    if [ -f "$dir/requirements.txt" ] || [ -f "$dir/pyproject.toml" ] || [ -f "$dir/setup.py" ] || [ -f "$dir/Pipfile" ]; then
        echo "  python"
    fi
    if [ -f "$dir/go.mod" ]; then
        echo "  go"
    fi
    if [ -f "$dir/Cargo.toml" ]; then
        echo "  rust"
    fi
    if [ -f "$dir/Package.swift" ] || ls "$dir"/*.xcodeproj 1>/dev/null 2>&1 || ls "$dir"/*.xcworkspace 1>/dev/null 2>&1; then
        echo "  swift"
    fi
}

# Scan root
echo ""
echo "Root ($DIR):"
detect_js_stack "$DIR"
detect_jvm_stack "$DIR"
detect_other_stack "$DIR"

# Scan subdirectories (1 level deep)
echo ""
echo "Subdirectories:"
for subdir in "$DIR"/*/; do
    if [ -d "$subdir" ] && [[ "$(basename "$subdir")" != "node_modules" ]] && [[ "$(basename "$subdir")" != ".git" ]] && [[ "$(basename "$subdir")" != ".baton" ]]; then
        name=$(basename "$subdir")
        result=""
        result+=$(detect_js_stack "$subdir" 2>/dev/null || true)
        result+=$(detect_jvm_stack "$subdir" 2>/dev/null || true)
        result+=$(detect_other_stack "$subdir" 2>/dev/null || true)
        if [ -n "$result" ]; then
            echo "$name/:"
            echo "$result"
        fi
    fi
done

echo ""
echo "=== Detection Complete ==="
