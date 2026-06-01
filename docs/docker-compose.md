# Docker Compose Setup

This document summarizes the local Docker Compose setup for the KOIN data platform.

## Service Roles

| Service | Role | Long-running |
| --- | --- | --- |
| `postgres` | Metadata database for Airflow and Superset | Yes |
| `airflow-webserver` | Airflow 3 API server and UI | Yes |
| `airflow-scheduler` | DAG scheduling and task dispatching | Yes |
| `airflow-init` | Airflow metadata migration | No |
| `dbt` | dbt BigQuery command runner | No |
| `superset` | BI dashboard service | Yes |

dbt is not exposed as a web service.
It runs as a command-line container with the local `dbt/` workspace mounted at `/usr/app`.

## Ports

| Service | Host Port | Container Port | Notes |
| --- | ---: | ---: | --- |
| Airflow API/UI | `${KOIN_DATA_AIRFLOW_PORT:-8080}` | `8080` | Open `http://localhost:8080` locally by default |
| Superset UI | `${KOIN_DATA_SUPERSET_PORT:-8088}` | `8088` | Open `http://localhost:8088` locally by default |
| Postgres | Not published | `5432` | Internal Docker network only |
| dbt | None | None | dbt runs as a command-line container, not a web server |

If `8080` or `8088` is already used on a developer machine or EC2 host, change only the host-side values in `.env`:

```text
KOIN_DATA_AIRFLOW_PORT=18080
KOIN_DATA_SUPERSET_PORT=18088
```

Postgres does not publish `5432` to the host. This is intentional for local and EC2 security.
Containers should connect to Postgres with the Docker Compose service address:

```text
postgres:5432
```

## Metadata Database Split

The Postgres container is used for service metadata, not for GA4 analytics data.

| Database | Owner | Purpose |
| --- | --- | --- |
| `airflow_metadata` | Airflow | DAG runs, task states, schedules, Airflow users |
| `superset_metadata` | Superset | Dashboard metadata, charts, users, connection metadata |

The databases are created by:

```text
docker/postgres/init-databases.sh
```

The database names are controlled by:

```text
KOIN_DATA_AIRFLOW_DB=airflow_metadata
KOIN_DATA_SUPERSET_DB=superset_metadata
```

## Analytics Data Storage

Analytics data is expected to live in BigQuery, not in the metadata Postgres container.
The initial `dbt/` directory is intentionally empty so project models can be added deliberately later.

## Local Verification

Create a local `.env` file:

```bash
cp .env.example .env
```

Build and start the services:

```bash
docker compose up -d --build
```

Check service status:

```bash
docker compose ps
```

Expected result:

```text
postgres            healthy/running
airflow-webserver   running
airflow-scheduler   running
superset            running
```

Useful logs:

```bash
docker compose logs postgres
docker compose logs airflow-webserver
docker compose logs airflow-scheduler
docker compose logs superset
```

## Build Notes

The Airflow image is based on `apache/airflow:3.0.1-python3.11`.
Use the matching Airflow constraints file during `pip install` so provider versions stay compatible with the base Airflow image.

Airflow 3 uses `airflow api-server` instead of the Airflow 2 `airflow webserver` command.

dbt is kept in a separate `ghcr.io/dbt-labs/dbt-bigquery:1.9.latest` container.
This avoids dependency conflicts between Airflow 3.x provider constraints and dbt BigQuery dependencies.

For Airflow `3.0.1` and Python `3.11`, the Dockerfile uses:

```text
https://raw.githubusercontent.com/apache/airflow/constraints-3.0.1/constraints-3.11.txt
```

Shell scripts mounted into Linux containers must use LF line endings.
The Postgres initialization script creates the service metadata databases:

```text
airflow_metadata
superset_metadata
```

Keep `*.sh` files as LF to avoid errors such as:

```text
env: 'bash\r': No such file or directory
```

## EC2 Security Group

Recommended inbound rules for an EC2 test server:

| Port | Purpose | Recommendation |
| ---: | --- | --- |
| `22` | SSH | Restrict to developer IPs |
| `8080` | Airflow UI | Restrict to team/VPN IPs |
| `8088` | Superset UI | Restrict to team/VPN IPs |
| `5432` | Postgres | Do not expose publicly |

Postgres should stay inside the Docker network unless there is a strong operational reason to expose it.
