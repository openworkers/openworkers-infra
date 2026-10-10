#!/usr/bin/env bash
set -euo pipefail

script_path="$(cd "$(dirname "$0")" && pwd -P)"
export HTTP_ADDR="${HTTP_ADDR:-127.0.0.1:8081}"
export HTTPS_ADDR="${HTTPS_ADDR:-127.0.0.1:8443}"
export WORKER_DOMAINS="${WORKER_DOMAINS:-workers.rocks,workers.dev.localhost}"
cd "$script_path/../openworkers-runner"
exec cargo run --features v8 -- "$@"
