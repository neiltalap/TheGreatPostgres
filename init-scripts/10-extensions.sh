#!/usr/bin/env bash
set -euo pipefail

DB_INIT_TARGET="${POSTGRES_DB:-postgres}"
echo "[init] Ensuring extensions (timescaledb, vector if available) in ${DB_INIT_TARGET} and template1" >&2

# Create in target database
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$DB_INIT_TARGET" <<'EOSQL'
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_available_extensions WHERE name = 'timescaledb') THEN
    CREATE EXTENSION IF NOT EXISTS timescaledb;
  ELSE
    RAISE NOTICE 'timescaledb not installed in this image; skipping CREATE EXTENSION timescaledb';
  END IF;
END$$;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_available_extensions WHERE name = 'vector') THEN
    CREATE EXTENSION IF NOT EXISTS vector;
  ELSE
    RAISE NOTICE 'pgvector not installed in this image; skipping CREATE EXTENSION vector';
  END IF;
END$$;
EOSQL

# Also in template1 so future databases inherit extensions by default
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname template1 <<'EOSQL'
DO $$
BEGIN
  BEGIN
    IF EXISTS (SELECT 1 FROM pg_available_extensions WHERE name = 'timescaledb') THEN
      CREATE EXTENSION IF NOT EXISTS timescaledb;
    ELSE
      RAISE NOTICE 'timescaledb not installed in this image; skipping in template1';
    END IF;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Skipping timescaledb in template1: %', SQLERRM;
  END;
  BEGIN
    IF EXISTS (SELECT 1 FROM pg_available_extensions WHERE name = 'vector') THEN
      CREATE EXTENSION IF NOT EXISTS vector;
    ELSE
      RAISE NOTICE 'pgvector not installed in this image; skipping in template1';
    END IF;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Skipping vector in template1: %', SQLERRM;
  END;
END$$;
EOSQL

echo "[init] Extensions ensured." >&2
