#!/usr/bin/env bash
set -euo pipefail

script_path="$(cd "$(dirname "$0")" && pwd -P)"

: "${HTTP_TLS_CERTIFICATE:?set HTTP_TLS_CERTIFICATE to the certificate of dash.dev.localhost and *.workers.dev.localhost}"
: "${HTTP_TLS_KEY:?set HTTP_TLS_KEY to its key}"

export HTTP_TLS_CERTIFICATE HTTP_TLS_KEY
export HTTP_ADDR="${HTTP_ADDR:-0.0.0.0:80}"
export HTTPS_ADDR="${HTTPS_ADDR:-0.0.0.0:443}"
export WORKER_DOMAINS="${WORKER_DOMAINS:-workers.dev.localhost}"

echo "Starting the runner on https://dash.dev.localhost"

cd "$script_path/../openworkers-runner"
exec cargo run --features v8 -- "$@"
