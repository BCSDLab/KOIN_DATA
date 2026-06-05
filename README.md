# KOIN_DATA

GA4 데이터를 BigQuery, Airflow, dbt, Superset으로 운영하기 위한 데이터 플랫폼 monorepo입니다.

## 아키텍처

```text
GA4
  -> BigQuery raw_ga4
  -> Airflow + dbt on Docker Compose
  -> BigQuery bronze/silver/gold
  -> Superset dashboards
```

BigQuery가 대량 데이터 저장과 처리를 담당합니다. VM은 Airflow, dbt, Superset, metadata DB를 실행하고 관리하는 서버입니다.

## 폴더 구조

```text
KOIN_DATA/
  AGENTS.md
  README.md
  .env.example
  docker-compose.yml

  docker/
    airflow/
    superset/

  airflow/
    dags/
    plugins/
    logs/

  dbt/            # 초기에는 빈 폴더, 모델은 단계적으로 추가

  scripts/
  docs/
  secrets/
  data/
```

## 빠른 시작

1. 환경변수 템플릿을 복사합니다.

```bash
cp .env.example .env
```

2. `.env` 값을 채웁니다.

3. 서비스를 빌드하고 실행합니다.

```bash
docker compose up -d --build
```

4. 필요하면 Airflow를 초기화합니다.

```bash
./scripts/init_airflow.sh
```

## 네이밍

- GitHub repo: `KOIN_DATA`
- Docker project: `koin-data`
- dbt workspace: `dbt/`
- Python, dbt, SQL 식별자: `underscore_case`
- 환경변수 prefix: `KOIN_DATA_`

## Docker Compose Reference

- [Docker Compose setup](docs/docker-compose.md)
