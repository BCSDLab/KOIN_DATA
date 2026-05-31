#!/usr/bin/env bash
set -euo pipefail

create_database() {
  local database="$1"
  psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname postgres <<SQL
SELECT 'CREATE DATABASE ${database}'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '${database}')\gexec
SQL
}

create_database "${KOIN_DATA_AIRFLOW_DB:-airflow_metadata}"
create_database "${KOIN_DATA_SUPERSET_DB:-superset_metadata}"
