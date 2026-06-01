# dbt BigQuery Setup

The dbt project lives in `dbt/koin` and runs through the Docker Compose `dbt` service.

## Files

| Path | Purpose |
| --- | --- |
| `dbt/koin/dbt_project.yml` | dbt project configuration |
| `dbt/koin/profiles.yml` | BigQuery connection profile |
| `dbt/koin/models/sources/ga4.yml` | GA4 raw BigQuery source definition |
| `dbt/koin/models/staging/stg_ga4_events.sql` | First cleaned GA4 event model |
| `dbt/koin/models/bronze` | Canonical raw event tables |
| `dbt/koin/models/silver` | Aggregated analytical tables |
| `dbt/koin/models/marts` | Superset-facing gold marts |

## Credentials

Place the BigQuery service account key at:

```text
secrets/gcp-service-account.json
```

The dbt container mounts this file as:

```text
/secrets/gcp-service-account.json
```

The default `.env` values are:

```text
DBT_TARGET=dev
GOOGLE_APPLICATION_CREDENTIALS=/secrets/gcp-service-account.json
KOIN_DATA_GCP_PROJECT=your-gcp-project
KOIN_DATA_BIGQUERY_LOCATION=asia-northeast3
KOIN_DATA_RAW_DATASET=raw_ga4
KOIN_DATA_STAGING_DATASET=staging
KOIN_DATA_BRONZE_DATASET=bronze
KOIN_DATA_SILVER_DATASET=silver
KOIN_DATA_GOLD_DATASET=gold
KOIN_DATA_GA4_TABLE_PREFIX=events_
```

## Commands

Parse the project without connecting to BigQuery:

```bash
docker compose run --rm dbt parse
```

Check the BigQuery profile and credentials:

```bash
docker compose run --rm dbt debug
```

List dbt resources:

```bash
docker compose run --rm dbt ls
```

Run the first GA4 models:

```bash
docker compose run --rm dbt run
```

Run tests:

```bash
docker compose run --rm dbt test
```
