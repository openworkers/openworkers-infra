# Getting Started

OpenWorkers runs its own control plane on itself: the API, and the dashboard it
serves, are workers deployed on the platform they manage. This document sets up
that mode end to end, from an empty machine to a dashboard served by the runner.

The API also runs as a plain Bun server. That is a development convenience
covered in [Development loop](#10-development-loop), not a deployment target.

## What runs where

| Process         | Language | Role                                                        |
| --------------- | -------- | ----------------------------------------------------------- |
| postgres        | -        | Single source of truth: workers, users, environments, assets metadata |
| nats            | -        | Log fan-out and scheduled events                            |
| runner          | Rust     | Executes workers, serves HTTP on 8080                       |
| postgate        | Rust     | HTTP proxy in front of postgres, used by the standalone API and for user databases |
| `ow` (CLI)      | Rust     | Migrations, users, workers, bindings, over a direct database connection |
| openworkers-api | Bun      | REST API and dashboard UI, deployed as a worker             |
| logs            | Rust     | Log streaming to the dashboard (optional)                   |
| scheduler       | Rust     | Cron events (optional)                                      |

## 1. Prerequisites

- Rust (stable). The runner, scheduler, logs, postgate and the CLI are Rust.
- Bun. The API is TypeScript.
- PostgreSQL 15+ and a NATS server, in containers or native (step 2).
- A TLS certificate and key for the dev proxy (step 9).

Install the CLI:

```bash
cargo binstall openworkers-cli
# or from source
cargo install --git https://github.com/openworkers/openworkers-cli
```

Prebuilt tarballs are listed in the
[CLI README](https://github.com/openworkers/openworkers-cli#installation).

Clone what you need:

```bash
mkdir openworkers && cd openworkers

git clone https://github.com/openworkers/openworkers-infra.git
git clone https://github.com/openworkers/openworkers-cli.git      # migrations live here
git clone https://github.com/openworkers/openworkers-runner.git
git clone https://github.com/openworkers/openworkers-api.git

git clone https://github.com/openworkers/postgate.git             # step 5
git clone https://github.com/openworkers/openworkers-logs.git     # optional
git clone https://github.com/openworkers/openworkers-scheduler.git # optional
git clone https://github.com/openworkers/openworkers-dash.git     # optional, split layout only
```

## 2. PostgreSQL and NATS

Two ordinary services. Pick either way to run them; nothing below depends on the
choice, only on the connection string.

### Containers

```bash
cd openworkers-infra
cp .env.example .env    # POSTGRES_USER / POSTGRES_PASSWORD / POSTGRES_DB at least
docker compose -f compose.yml -f compose.dev.yml up -d postgres
docker run -d --name ow-nats -p 4222:4222 nats:2.12.2-alpine3.22
```

`compose.dev.yml` publishes 5432 on the host. The `nats` service publishes no
port, so a runner or scheduler running on the host cannot reach it through
compose; run NATS directly as above, or add a `ports` mapping in your own
`compose.override.yml`.

### Native

```bash
brew install postgresql@15 nats-server
brew services start postgresql@15
brew services start nats-server

createuser openworkers
createdb -O openworkers openworkers
```

Postgres.app works the same way: start it, then run `createuser` and `createdb`
from `/Applications/Postgres.app/Contents/Versions/latest/bin`.

The rest of this document uses `postgres://openworkers@localhost:5432/openworkers`.
Add `:password` after the role name if yours has one.

## 3. CLI alias and migrations

```bash
ow alias set infra --db postgres://openworkers@localhost:5432/openworkers
ow infra migrate status
ow infra migrate run
```

`infra` is an alias name, and every command below is prefixed with it. Aliases
come in two kinds: a **db alias** (`--db`) opens a direct PostgreSQL connection,
an **api alias** (`--api`) talks to a running platform. Infrastructure commands
(`migrate`, `users`, `setup-storage`) require a db alias.

Aliases live in `~/.openworkers/config.json`. Dropping the prefix falls back to
the `default` alias, which points at the hosted API, so keep the prefix on every
command.

> **Known issue: migration 28 fails under the CLI runner.**
>
> The CLI wraps each migration file in a transaction (sqlx). Migration 28 starts
> with `ALTER TYPE ... ADD VALUE`, and PostgreSQL refuses to use a new enum value
> in the transaction that added it: `unsafe use of new value "planetscale" of
> enum type`. Everything before 28 is applied when this fires. Apply that one
> file with psql, which runs it in autocommit, then record it:
>
> ```bash
> DATABASE_URL=postgres://openworkers@localhost:5432/openworkers
> FILE=openworkers-cli/migrations/28_planetscale_provider.sql
>
> psql "$DATABASE_URL" -f "$FILE"
> psql "$DATABASE_URL" -c "INSERT INTO _sqlx_migrations
>   (version, description, installed_on, success, checksum, execution_time)
>   VALUES (28, 'planetscale provider', now(), true,
>           decode('$(shasum -a 384 "$FILE" | cut -d' ' -f1)', 'hex'), 0)"
> ```
>
> The checksum has to be the SHA-384 of the file: `migrate run` verifies applied
> migrations against it and refuses to continue on a mismatch. Then run
> `ow infra migrate run` again for whatever comes after 28.

## 4. The system user

This step decides what your dashboard shows, so read it before running it.

Migrations create one user row with the nil UUID
`00000000-0000-0000-0000-000000000000`, named `__system__`. It owns the platform's
shared resources: the `openworkers-api` database config, and every worker,
environment and storage config the CLI creates through a db alias.

`ow infra users create <handle> --system` creates nothing. It renames
`__system__` to `<handle>`. Whoever logs in as `<handle>` is the platform.

**(a) Claim it with your GitHub handle: merged identity.**

```bash
ow infra users create max-lt --system
```

GitHub sign-in looks up the GitHub numeric id first; finding none, it inserts a
user row keyed on the GitHub login, and the unique constraint on `username`
turns that insert into an update of the existing row. Your GitHub account is
then bound to the system user. You are root: your dashboard lists
`openworkers-api` and the rest of the platform resources alongside your own
workers. Convenient on a single-developer machine, and not cleanly reversible.

**(b) Claim it headless with an email: separate identity.**

```bash
ow infra users create platform@example.com --system --password
```

Password login matches `username` against the email, so the system user is
reachable only through that address and password. Your GitHub sign-in then
creates an ordinary user row with an empty dashboard: no `openworkers-api`, no
platform storage, only what that account creates. Recommended: it is the only
setup where you see the product as a user sees it.

Then point the alias at the claimed user. Every `ow infra` command creates
resources owned by it:

```bash
ow alias set infra \
  --db postgres://openworkers@localhost:5432/openworkers \
  --user platform@example.com \
  --force
```

`--force` overwrites the existing alias. `--user` is resolved to `users.id` by
exact username on every command.

## 5. Postgate and the API token

Postgate proxies SQL over HTTP. The runner embeds it as a library, so a worker-mode
API reaches the platform database through its `DATABASE` binding and needs no
Postgate service for that. Postgate is needed for two other things:

- the standalone dev loop (step 10), where the API queries postgres over HTTP
  with a `pg_...` token;
- SQL run against a *user* database from the dashboard, which the API sends to
  `POSTGATE_URL` with a token derived from `POSTGATE_SYSTEM_TOKEN_SECRET`.

```bash
cd postgate

cat > .env << 'EOF'
DATABASE_URL=postgres://openworkers@localhost:5432/openworkers
POSTGATE_PORT=6080
EOF

cargo run
```

Set the port explicitly: the binary defaults to 3000 while the rest of the stack
expects 6080 (the compose service sets it, and the API's `POSTGATE_URL` defaults
to `http://localhost:6080`).

Generate a token for the platform database, whose id is the nil UUID:

```bash
cargo run -- gen-token 00000000-0000-0000-0000-000000000000 api \
  --permissions SELECT,INSERT,UPDATE,DELETE
```

Keep the `pg_...` value for step 10.

## 6. Platform storage

Worker uploads store assets in an S3-compatible bucket. The CLI needs its
credentials before it can create any storage config:

```bash
ow infra setup-storage \
  --endpoint https://<account>.r2.cloudflarestorage.com \
  --bucket openworkers-dev \
  --access-key-id AKIA... \
  --secret-access-key ...
```

The credentials are written into the `infra` entry of
`~/.openworkers/config.json`: per machine and per alias, not in the database.

Two failure modes:

- `Storage can only be configured for DB aliases` means the alias prefix is
  missing. `ow setup-storage ...` resolves the default alias, which is an api
  alias. It is `ow infra setup-storage ...`.
- `Platform storage not configured` at the first `storage create` means this
  step was skipped. `storage create` defaults to `--provider platform` and takes
  its credentials from the alias; `--provider s3` with explicit `--bucket`,
  `--endpoint`, `--access-key-id` and `--secret-access-key` bypasses it.

## 7. Deploy the API worker

Create the worker, its environment, and the two bindings:

```bash
ow infra env create openworkers-api-env
ow infra workers create openworkers-api
ow infra workers link openworkers-api openworkers-api-env

# The platform database config, created by migration 15 under this name
ow infra env bind openworkers-api-env DATABASE openworkers-api --type database

# Bucket holding the client bundle
ow infra storage create openworkers-api-storage
ow infra env bind openworkers-api-env ASSETS openworkers-api-storage --type assets
```

The variables are listed in
[openworkers-api/README.md#environment-variables](https://github.com/openworkers/openworkers-api#environment-variables),
which is the single source of truth for what is required in which mode. A worker
deployment needs at least:

```bash
ow infra env set openworkers-api-env APP_URL https://dash.dev.localhost
ow infra env set openworkers-api-env POSTGATE_SYSTEM_TOKEN_SECRET --secret
ow infra env set openworkers-api-env JWT_ACCESS_SECRET --secret
ow infra env set openworkers-api-env JWT_REFRESH_SECRET --secret

# Same bucket as step 6: the API creates storage configs for its users
ow infra env set openworkers-api-env SHARED_STORAGE_BUCKET openworkers-dev
ow infra env set openworkers-api-env SHARED_STORAGE_ENDPOINT https://<account>.r2.cloudflarestorage.com
ow infra env set openworkers-api-env SHARED_STORAGE_PUBLIC_URL https://assets.example.com
ow infra env set openworkers-api-env SHARED_STORAGE_ACCESS_KEY_ID --secret
ow infra env set openworkers-api-env SHARED_STORAGE_SECRET_ACCESS_KEY --secret

# Without this pair, the sign-in page redirects to /sign-in?error=github-not-configured
ow infra env set openworkers-api-env GITHUB_CLIENT_ID Iv1....
ow infra env set openworkers-api-env GITHUB_CLIENT_SECRET --secret
```

Omitting a value prompts for it with masked input, which keeps secrets out of
the shell history.

Build and upload:

```bash
cd openworkers-api
bun install && bun run build
ow infra workers upload openworkers-api ./build
```

Create and link the environment before the first upload: an upload that promotes
the worker to a project inherits the environment automatically, while linking
afterwards has to cascade it. See
[openworkers-api/DEPLOY.md](https://github.com/openworkers/openworkers-api/blob/main/DEPLOY.md).

### Dashboard

Two layouts exist, and the choice shows up again in the proxy config (step 9):

- **Unified**: the SvelteKit app in `openworkers-api` serves both the API and the
  UI. One worker, nothing else to deploy.
- **Split**: the Angular dashboard is a second worker.

```bash
cd openworkers-dash
bun install && bun run deploy:prepare

ow infra workers create openworkers-dash
ow infra storage create openworkers-dash-storage
ow infra env create openworkers-dash-env
ow infra env bind openworkers-dash-env ASSETS openworkers-dash-storage --type assets
ow infra workers link openworkers-dash openworkers-dash-env
ow infra workers upload openworkers-dash ./dist/openworkers
```

## 8. Run the platform

The runner serves every worker, including the API:

```bash
cd openworkers-runner

cat > .env << 'EOF'
NATS_SERVERS=nats://localhost:4222
DATABASE_URL=postgres://openworkers@localhost:5432/openworkers
RUST_LOG=info
EOF

cargo run --features v8 --bin snapshot   # first run, and after any runtime JS change
cargo run --features v8
```

It listens on `0.0.0.0:8080`, which is not configurable, loads worker code from
postgres, and resolves each request to a worker through the `X-Worker-Id` or
`X-Worker-Name` header.

Log streaming in the dashboard needs the logs service. Its own default port
collides with the runner, and the dev proxy expects 18080:

```bash
cd openworkers-logs

cat > .env << 'EOF'
PORT=18080
NATS_SERVERS=nats://localhost:4222
DATABASE_URL=postgres://openworkers@localhost:5432/openworkers
EOF

cargo run
```

Cron events need the scheduler:

```bash
cd openworkers-scheduler

cat > .env << 'EOF'
NATS_SERVERS=nats://localhost:4222
DATABASE_URL=postgres://openworkers@localhost:5432/openworkers
EOF

cargo run
```

## 9. Dev proxy

`run-dev.sh` starts an nginx container that terminates TLS for
`dash.dev.localhost` and `*.workers.dev.localhost`:

```bash
HTTP_TLS_CERTIFICATE=/path/to/ssl.crt HTTP_TLS_KEY=/path/to/ssl.key ./run-dev.sh
```

The certificate has to cover both names; mkcert produces one in a couple of
commands. Browsers resolve `*.localhost` to loopback themselves; other tools may
need `/etc/hosts` entries.

The script picks a container runtime:

- **docker**: the container joins the host network and the `127.0.0.1` upstreams
  in the config work as written.
- **apple `container`**: no host networking. The entrypoint rewrites the
  `127.0.0.1` upstreams to the VM's gateway, so host processes have to listen
  beyond loopback. Start the API dev server with `--host 0.0.0.0`. The Angular
  `dev` script pins `ng serve` to `127.0.0.1` and stays unreachable this way.

`nginx/servers/dash.dev.conf` routes `/api`, the worker upload endpoint, and the
`@dash` catch-all to one of three upstreams. One `proxy_pass` line is active and
the alternatives sit commented next to it:

| Upstream         | Address        | Serves                        | `X-Worker-Name`   |
| ---------------- | -------------- | ----------------------------- | ----------------- |
| `workers_server` | 127.0.0.1:8080 | the API worker, through the runner | `openworkers-api` |
| `api_server`     | 127.0.0.1:7000 | the standalone Bun dev server | ignored           |
| `dash_server`    | 127.0.0.1:4200 | `ng serve`, split layout only | ignored           |

Dogfooding points every location at `workers_server`. The header has to name a
worker that exists: with the unified app there is no `openworkers-dash` worker,
and sending that name gets `No worker or project found for request` from the
runner.

Logs keep their own upstream (`log_server`, 127.0.0.1:18080) in every mode.

With the runner up and the proxy pointing at it, the platform answers on
`https://dash.dev.localhost`:

```bash
curl https://dash.dev.localhost/api/health
```

A 502 means the runner is down; `No worker or project found for request` means
the upload of step 7 did not land under the name the proxy sends.

## 10. Development loop

**Iterate on the API.** The SvelteKit app runs as a Bun process against Postgate:

```bash
cd openworkers-api

cat > .env << 'EOF'
PORT=7000
APP_URL=https://dash.dev.localhost
POSTGATE_URL=http://localhost:6080
POSTGATE_TOKEN=pg_xxx
POSTGATE_SYSTEM_TOKEN_SECRET=dev-system-token-secret-at-least-32-chars
JWT_ACCESS_SECRET=dev-access-secret-at-least-32-chars-long
JWT_REFRESH_SECRET=dev-refresh-secret-at-least-32-chars-long
EOF

bun install
bun dev            # add --host 0.0.0.0 behind apple's container tool
```

`pg_xxx` is the token from step 5. Vite listens on `PORT`, or 5173 when unset,
and 7000 is what the `api_server` upstream expects; point `@dash` and `/api`
there while working this way. Without a `DATABASE` binding the app falls back to
the token, and a missing one gives `No database client available: neither
DATABASE binding nor POSTGATE_TOKEN configured`.

**Test what you ship.** Redeploy the worker and switch the proxy back to
`workers_server`:

```bash
cd openworkers-api
bun run build && ow infra workers upload openworkers-api ./build
```

`package.json` wraps this as `deploy:local`, `deploy:dev` and `deploy:main`, one
per alias. Bindings, the runner's `fetch` routing, and the isolate's environment
only behave like production in this mode, so anything touching them has to be
checked here before it counts as working.

## 11. Ports

| Service                | Port      | Set by                                       |
| ---------------------- | --------- | -------------------------------------------- |
| PostgreSQL             | 5432      | postgres                                     |
| NATS                   | 4222      | nats-server                                  |
| Postgate               | 6080      | `POSTGATE_PORT`; the binary alone defaults to 3000 |
| API, standalone        | 7000      | `PORT`; vite alone defaults to 5173          |
| Angular dashboard      | 4200      | `ng serve`                                   |
| Runner                 | 8080      | hardcoded                                    |
| Logs                   | 18080     | `PORT`; the binary alone defaults to 8080    |
| Dev proxy              | 80, 443   | `run-dev.sh`                                 |

The nginx dev config hardcodes 7000, 4200, 8080 and 18080 as upstreams, so
changing one of those means changing `nginx/servers/dash.dev.conf` too.

## 12. Symptoms

| Message                                                  | Cause                                                            |
| -------------------------------------------------------- | ---------------------------------------------------------------- |
| `unsafe use of new value "planetscale" of enum type`     | Migration 28 through the CLI runner (step 3)                     |
| `Storage can only be configured for DB aliases`          | `setup-storage` without the alias prefix (step 6)                |
| `Platform storage not configured`                        | `setup-storage` never run for this alias (step 6)                |
| `User not found`                                         | The alias `--user` matches no `users.username` (step 4)          |
| `/sign-in?error=github-not-configured`                   | `GITHUB_CLIENT_ID` unset in the API environment (step 7)         |
| `No worker or project found for request`                 | `X-Worker-Name` names a worker that does not exist (step 9)      |
| `No database client available`                           | Standalone API with neither binding nor `POSTGATE_TOKEN` (step 10) |

## Container stack

`compose.yml` runs the whole stack in containers, with the API and the dashboard
as images rather than workers. Setup is identical up to step 6, since the
database, the system user and the platform storage are the same, and `.env`
carries the variables the containers read.

```bash
docker compose up -d
docker compose ps
docker compose logs -f openworkers-api

docker compose pull        # update images
ow infra migrate run       # apply new migrations
docker compose up -d

./database.sh backup
./database.sh restore ~/backups/openworkers/openworkers-2026-01-10.dump
./database.sh psql
```

In this layout the API has no bindings, so it needs `POSTGATE_URL` and
`POSTGATE_TOKEN` to reach the database, exactly like the dev loop of step 10.
