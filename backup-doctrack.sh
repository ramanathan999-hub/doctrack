#!/bin/bash
set -euo pipefail

PGDUMP=/usr/lib/postgresql/17/bin/pg_dump
DEST=/opt/backups/doctrack
STAMP=$(date +%Y-%m-%d-%H%M%S)
FILE=$DEST/doctrack-$STAMP.sql.gz
LOG=$DEST/backup.log

$PGDUMP -h db.syorwcsahfxbemvwdxrz.supabase.co -p 5432 -U postgres -d postgres --no-password | gzip > "$FILE"

SIZE=$(du -sh "$FILE" | cut -f1)
echo "$STAMP  OK  $SIZE  $FILE" >> "$LOG"

# Retain 7 days
find "$DEST" -name 'doctrack-*.sql.gz' -mtime +7 -delete
