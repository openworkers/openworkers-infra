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

## 3. Configure CLI alias

```bash
# Using the CLI (recommended)
docker run --rm --network host \
  -v ~/.openworkers:/root/.openworkers \
  ghcr.io/openworkers/openworkers-cli \
  alias set infra --db postgres://$POSTGRES_USER:$POSTGRES_PASSWORD@localhost/$POSTGRES_DB
```

Or if you have the CLI installed locally:

```bash
ow alias set infra --db postgres://$POSTGRES_USER:$POSTGRES_PASSWORD@localhost/$POSTGRES_DB
```

## 4. Run migrations

**Option A: Using the CLI (recommended)**

```bash
# Using Docker
docker run --rm --network host \
  -v ~/.openworkers:/root/.openworkers \
  ghcr.io/openworkers/openworkers-cli \
  infra migrate run

# Or locally
ow infra migrate run
```

**Option B: Manual SQL files**

If you prefer to apply migrations manually:

```bash
for f in openworkers-cli/migrations/*.sql; do
  echo "Applying $f..."
  docker compose exec -T postgres psql -U $POSTGRES_USER -d $POSTGRES_DB < "$f"
done
```

**If you already ran migrations manually:**

Mark them as applied so the CLI doesn't re-run them:

```bash
ow infra migrate baseline
```

This creates all tables including Postgate compatibility views.

## 5. Create first user

```bash
# Using Docker
docker run --rm --network host \
  -v ~/.openworkers:/root/.openworkers \
  ghcr.io/openworkers/openworkers-cli \
  infra users create admin

# Or locally
ow infra users create admin
```

## 6. Configure user in alias

```bash
# Using Docker
docker run --rm --network host \
  -v ~/.openworkers:/root/.openworkers \
  ghcr.io/openworkers/openworkers-cli \
  alias set infra --db postgres://$POSTGRES_USER:$POSTGRES_PASSWORD@localhost/$POSTGRES_DB --user admin --force

# Or locally
ow alias set infra --db postgres://$POSTGRES_USER:$POSTGRES_PASSWORD@localhost/$POSTGRES_DB --user admin --force
```

Now the CLI can manage workers on behalf of the `admin` user.

## 7. Generate API token

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

## 8. Start all services

```bash
docker compose up -d
```

## 9. Verify

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

## Updating

```bash
# Pull latest images
docker compose pull

# Apply new migrations
docker run --rm --network host \
  -v ~/.openworkers:/root/.openworkers \
  ghcr.io/openworkers/openworkers-cli \
  infra migrate run

# Or locally
ow infra migrate run

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

**Using the CLI:**

```bash
# Check migration status
ow infra migrate status

# Run pending migrations
ow infra migrate run

# Baseline (mark all as applied without running)
ow infra migrate baseline

# User management
ow infra users list
ow infra users create username
ow infra users delete username
```

**Using the `database.sh` script:**

```bash
# Backup
./database.sh backup

# Restore
./database.sh restore ~/backups/openworkers/openworkers-2025-01-10.dump

# Run a migration manually
./database.sh migrate path/to/migration.sql

# Interactive psql
./database.sh psql
```
