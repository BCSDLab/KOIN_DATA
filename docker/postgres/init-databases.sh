#!/usr/bin/env bash
set -euo pipefail

# Create service metadata databases during the first Postgres initialization.
create_database() {
  local database="$1"

  psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname postgres \
    --command "SELECT 1 FROM pg_database WHERE datname = '$database'" \
    --tuples-only --no-align | grep -q 1 && return 0

  psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname postgres \
    --command "CREATE DATABASE \"$database\""
}

create_database "${KOIN_DATA_AIRFLOW_DB:-airflow_metadata}"
create_database "${KOIN_DATA_SUPERSET_DB:-superset_metadata}"
