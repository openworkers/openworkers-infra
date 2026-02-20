# Getting Started (Docker Compose)

Self-hosted deployment using Docker Compose.

## Prerequisites

- Docker + Docker Compose
- TLS certificates (for HTTPS)
- A domain name pointing to your server

## 1. Configure environment

```bash
cp .env.example .env
# Edit .env with your values
```

**Required variables:**

- `POSTGRES_USER` / `POSTGRES_PASSWORD` / `POSTGRES_DB` - Database credentials
- `GITHUB_CLIENT_ID` / `GITHUB_CLIENT_SECRET` - OAuth (for dashboard login)
- `JWT_ACCESS_SECRET` / `JWT_REFRESH_SECRET` - Auth tokens (>= 32 chars each)
- `POSTGATE_SYSTEM_TOKEN_SECRET` - System token HMAC secret (>= 32 chars)
- `HTTP_TLS_CERTIFICATE` / `HTTP_TLS_KEY` - TLS cert paths

## 2. Start database

```bash
docker compose up -d postgres
# Wait for it to be healthy
docker compose ps
```

## 3. Configure CLI alias

```bash
ow alias set infra --db postgres://$POSTGRES_USER:$POSTGRES_PASSWORD@localhost/$POSTGRES_DB
```

Or using Docker if you don't have the CLI installed locally:

```bash
docker run --rm --network host \
  -v ~/.openworkers:/root/.openworkers \
  ghcr.io/openworkers/openworkers-cli \
  alias set infra --db postgres://$POSTGRES_USER:$POSTGRES_PASSWORD@localhost/$POSTGRES_DB
```

## 4. Run migrations

```bash
ow infra migrate status
ow infra migrate run
```

## 5. Claim the system user

The system user (`00000000-...`) owns shared resources (the platform database config, etc.). Claim it with your admin identity.

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
ow alias set infra --db postgres://... --user my-github-handle --force
```

## 6. Generate Postgate token

The migrations created a database config for the API. Start Postgate and generate a token:

```bash
docker compose up -d postgate

docker compose exec postgate postgate gen-token \
  00000000-0000-0000-0000-000000000000 api \
  --permissions SELECT,INSERT,UPDATE,DELETE
```

Copy the generated token (`pg_xxx...`) to `.env` as `POSTGATE_TOKEN`.

## 7. Start all services

```bash
docker compose up -d
```

## 8. Verify

```bash
docker compose ps
docker compose logs -f
```

Dashboard should be available at `https://your-domain/`.

You can now manage workers via CLI:

```bash
ow infra workers create my-worker
ow infra workers deploy my-worker script.ts
```

## Workerized deployment (optional)

The API and Dashboard can also run as workers on the platform itself instead of as Docker containers. See [openworkers-api/DEPLOY.md](https://github.com/openworkers/openworkers-api/blob/main/DEPLOY.md) for instructions.

In this mode, Postgate HTTP is optional too — the workerized API uses runtime database bindings directly.

## Updating

```bash
# Pull latest images
docker compose pull

# Apply new migrations
ow infra migrate run

# Restart with new images
docker compose up -d
```

## Useful commands

```bash
# View logs
docker compose logs -f openworkers-api
docker compose logs -f openworkers-runner

# Restart a service
docker compose restart openworkers-api

# Shell into postgres
docker compose exec postgres psql -U $POSTGRES_USER -d $POSTGRES_DB

# Stop all services
docker compose down

# Stop all + remove volumes (DANGER: deletes data)
docker compose down -v
```

## Database management

```bash
# Check migration status
ow infra migrate status

# Run pending migrations
ow infra migrate run

# Baseline (mark all as applied without running)
ow infra migrate baseline

# User management
ow infra users list
ow infra users create username          # GitHub login
ow infra users create email --password  # Email/password login
ow infra users delete username
```

Using the `database.sh` script:

```bash
./database.sh backup
./database.sh restore ~/backups/openworkers/openworkers-2025-01-10.dump
./database.sh psql
```
