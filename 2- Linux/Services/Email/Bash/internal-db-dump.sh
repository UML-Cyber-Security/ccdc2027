#!/usr/bin/env bash
set -euo pipefail

### CONFIG (EDIT THIS)
# Choose one:
#   mysql | postgres | sqlite
DB_TYPE="mysql"

BACKUP_BASE="$HOME/db-backups"
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
DEST="$BACKUP_BASE/$DB_TYPE-$TIMESTAMP"

mkdir -p "$DEST"

echo "[+] Database type : $DB_TYPE"
echo "[+] Backup dest    : $DEST"

### MYSQL / MARIADB
if [[ "$DB_TYPE" == "mysql" ]]; then

  if command -v mysqldump >/dev/null 2>&1; then
    echo "[+] Running MySQL dump..."

    mysqldump --all-databases > "$DEST/mysql_all.sql" 2>/dev/null || {
      echo "[!] MySQL dump failed (auth/permissions likely required)"
    }

  else
    echo "[!] mysqldump not found"
  fi
fi

### POSTGRESQL
if [[ "$DB_TYPE" == "postgres" ]]; then

  if command -v pg_dumpall >/dev/null 2>&1; then
    echo "[+] Running PostgreSQL dump..."

    pg_dumpall > "$DEST/postgres_all.sql" 2>/dev/null || {
      echo "[!] PostgreSQL dump failed (auth/permissions likely required)"
    }

  else
    echo "[!] pg_dumpall not found"
  fi
fi

### SQLITE
if [[ "$DB_TYPE" == "sqlite" ]]; then

  echo "[+] Searching for SQLite databases..."

  FOUND=0

  while IFS= read -r db; do
    FOUND=1
    echo "[+] Found SQLite DB: $db"

    NAME=$(basename "$db")
    cp -a "$db" "$DEST/${NAME}" 2>/dev/null || {
      echo "[!] Failed to copy $db"
    }

  done < <(find / -type f \( -name "*.db" -o -name "*.sqlite" -o -name "*.sqlite3" \) 2>/dev/null | head -n 50)

  if [[ "$FOUND" -eq 0 ]]; then
    echo "[!] No SQLite databases found"
  fi
fi

### SUMMARY
echo "======================================"
echo "[+] Backup complete"
echo "[+] Stored in: $DEST"
echo "======================================"