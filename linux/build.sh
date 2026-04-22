#!/usr/bin/env bash
# build.sh — compile drover.so
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

gcc -shared -fPIC -O2 \
    -o "$SCRIPT_DIR/drover.so" \
    "$SCRIPT_DIR/drover.c" \
    -ldl -lpthread

echo "Built: $SCRIPT_DIR/drover.so"
