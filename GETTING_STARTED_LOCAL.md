# Getting Started (Local Development)

Development setup for contributing to OpenWorkers. Uses Docker for PostgreSQL and NATS.

For a fully native setup (no Docker), see [GETTING_STARTED_NATIVE.md](./GETTING_STARTED_NATIVE.md).

## Prerequisites

- Rust (latest stable)
- Bun
- Docker + Docker Compose
- Node.js 20+ (for Angular CLI)

## Clone repositories

```bash
mkdir openworkers && cd openworkers

git clone https://github.com/openworkers/openworkers-infra.git
git clone https://github.com/openworkers/openworkers-cli.git
git clone https://github.com/openworkers/openworkers-runner.git
git clone https://github.com/openworkers/openworkers-api.git
git clone https://github.com/openworkers/openworkers-dash.git
git clone https://github.com/openworkers/openworkers-scheduler.git

# Optional: runtime libraries
git clone https://github.com/openworkers/openworkers-core.git
git clone https://github.com/openworkers/openworkers-runtime-v8.git
git clone https://github.com/openworkers/postgate.git
```

## 1. Start PostgreSQL and NATS

```bash
cd openworkers-infra
docker compose up -d postgres nats
```

## 2. Setup database

```bash
ow alias set infra --db postgres://openworkers:openworkers@localhost:5432/openworkers
ow infra migrate run
```

If you don't have the CLI yet, apply migrations manually:

```bash
for f in openworkers-cli/migrations/*.sql; do
  echo "Applying $f..."
  docker compose exec -T postgres psql -U openworkers -d openworkers < "$f"
done
```

## 3. Claim the system user

The system user (`00000000-...`) owns shared resources (the API database config, etc.). Claim it with your admin identity.

**The username must match exactly how you will log in:**

- **GitHub OAuth** → use your GitHub username (e.g. `max-lt`)
- **Email/password (headless)** → use your email (e.g. `admin@example.com`)

> **Important:** Anyone who signs up or logs in with this username gets admin access to platform resources. Double-check it before proceeding.

```bash
# GitHub login
ow infra users create my-github-handle --system

# Or email/password login (headless, no GitHub)
ow infra users create admin@example.com --system --password
```

Update the alias to reference the admin user:

```bash
ow alias set infra --db postgres://openworkers:openworkers@localhost:5432/openworkers --user my-github-handle --force
```

## 4. Start Postgate

```bash
cd postgate

cat > .env << 'EOF'
DATABASE_URL=postgres://openworkers:openworkers@localhost:5432/openworkers
POSTGATE_PORT=3001
EOF

cargo run
```

Postgate runs on `http://localhost:3001`.

Generate a dev token for the API:

```bash
cargo run -- gen-token 00000000-0000-0000-0000-000000000000 api --permissions SELECT,INSERT,UPDATE,DELETE
```

## 5. Start API

```bash
cd openworkers-api

cat > .env << 'EOF'
PORT=3000
POSTGATE_URL=http://localhost:3001
POSTGATE_TOKEN=pg_xxx
POSTGATE_SYSTEM_TOKEN_SECRET=dev-system-token-secret-at-least-32-chars
JWT_ACCESS_SECRET=dev-access-secret-at-least-32-chars-long
JWT_REFRESH_SECRET=dev-refresh-secret-at-least-32-chars-long
EOF

bun install
bun dev
```

Replace `pg_xxx` with the token generated in step 4.

API runs on `http://localhost:3000`.

## 6. Start Runner

```bash
cd openworkers-runner

cat > .env << 'EOF'
NATS_URL=localhost:4222
DATABASE_URL=postgres://openworkers:openworkers@localhost:5432/openworkers
RUST_LOG=info
EOF

# Generate V8 snapshot (first time only)
cargo run --features v8 --bin snapshot

# Run
cargo run --features v8
```

Runner is an HTTP server on port 8080. It loads worker code from PostgreSQL and executes it in V8. Logs are published to NATS, and scheduled tasks are received from NATS.

## 7. Start Dashboard

```bash
cd openworkers-dash

bun install
bun dev
```

Dashboard runs on `http://localhost:4200` with proxy to API.

## 8. Start Scheduler (optional)

```bash
cd openworkers-scheduler

cat > .env << 'EOF'
NATS_URL=localhost:4222
DATABASE_URL=postgres://openworkers:openworkers@localhost:5432/openworkers
EOF

bun install
bun dev
```

## Development workflow

### Runner (Rust)

```bash
cd openworkers-runner

cargo test --features v8           # Run all tests
cargo test --features v8 test_name # Run specific test

# After modifying runtime JS (in openworkers-runtime-v8)
cargo run --features v8 --bin snapshot
```

### API (TypeScript/Bun)

```bash
cd openworkers-api

bun dev         # Development with hot reload
bun test        # Run tests
```

### Dashboard (Angular)

```bash
cd openworkers-dash

bun dev         # Development server
bun run build   # Production build
```

## Ports summary

| Service    | Port |
| ---------- | ---- |
| PostgreSQL | 5432 |
| NATS       | 4222 |
| Postgate   | 3001 |
| API        | 3000 |
| Dashboard  | 4200 |
| Runner     | 8080 |

## Tips

- Use `./database.sh psql` from infra to quickly access the database
- Dashboard proxies `/api` requests to the API (configured in `proxy.conf.json`)
- Runner logs show worker execution details with `RUST_LOG=debug`
