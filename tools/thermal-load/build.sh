#!/bin/zsh
set -euo pipefail

module_cache=".build/module-cache"
mkdir -p "$module_cache"
export CLANG_MODULE_CACHE_PATH="$module_cache"

xcrun swiftc -O -framework Metal main.swift -o thermal-load
echo "Built ./thermal-load"
