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

# -s file is true if the file exists and has a size greater than zero.
# The '!' reverses the result, so ! -s is true if the file is empty or does
# not exist.
# "$PGDATA/PG_VERSION" is the path to PostgreSQL’s version marker file. The
# quotes keep the path together if it contains spaces.

if [ ! -s "$PGDATA/PG_VERSION" ]; then
    echo "[${REPLICA_NAME}] No existing data directory found. This is a first start."
    echo "[${REPLICA_NAME}] Waiting for pg-primary to accept connections..."

    # -q makes pg_isready run quietly: it suppresses its normal status message.
    # The loop still checks its exit status, retrying every second until
    # pg-primary accepts connections.

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

    # -tAc is three psql options combined:
    #   -t hides table headers and row-count footers.
    #   -A prints results without table formatting.
    #   -c runs the SQL command that follows.

    # >/dev/null 2>&1 discards both normal output and error messages:
    # > sends normal output to /dev/null, and 2>&1 sends errors to the same
    # place.

    # In short, the script quietly tries to remove the replica’s old, inactive
    # replication slot. || true makes the script continue even if that cleanup
    # command fails.
    
    PGPASSWORD=ReplicatorPass123 psql -h pg-primary -p 5432 -U replicator -d postgres -tAc \
        "SELECT pg_drop_replication_slot('${REPLICA_NAME}_slot') FROM pg_replication_slots WHERE slot_name = '${REPLICA_NAME}_slot' AND NOT active;" \
        >/dev/null 2>&1 || true

    mkdir -p "$PGDATA"
    chown postgres:postgres "$PGDATA"
    chmod 700 "$PGDATA"

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

    # -u postgres in `sudo -u postgres pg_basebackup ...` tells sudo to run the
    # command as the postgres user. `gosu` is a separate utility often used in
    # Docker containers for the same purpose; it is useful here because `sudo`
    # may not be installed or configured in a normal Docker container.
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

        # If `pg_basebackup` fails partway through, it may leave an incomplete
        # backup inside `$PGDATA`. Before retrying, this command removes the
        # directory’s contents so the next backup starts clean. It keeps the
        # `$PGDATA` directory itself, which the script created earlier.

        # The `:?` makes Bash stop with an error if `PGDATA` is unset or
        # empty, helping prevent an accidental deletion from an invalid path.
        # `rm -rf` removes files and subdirectories without prompting.

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
