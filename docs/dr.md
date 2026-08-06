# DocTrack — Disaster Recovery

## Backup

- **Script:** `/opt/backups/backup-doctrack.sh` on the Hetzner server
- **Schedule:** daily at 02:00 UTC (cron on `doctrack-n8n`)
- **Location:** `/opt/backups/doctrack/doctrack-YYYY-MM-DD-HHMMSS.sql.gz`
- **Retention:** 7 days (older files deleted automatically by the script)
- **Tool:** `pg_dump` v17 (PostgreSQL 17, `/usr/lib/postgresql/17/bin/pg_dump`)
- **Credentials:** stored in `/root/.pgpass` (mode 600), never in the script or repo

### First backup recorded — 2026-08-06

| Metric | Value |
|--------|-------|
| Compressed size | 67 KB |
| Uncompressed size | 395 KB |
| Tables in dump | 53 |
| Duration | < 30 s |

---

## Restore procedure

### Prerequisites

- A target PostgreSQL instance (Supabase project or local Postgres)
- The target connection string
- Access to the Hetzner server (`ssh hetzner`) or a copy of the `.sql.gz` file

### Steps

```bash
# 1. Copy the dump locally (if restoring from Hetzner)
scp hetzner:/opt/backups/doctrack/doctrack-YYYY-MM-DD-HHMMSS.sql.gz .

# 2. Restore into the target database
zcat doctrack-YYYY-MM-DD-HHMMSS.sql.gz \
  | psql postgresql://postgres:<password>@<host>:5432/postgres

# 3. Verify table count
psql postgresql://postgres:<password>@<host>:5432/postgres \
  -c "SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public';"
```

### Notes

- The dump includes schema and data. It does not include Supabase-managed roles or
  storage bucket contents. Document files in the `documents` storage bucket must be
  backed up separately if required.
- Object-lock (WORM) storage is deferred until WP-0 task 1 (dedicated host) is
  completed. Current backups are on-disk only — a compromised host could destroy them.
- A full restore into a nonprod Supabase project will be timed and recorded here once
  the nonprod project exists (WP-0 task 2).
