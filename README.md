# OpenWorkers Infrastructure

Self-hosted Cloudflare Workers runtime.

## Getting Started

**[GETTING_STARTED.md](./GETTING_STARTED.md)** walks through a full setup: infra
services in containers or native, migrations, the system user, storage, the API
deployed as a worker, and the public listeners.

## Stack

| Service            | Role                                                                    |
| ------------------ | ----------------------------------------------------------------------- |
| PostgreSQL         | Platform data and worker logs                                           |
| openworkers-runner | Public HTTP and HTTPS, workers, crons, log storage and log streams      |
| postgate           | HTTP database API on the Compose network; no public route               |
| openworkers-api    | REST API and dashboard, deployed as a worker                            |
| openworkers-cli    | Migrations and platform administration                                  |

One runner serves the public traffic. It does not use nginx, NATS,
openworkers-logs or openworkers-scheduler. The internal listener
`127.0.0.1:8080` of the runner serves the worker-to-worker calls and the admin
endpoints; Compose does not publish it.

The runner holds a PostgreSQL advisory lock, and a second runner on the same
database does not start. There is no rolling update and no failover.

## Deploy

`compose.yml` runs the published runner image. Set `RUNNER_IMAGE` to run
another image. The production overlay publishes HTTP on `5080` and HTTPS on
`50443`, mounts the TLS files that `HTTP_TLS_CERTIFICATE` and `HTTP_TLS_KEY`
give in `.env`, and mounts `inbound-allowlist.txt`.

On the production host, after you copy the Compose files and the allowlist:

```bash
docker compose -f compose.yml -f compose.prod.yml pull openworkers-runner
docker compose -f compose.yml -f compose.prod.yml up -d --remove-orphans
```

Compose stops the old runner before it starts the new one, so the traffic stops
for that time. `--remove-orphans` removes the containers of nginx, NATS,
openworkers-logs and openworkers-scheduler. Do not keep openworkers-logs or
openworkers-scheduler on the database of the runner.

The allowlist has the Cloudflare ranges. Only these peers can connect to the
public ports, and the runner reads the client address from `cf-connecting-ip`.
When Cloudflare changes its ranges, edit the file and restart the runner. Before
the first deploy, check that Docker gives the runner the real peer address: if
the runner logs `connection refused by the inbound allowlist` for each request,
Docker replaces the address (for example with `docker-proxy` on IPv6).

The development overlay builds the image from `../openworkers-runner` and
publishes HTTP on `80`. Add `-f compose.tls.yml` for HTTPS on `443`.

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
