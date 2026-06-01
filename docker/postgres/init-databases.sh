#!/usr/bin/env bash
set -euo pipefail

# Create service metadata databases during the first Postgres initialization.
create_database() {
  local database="$1"
  local exists

  exists="$(
    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname postgres \
      --tuples-only --no-align \
      --command "SELECT 1 FROM pg_database WHERE datname = '${database}'"
  )"

  if [[ "$exists" != "1" ]]; then
    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname postgres \
      --command "CREATE DATABASE \"${database}\""
  fi
}

create_database "${KOIN_DATA_AIRFLOW_DB:-airflow_metadata}"
create_database "${KOIN_DATA_SUPERSET_DB:-superset_metadata}"
