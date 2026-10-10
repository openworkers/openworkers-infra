# OpenWorkers Infrastructure

Self-hosted Cloudflare Workers runtime.

## Getting Started

**[GETTING_STARTED.md](./GETTING_STARTED.md)** walks through a full setup: infra
services in containers or native, migrations, the system user, storage, the API
deployed as a worker, and the public listeners.

## Stack

| Service            | Role                                                                         |
| ------------------ | ---------------------------------------------------------------------------- |
| PostgreSQL         | Platform data and worker logs                                                |
| NATS               | Console log transport                                                        |
| openworkers-runner | HTTP/TLS, workers, cron scheduler, log persistence and SSE/WebSocket streams |
| postgate           | Existing private HTTP database API; no public route                          |
| openworkers-api    | REST API and dashboard, deployed as a worker                                 |
| openworkers-cli    | Migrations and platform administration                                       |

Run one runner. It receives public traffic directly, without Nginx, and calls
cron handlers in the same process. The internal listener on `127.0.0.1:8080`
serves bindings and administration. Only public ports are published.

The runner holds a PostgreSQL advisory lock to reject a second instance. Stop
the old runner before starting its replacement. There is no rolling update or
failover. The Postgate library remains available for database bindings; removing
the standalone Postgate service is a separate change.

## Deploy

The default runner image is built from `../openworkers-runner`. Set `RUNNER_IMAGE`
to use a published image that includes the integrated services. Older images do
not serve the public ports or run the scheduler and log collector.

```bash
docker compose -f compose.yml -f compose.prod.yml build openworkers-runner
docker compose -f compose.yml -f compose.prod.yml up -d --remove-orphans
```

For migration from the old stack, stop it **before** applying the new Compose
files. This stops all runner replicas, the scheduler, the log collector and
Nginx. Do not run the old log collector alongside the new runner: it would insert
duplicate records. The new runner does not consume the old `scheduled` NATS subject.

The production mapping stays `5080` for HTTP and `50443` for HTTPS. The development
overlay maps `80` and `443`. Mount certificates through `HTTP_TLS_CERTIFICATE`
and `HTTP_TLS_KEY` in `.env` and add `-f compose.tls.yml` to enable HTTPS and
HTTP/2. Without this overlay, public HTTP uses HTTP/1.1. The runner loads
certificates on startup. There is no public
Postgate hostname. Cloudflare client-IP headers are not trusted; the recorded IP
is the TCP peer.

The production overlay mounts `inbound-allowlist.txt`, initialized with the
Cloudflare ranges from the former Nginx configuration. It admits only those TCP
peers on public ports. Edit the file for your deployment and restart the runner.
Use one IPv4/IPv6 address or CIDR per line. `#` comments are allowed. An empty
file denies all; an invalid or unreadable file prevents startup. The dev overlay
has no allowlist. Local health checks use the internal listener.

## How Database Access Works

```
Worker JS code          Runner (Rust)              Postgate (lib)         PostgreSQL
      │                      │                           │                    │
      │  env.DB.query(sql)   │                           │                    │
      ├─────────────────────►│                           │                    │
      │                      │  postgate::execute(sql)   │                    │
      │                      ├──────────────────────────►│                    │
      │                      │                           │  SQL query         │
      │                      │                           ├───────────────────►│
      │                      │                           │◄───────────────────┤
      │                      │◄──────────────────────────┤                    │
      │◄─────────────────────┤                           │                    │
```

- **Workers** use bindings (`env.DB.query()`) provided by the runner
- **Runner** uses Postgate as a Rust library for query validation and execution
- **Postgate HTTP** serves the API dev loop, and the SQL the API runs against
  a user's own database

## CLI

Use the CLI for database migrations and worker management:

```bash
# Install CLI
cargo install --git https://github.com/openworkers/openworkers-cli

# Or use Docker
docker run --rm ghcr.io/openworkers/openworkers-cli --help

# Self-hosting setup
ow alias set infra --db postgres://user:pass@localhost/openworkers
ow infra migrate run                    # Run migrations
ow infra users create admin --system    # Claim the system user
ow alias set infra --db postgres://... --user admin --force  # Set user context

# Manage workers
ow infra workers create my-worker
ow infra workers deploy my-worker script.ts
```

`users create --system` renames the system user rather than adding one, which
decides who owns the platform's resources. See
[the system user](./GETTING_STARTED.md#4-the-system-user).

## Scripts

```bash
# Database backup/restore
./database.sh backup
./database.sh restore <file>
./database.sh psql
```
