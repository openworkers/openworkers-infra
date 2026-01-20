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
- `JWT_ACCESS_SECRET` / `JWT_REFRESH_SECRET` - Auth tokens (generate random strings)
- `HTTP_TLS_CERTIFICATE` / `HTTP_TLS_KEY` - TLS cert paths

## 2. Start database

```bash
docker compose up -d postgres
# Wait for it to be healthy
docker compose ps
```

## 3. Run migrations

```bash
# Using the CLI (recommended)
docker run --rm --network host \
  -v ~/.openworkers:/root/.openworkers \
  ghcr.io/openworkers/openworkers-cli \
  alias set infra --db postgres://$POSTGRES_USER:$POSTGRES_PASSWORD@localhost/$POSTGRES_DB

docker run --rm --network host \
  -v ~/.openworkers:/root/.openworkers \
  ghcr.io/openworkers/openworkers-cli \
  infra db migrate
```

Or if you have the CLI installed locally:

```bash
ow alias set infra --db postgres://$POSTGRES_USER:$POSTGRES_PASSWORD@localhost/$POSTGRES_DB
ow infra db migrate
```

This creates all tables including Postgate compatibility views.

## 4. Generate API token

The migrations created a database config for the API. Generate a token for it:

```bash
# Start Postgate
docker compose up -d postgate

# Generate API token
docker compose exec postgate postgate gen-token \
  aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa api \
  --permissions SELECT,INSERT,UPDATE,DELETE
```

Copy the generated token to `.env`:

```
POSTGATE_TOKEN=pg_xxx...
```

## 5. Start all services

```bash
docker compose up -d
```

## 6. Verify

```bash
docker compose ps
docker compose logs -f
```

Dashboard should be available at `https://your-domain/`.

## Updating

```bash
# Pull latest images
docker compose pull

# Apply new migrations
docker run --rm --network host \
  -v ~/.openworkers:/root/.openworkers \
  ghcr.io/openworkers/openworkers-cli \
  infra db migrate

# Restart with new images
docker compose up -d
```

## Useful Commands

```bash
# View logs
docker compose logs -f openworkers-api
docker compose logs -f openworkers-runner

# Restart a service
docker compose restart openworkers-api

# Shell into postgres
docker compose exec postgres psql -U openworkers -d openworkers

# Stop all services
docker compose down

# Stop all + remove volumes (DANGER: deletes data)
docker compose down -v
```

## Database management

Use the `database.sh` script:

```bash
# Backup
./database.sh backup

# Restore
./database.sh restore ~/backups/openworkers/openworkers-2025-01-10.dump

# Run a migration
./database.sh migrate path/to/migration.sql

# Interactive psql
./database.sh psql
```
