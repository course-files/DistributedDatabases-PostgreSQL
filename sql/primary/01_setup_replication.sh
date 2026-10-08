#!/usr/bin/env bash
# Module 2 lab -- runs once, automatically, the first time the primary's
# data volume is created. It prepares the primary to accept streaming
# replicas.

# `set -euo pipefail`: Avoids cases where scripts silently continue executing after a command fails.
#  -e → Exit the entire script if any command returns a non-zero exit code (if any command fails).
#  -u → Exit the entire script if you try to use an uninitialized variable (a variable that has not been set).
#  -o pipefail → If any command in a pipeline fails, the entire pipeline will be considered to have failed, and the script will exit.
set -euo pipefail

echo "[primary-init] Configuring PostgreSQL for streaming replication..."

# 1. Create a dedicated replication role.
#
#    NOTE: the password below is hardcoded in plain text. That is
#    acceptable ONLY because this cluster lives on an isolated Docker
#    network used for a classroom exercise. A production system would
#    supply this credential through a secrets manager and would never
#    commit it to a script.

# Bash passes the following lines to `psql` as input until it reaches the
# closing `EOSQL`. The `-` allows leading tabs to be stripped from those lines.
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    CREATE ROLE replicator WITH REPLICATION LOGIN PASSWORD 'ReplicatorPass123';
EOSQL

# 2. Allow the replica containers to authenticate as "replicator" against
#    the special "replication" pseudo-database. 0.0.0.0/0 is deliberately
#    broad here -- this is acceptable only because this Docker network is
#    not reachable from outside the host running the lab in a classroom environment.
echo "host replication replicator 0.0.0.0/0 scram-sha-256" >> "$PGDATA/pg_hba.conf"

# Also allow "replicator" to open ordinary (non-replication) connections,
# which the lab uses later to let students inspect a replica directly.
echo "host all replicator 0.0.0.0/0 scram-sha-256" >> "$PGDATA/pg_hba.conf"

# 3. Turn on the settings a primary needs before any replica can stream
#    from it. wal_level, max_wal_senders and max_replication_slots are
#    POSTMASTER-context settings (POSTMASTER means these settings can only be
#    applied at server start): editing them here only takes effect
#    because the Docker entrypoint restarts PostgreSQL after every
#    docker-entrypoint-initdb.d script has finished running.

# cat normally prints text, but here >> redirects its input to the end of the
# file named by $PGDATA/postgresql.conf (the >> appends rather than overwrites).

# <<-'EOCONF' starts a here-document: the lines that follow are provided as
# input to cat until the closing EOCONF.
# The - allows leading tabs to be stripped from those lines. So this command
# appends the PostgreSQL settings in the here-document to postgresql.conf.
cat >> "$PGDATA/postgresql.conf" <<-'EOCONF'

# --- Module 2 lab: replication settings ---
wal_level = replica
max_wal_senders = 10
max_replication_slots = 10
hot_standby = on
# A generous, unconditional floor on how much WAL the primary keeps on
# disk, on top of whatever each replica's own replication slot already
# reserves. Each replica's slot is the mechanism that is SUPPOSED to
# guarantee the primary never removes WAL a connected replica still
# needs -- but a slot only reliably protects WAL from the moment it is
# created, and a base backup is a multi-step operation (checkpoint,
# copy, stream) with real elapsed time in between those steps. Under
# load -- most notably when more than one replica's base backup runs
# at once, as the two replicas' entrypoint scripts are written to avoid
# via depends_on -- a fast-moving primary can still outrun that
# protection. wal_keep_size gives every base backup this fixed margin
# regardless of slot timing, independent of how many replicas are
# joining or how busy the primary is.
wal_keep_size = 512MB
# synchronous_standby_names is intentionally left unset here.
# Parts D and E of the lab set it explicitly with ALTER SYSTEM so you can
# observe the exact moment replication becomes synchronous.
EOCONF

echo "[primary-init] Replication configuration complete."
