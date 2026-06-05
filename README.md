# KOIN_DATA

GA4 데이터를 Airflow, dbt, BigQuery, Superset으로 처리하고 시각화하기 위한 데이터 파이프라인 프로젝트입니다.

## Overview

이 프로젝트는 Docker Compose 기반으로 실행됩니다.

```text
GA4 data
-> BigQuery raw data
-> Airflow orchestration
-> dbt bronze/silver/gold modeling
-> Superset dashboards
```

운영 환경에서는 AWS Lightsail 서버에 배포합니다.
Tailscale은 동아리원 전체 대시보드 조회용이 아니라, 운영진의 SSH 접속과 서버 관리를 위한 접근 수단입니다.

```text
운영진
-> Tailscale
-> Lightsail SSH 접속
-> Docker / Airflow / Superset / Postgres 관리

동아리원
-> 브라우저
-> Superset HTTPS 주소 접속
```

## Architecture

```text
Browser
-> https://superset.bcsdlab.com
-> Caddy reverse proxy
-> Superset:8088
-> BigQuery / Postgres
```

현재 DNS 연결 전에는 운영진이 SSH 터널로 Superset을 확인합니다.

```bash
ssh -L 8089:127.0.0.1:8088 ubuntu@100.80.218.102
```

터널을 열어둔 상태에서 브라우저로 접속합니다.

```text
http://127.0.0.1:8089
```

## Services

| Service | Purpose | Exposure |
| --- | --- | --- |
| Caddy | HTTPS reverse proxy | Public 80/443 |
| Superset | Dashboard web app | Host localhost only |
| Airflow webserver | DAG/API management | Host localhost only |
| Airflow scheduler | DAG scheduling | Docker network |
| Postgres | Airflow/Superset metadata DB | Docker network |
| dbt | Data modeling commands | Run on demand |

## Ports

| Port | Service | Production exposure |
| --- | --- | --- |
| 80 | Caddy HTTP | Public |
| 443 | Caddy HTTPS | Public |
| 8088 | Superset | Not public |
| 8080 | Airflow | Not public |
| 5432 | Postgres | Not public |

Superset and Airflow are bound to `127.0.0.1` on the server.
Postgres is only reachable inside the Docker Compose network.

## Directory Structure

```text
KOIN_DATA/
  README.md
  .env.example
  docker-compose.yml

  airflow/
    dags/
    logs/
    plugins/

  dbt/

  docker/
    airflow/
    caddy/
    postgres/
    superset/

  docs/
    architecture.md
    deploy-lightsail.md
    docker-compose.md
    operations.md

  scripts/
    backup_postgres.sh
    init_airflow.sh

  secrets/
```

## Local or Server Setup

Create the environment file.

```bash
cp .env.example .env
```

Update the required values in `.env`.

```env
KOIN_DATA_SUPERSET_DOMAIN=superset.bcsdlab.com
KOIN_DATA_POSTGRES_PASSWORD=replace-with-strong-password
SUPERSET_SECRET_KEY=replace-with-strong-secret
AIRFLOW__WEBSERVER__SECRET_KEY=replace-with-strong-secret
SUPERSET_ADMIN_PASSWORD=replace-with-strong-password
```

Start the stack.

```bash
docker compose up -d --build
```

Initialize Airflow metadata DB if needed.

```bash
./scripts/init_airflow.sh
```

Check service status.

```bash
docker compose ps
```

## Lightsail Deployment

The project is deployed on the Lightsail server under:

```text
/home/ubuntu/KOIN_DATA
```

Server access:

```bash
ssh ubuntu@100.80.218.102
```

Production DNS should point to the Lightsail public IP.

```text
superset.bcsdlab.com -> 3.39.229.133
```

After DNS is connected, Caddy automatically issues and renews HTTPS certificates.

More details:

```text
docs/deploy-lightsail.md
docs/operations.md
```

## Useful Commands

```bash
docker compose ps
docker compose logs -f caddy
docker compose logs -f superset
docker compose logs -f airflow-webserver
docker compose run --rm dbt debug
docker compose run --rm dbt run
./scripts/backup_postgres.sh
```

## Security Notes

- Do not commit `.env`.
- Do not commit files in `secrets/`.
- Do not expose Superset `8088` directly to the internet.
- Do not expose Airflow `8080` directly to the internet.
- Do not expose Postgres `5432` directly to the internet.
- Give club members viewer-level Superset permissions only.
- Use Public Dashboard only for data that can be visible to anyone.
