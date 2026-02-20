# Getting Started (Native / No Docker)

Fully native development setup — no Docker required.

## Prerequisites

- Rust (latest stable)
- Bun
- PostgreSQL (local install)
- NATS server (local install)
- Node.js 20+ (for Angular CLI)

```bash
# macOS (Homebrew)
brew install postgresql nats-server bun node rust
```

## Clone repositories

```bash
mkdir openworkers && cd openworkers

git clone https://github.com/openworkers/openworkers-infra.git
git clone https://github.com/openworkers/openworkers-cli.git
git clone https://github.com/openworkers/openworkers-runner.git
git clone https://github.com/openworkers/openworkers-api.git
git clone https://github.com/openworkers/openworkers-dash.git
git clone https://github.com/openworkers/openworkers-scheduler.git

# Required for native Postgate
git clone https://github.com/openworkers/postgate.git

# Optional: runtime libraries
git clone https://github.com/openworkers/openworkers-core.git
git clone https://github.com/openworkers/openworkers-runtime-v8.git
```

## 1. Start PostgreSQL and NATS

```bash
brew services start postgresql
brew services start nats-server
```

Create the database if needed:

```bash
createdb openworkers
createuser openworkers
```

## 2. Setup database

```bash
ow alias set infra --db postgres://openworkers@localhost:5432/openworkers
ow infra migrate run
```

If you don't have the CLI yet, apply migrations manually:

```bash
for f in openworkers-cli/migrations/*.sql; do
  echo "Applying $f..."
  psql -U openworkers -d openworkers < "$f"
done
```

## 3. Start Postgate

```bash
cd postgate

cat > .env << 'EOF'
DATABASE_URL=postgres://openworkers@localhost:5432/openworkers
POSTGATE_PORT=3001
EOF

cargo run
```

Postgate runs on `http://localhost:3001`.

Generate a dev token for the API:

```bash
cargo run -- gen-token 00000000-0000-0000-0000-000000000000 api --permissions SELECT,INSERT,UPDATE,DELETE
```

## 4. Start API

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
bun run dev
```

Replace `pg_xxx` with the token generated in step 3.

API runs on `http://localhost:3000`.

## 5. Start Runner

```bash
cd openworkers-runner

cat > .env << 'EOF'
NATS_URL=localhost:4222
DATABASE_URL=postgres://openworkers@localhost:5432/openworkers
RUST_LOG=info
EOF

# Generate V8 snapshot (first time only)
cargo run --features v8 --bin snapshot

# Run
cargo run --features v8
```

Runner is an HTTP server on port 8080. It loads worker code from PostgreSQL and executes it in V8. Logs are published to NATS, and scheduled tasks are received from NATS.

## 6. Start Dashboard

```bash
cd openworkers-dash

bun install
bun start
```

Dashboard runs on `http://localhost:4200` with proxy to API.

## 7. Start Scheduler (optional)

```bash
cd openworkers-scheduler

cat > .env << 'EOF'
NATS_URL=localhost:4222
DATABASE_URL=postgres://openworkers@localhost:5432/openworkers
EOF

bun install
bun run dev
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
