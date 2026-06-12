#!/usr/bin/env bash
# Initialises the MSNoise project (once), enables the tomo plugin, then runs
# whatever command was requested (CLI / web admin / jupyter).
set -euo pipefail

PROJECT_DIR="${MSNOISE_PROJECT_DIR:-/project}"
DB_TECH="${DB_TECH:-sqlite}"
cd "$PROJECT_DIR"

init_sqlite() {
  # tech=1 -> creates msnoise.sqlite + db.ini in the current (project) folder.
  python -c "from msnoise.s000installer import main; main(tech=1)"
}

wait_for_mysql() {
  python - <<'PY'
import os, sys, time, pymysql
cfg = dict(
    host=os.environ.get("MYSQL_HOST", "mariadb"),
    user=os.environ.get("MYSQL_USER", "msnoise"),
    password=os.environ.get("MYSQL_PASSWORD", "msnoise"),
    database=os.environ.get("MYSQL_DB", "msnoise"),
)
for i in range(60):
    try:
        pymysql.connect(**cfg).close()
        print("[entrypoint] MySQL is ready")
        sys.exit(0)
    except Exception as e:
        print(f"[entrypoint] Waiting for MySQL ({i + 1}/60): {e}")
        time.sleep(2)
sys.exit("[entrypoint] ERROR: MySQL never became reachable")
PY
}

init_mysql() {
  wait_for_mysql
  # The msnoise CLI cannot pass MySQL credentials, so call the installer
  # directly with the values from the environment.
  python - <<'PY'
import os
from msnoise.s000installer import main
main(tech=2,
     hostname=os.environ.get("MYSQL_HOST", "mariadb"),
     username=os.environ.get("MYSQL_USER", "msnoise"),
     password=os.environ.get("MYSQL_PASSWORD", "msnoise"),
     database=os.environ.get("MYSQL_DB", "msnoise"))
PY
}

if [ ! -f "$PROJECT_DIR/db.ini" ]; then
  echo "[entrypoint] No db.ini found - initialising MSNoise project (DB_TECH=$DB_TECH)..."
  if [ "$DB_TECH" = "mysql" ]; then init_mysql; else init_sqlite; fi
  echo "[entrypoint] Enabling the msnoise_tomo plugin..."
  msnoise config set plugins=msnoise_tomo
  echo "[entrypoint] MSNoise project ready in $PROJECT_DIR"
else
  echo "[entrypoint] Using existing MSNoise project in $PROJECT_DIR"
fi

exec "$@"
