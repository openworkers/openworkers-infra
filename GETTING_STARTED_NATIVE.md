# Getting Started (Native / CLI-first)

Fully native setup — no Docker required. Uses the CLI (`ow`) for everything: migrations, user setup, and workerized deployment of the API and Dashboard.

For a Docker-based dev setup, see [GETTING_STARTED_LOCAL.md](./GETTING_STARTED_LOCAL.md).

## Prerequisites

- Rust (latest stable)
- Bun
- PostgreSQL (local install)
- NATS server (local install)
- OpenWorkers CLI (`ow`)

```bash
# macOS (Homebrew)
brew install postgresql nats-server bun rust

# Install CLI (pick one)
cargo install openworkers-cli
# or
cargo binstall openworkers-cli
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
ow alias set infra --db postgres://openworkers@localhost:5432/openworkers --user my-github-handle --force
```

## 4. Start Postgate

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

## 5. Deploy API via CLI

Build the API and deploy it as a worker on the platform:

```bash
# Create environment, worker, and link them
ow infra env create openworkers-api-env
ow infra worker create openworkers-api
ow infra worker link openworkers-api openworkers-api-env

# Bind the database (migration 15 creates 'openworkers-api' database config)
ow infra env bind openworkers-api-env DATABASE openworkers-api --type database

# Bind assets storage (for SvelteKit client files)
ow infra storage create openworkers-api-storage
ow infra env bind openworkers-api-env ASSETS openworkers-api-storage --type assets

# Set variables and secrets
ow infra env set openworkers-api-env APP_URL http://localhost:4200
ow infra env set openworkers-api-env POSTGATE_SYSTEM_TOKEN_SECRET --secret
ow infra env set openworkers-api-env JWT_ACCESS_SECRET --secret
ow infra env set openworkers-api-env JWT_REFRESH_SECRET --secret

# Build and upload
cd openworkers-api
bun install && bun run build
ow infra worker upload openworkers-api ./build
```

In worker mode, the `DATABASE` binding provides direct database access — no Postgate HTTP proxy needed for the API itself. Postgate is still used for the gen-token step above.

## 6. Deploy Dashboard via CLI

```bash
cd openworkers-dash
bun install && bun run deploy:prepare

ow infra worker create openworkers-dash
ow infra storage create openworkers-dash-storage
ow infra env create openworkers-dash-env
ow infra env bind openworkers-dash-env ASSETS openworkers-dash-storage --type assets
ow infra worker link openworkers-dash openworkers-dash-env
ow infra worker upload openworkers-dash ./dist/openworkers
```

## 7. Start Runner

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

Runner is an HTTP server on port 8080. It loads worker code from PostgreSQL and executes it in V8. The workerized API and Dashboard are served through the Runner.

## 8. Start Scheduler (optional)

```bash
cd openworkers-scheduler

cat > .env << 'EOF'
NATS_URL=localhost:4222
DATABASE_URL=postgres://openworkers@localhost:5432/openworkers
EOF

bun install
bun dev
```

## Ports summary

| Service    | Port |
| ---------- | ---- |
| PostgreSQL | 5432 |
| NATS       | 4222 |
| Postgate   | 3001 |
| Runner     | 8080 |
