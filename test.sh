#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

lua5.4 ./lua/anxtgo/test.lua
