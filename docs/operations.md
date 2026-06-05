# Operations

## Access Model

Tailscale is only for server operators who need SSH and Docker access.
Club members do not join the tailnet to view Superset dashboards.

```text
Operators -> Tailscale -> Lightsail SSH
Members   -> Browser   -> https://superset.bcsdlab.com
```

## Public Ports

Open only these ports in the Lightsail firewall.

| Port | Purpose | Public |
| --- | --- | --- |
| 22 | SSH | No, use Tailscale only |
| 80 | HTTP challenge / redirect | Yes |
| 443 | HTTPS Superset access | Yes |
| 8080 | Airflow API server | No |
| 8088 | Superset app server | No |
| 5432 | Postgres | No |

Airflow and Superset are bound to `127.0.0.1` on the host. Postgres is available only inside the Docker network.

## First Deploy

```bash
cp .env.example .env
docker compose up -d --build
./scripts/init_airflow.sh
```

Before running the stack, update `.env` values:

```env
KOIN_DATA_SUPERSET_DOMAIN=superset.bcsdlab.com
KOIN_DATA_CADDY_EMAIL=your-email@example.com
KOIN_DATA_POSTGRES_PASSWORD=replace-with-strong-password
SUPERSET_SECRET_KEY=replace-with-strong-secret
AIRFLOW__WEBSERVER__SECRET_KEY=replace-with-strong-secret
```

Create a DNS A record for `superset.bcsdlab.com` pointing to the Lightsail static IP before starting Caddy.

## Runtime Commands

```bash
docker compose ps
docker compose logs -f caddy
docker compose logs -f superset
docker compose logs -f airflow-webserver
docker compose run --rm dbt debug
docker compose run --rm dbt run
```

## Backups

Postgres stores Airflow and Superset metadata. Back it up regularly.

```bash
./scripts/backup_postgres.sh
```

Also keep Lightsail snapshots for server-level recovery.

## Superset Permissions

Use login-based access by default.

| Role | Target | Permission |
| --- | --- | --- |
| Admin | Server / BI admins | Full management |
| Alpha | Dashboard builders | Create and edit charts and dashboards |
| Gamma / Viewer | Club members | View dashboards only |

Do not grant club members SQL Lab, database connection, or admin permissions.

Public dashboards are allowed only for data that can be visible to anyone on the internet.
