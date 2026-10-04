#!/usr/bin/env bash
# Module 2 lab -- custom entrypoint for a replica container.
#
# The official postgres image's own entrypoint only knows how to either
# (a) initialise a brand-new, empty database, or (b) start an existing one.
# It has no built-in concept of "join an existing primary as a streaming
# replica" -- that is a standard PostgreSQL administration task, and this
# script performs it explicitly so every step is visible to you rather
# than hidden inside the image.
set -euo pipefail

PGDATA="/var/lib/postgresql/18/docker"
REPLICA_NAME="${REPLICA_NAME:?REPLICA_NAME environment variable must be set}"

if [ ! -s "$PGDATA/PG_VERSION" ]; then
    echo "[${REPLICA_NAME}] No existing data directory found. This is a first start."
    echo "[${REPLICA_NAME}] Waiting for pg-primary to accept connections..."

    until pg_isready -h pg-primary -p 5432 -q; do
        sleep 1
    done
    # pg_isready only confirms the server accepts TCP connections; give the
    # primary's own init scripts (role creation, config reload) a moment
    # to finish committing before we try to authenticate as "replicator".
    sleep 3

    echo "[${REPLICA_NAME}] Primary is ready. Taking a base backup and registering as a streaming replica..."

    # Defensive cleanup: if an EARLIER attempt at joining got partway
    # through -- created its replication slot on the primary, then
    # failed before finishing the backup -- that slot is left behind
    # even though this container has no usable data directory to show
    # for it. Without this, every retry would fail immediately with
    # "replication slot ... already exists", permanently, until someone
    # noticed and fixed it by hand. Dropping it first (only if it is not
    # currently in use by a genuinely in-progress backup) makes a retry
    # self-heal instead.
    PGPASSWORD=ReplicatorPass123 psql -h pg-primary -p 5432 -U replicator -d postgres -tAc \
        "SELECT pg_drop_replication_slot('${REPLICA_NAME}_slot') FROM pg_replication_slots WHERE slot_name = '${REPLICA_NAME}_slot' AND NOT active;" \
        >/dev/null 2>&1 || true

    mkdir -p "$PGDATA"
    chown postgres:postgres "$PGDATA"
    chmod 0700 "$PGDATA"

    # -d   : a full libpq connection string, so we can set application_name
    #        here. This is the name PostgreSQL will match against
    #        synchronous_standby_names later in the lab -- if it is not
    #        set correctly now, Part D and Part E will not work.
    # -D   : where to write the copied data directory.
    # -Fp  : plain format (a real, directly usable data directory, not a tar).
    # -Xs  : stream the WAL generated during the backup itself, so the
    #        backup is immediately consistent.
    # -C -S: create a dedicated physical replication slot on the primary
    #        for this replica, named after it. A slot tells the primary
    #        "do not remove WAL this replica might still need", even if
    #        the replica is temporarily disconnected.
    # -R   : write standby.signal and a primary_conninfo entry so the
    #        server starts up already knowing it is a standby.
    # -v -P: verbose progress output, useful the first time you watch this run.
    #
    # Retried up to 5 times: a base backup can still fail transiently
    # (e.g. if the primary is under unusually heavy load at that exact
    # moment), and because this container has restart: "no", a single
    # failure would otherwise leave it stopped until a person noticed
    # and restarted it by hand.
    attempt=1
    until gosu postgres pg_basebackup \
        -d "host=pg-primary port=5432 user=replicator password=ReplicatorPass123 application_name=${REPLICA_NAME}" \
        -D "$PGDATA" \
        -Fp -Xs \
        -C -S "${REPLICA_NAME}_slot" \
        -R \
        -v -P
    do
        if [ "$attempt" -ge 5 ]; then
            echo "[${REPLICA_NAME}] pg_basebackup failed after $attempt attempts. Giving up."
            exit 1
        fi
        echo "[${REPLICA_NAME}] pg_basebackup attempt $attempt failed. Cleaning up and retrying in 5 seconds..."
        PGPASSWORD=ReplicatorPass123 psql -h pg-primary -p 5432 -U replicator -d postgres -tAc \
            "SELECT pg_drop_replication_slot('${REPLICA_NAME}_slot') FROM pg_replication_slots WHERE slot_name = '${REPLICA_NAME}_slot' AND NOT active;" \
            >/dev/null 2>&1 || true
        rm -rf "${PGDATA:?}"/*
        attempt=$((attempt + 1))
        sleep 5
    done

    echo "[${REPLICA_NAME}] Base backup complete."
else
    echo "[${REPLICA_NAME}] Existing data directory found -- resuming as a replica without a fresh base backup."
fi

echo "[${REPLICA_NAME}] Starting PostgreSQL..."
exec gosu postgres postgres -D "$PGDATA"
