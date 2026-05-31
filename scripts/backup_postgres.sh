#!/usr/bin/env bash
set -euo pipefail

BACKUP_DIR="${BACKUP_DIR:-backups/postgres}"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"

mkdir -p "${BACKUP_DIR}"
docker compose exec -T postgres pg_dumpall -U "${KOIN_DATA_POSTGRES_USER:-koin}" > "${BACKUP_DIR}/postgres_${TIMESTAMP}.sql"
