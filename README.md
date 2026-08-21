# OpenWorkers Infrastructure

Self-hosted Cloudflare Workers runtime.

## Getting Started

**[GETTING_STARTED.md](./GETTING_STARTED.md)** walks through a full setup: infra
services in containers or native, migrations, the system user, storage, the API
deployed as a worker, and the dev proxy.

## Stack

| Service                                                                       | Description                                                |
| ----------------------------------------------------------------------------- | ---------------------------------------------------------- |
| postgres                                                                      | PostgreSQL database                                        |
| nats                                                                          | Message queue for worker communication                     |
| [postgate](https://github.com/openworkers/postgate)                           | HTTP proxy for PostgreSQL (query validation, multi-tenant) |
| [openworkers-api](https://github.com/openworkers/openworkers-api)             | REST API and dashboard UI, deployed as a worker            |
| [openworkers-runner](https://github.com/openworkers/openworkers-runner)       | Worker runtime (V8 isolates)                               |
| [openworkers-logs](https://github.com/openworkers/openworkers-logs)           | Log aggregator                                             |
| [openworkers-scheduler](https://github.com/openworkers/openworkers-scheduler) | Cron job scheduler                                         |
| [openworkers-cli](https://github.com/openworkers/openworkers-cli)             | CLI for migrations & worker management                     |
| openworkers-proxy                                                             | Nginx reverse proxy                                        |

## Architecture

```
                     +-----------------+
                     |  nginx (proxy)  |
                     +----+-------+----+
                   sse/ws |       | http
                  +-------+--+  +-+--------------------------+
                  |  logs *  |  | runner *                   |
                  +-------+--+  | runs the api worker        |
                          |     | (rest api + dashboard ui)  |
                          |     +-+--------------------------+
                          |       |
                     +----+-------+----+     +--------------+
                     |      nats       +-----+ scheduler *  |
                     +-----------------+     +--------------+

                     * = connects to PostgreSQL
```

`api` runs as a worker on the platform itself, served by the runner, and
serves the dashboard UI. The API reaches postgres through a runtime `DATABASE` binding, which
leaves `postgate` for the API dev loop and for user databases.

Services `logs` and `scheduler` are not required for the core runtime but provide additional functionality (log streaming and cron jobs).

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
