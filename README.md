# Distributed Databases using PostgreSQL: Replication, Failover, Durability

# Collaborative Git Workflows

| Key              | Value                                                                                                                                                                                                                                                        |
|:-----------------|:------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| **Course Codes** | MIT 8107                                                                                                                                                                                                                     |
| **Course Names** | MIT 8107: Advanced Database Systems (Week 4-6)                                                                                                                                                                             |
| **Semester**     | September to December 2026                                                                                                                                                                                                           |
| **Lecturer**     | Allan Omondi                                                                                                                                                                                                                 |
| **Contact**      | aomondi@strathmore.edu                                                                                                                                                                                                       |
| **Note**         | The lecture contains both theory and practice.<br/>The code in this repository forms part of the practice.<br/>It is intended for educational purpose only.<br/>Recommended citation: [BibTex](https://raw.githubusercontent.com/course-files/DistributedDatabases-PostgreSQL/refs/heads/main/RecommendedCitation.bib) |

## What this environment is

A three-node PostgreSQL 18 cluster running entirely in Docker:

- `pg-primary` — the writable primary, exposed on host port **5441**
- `pg-replica1` — a streaming replica, exposed on host port **5442**
- `pg-replica2` — a streaming replica, exposed on host port **5443**

The replicas are built using real PostgreSQL streaming replication
(`pg_basebackup` against the primary, then `standby.signal` +
`primary_conninfo`) — the same mechanism a production PostgreSQL cluster
uses, not a simplified simulation.

## First-time setup

```bash
docker compose up -d
docker compose ps
```

Wait for all three services to show `healthy`. The replicas take longer
than the primary on first start, because each one performs a real base
backup from the primary before it can start.

Connect to any node:

```bash
docker compose exec pg-primary  psql -U lab_user -d distributed_lab
docker compose exec pg-replica1 psql -U lab_user -d distributed_lab
docker compose exec pg-replica2 psql -U lab_user -d distributed_lab
```

## Automated check

```bash
chmod u+x verify_lab.sh
sed -i 's/\r$//' verify_lab.sh
./verify_lab.sh
```

Confirms all three nodes are healthy, streaming, and that a write on the
primary reaches both replicas. Safe to run at any time — it does not
destroy data.

## Clean reset

```bash
chmod u+x reset_lab.sh
sed -i 's/\r$//' reset_lab.sh
./reset_lab.sh
```

Destroys all three nodes' data volumes and rebuilds the cluster from
scratch. Use this between lab sessions, or whenever a cluster
has been left in a promoted / diverged / stopped state by the exercises
and needs to return to a clean starting point.

## Files

```
docker-compose.yml            -- the three-node cluster definition
sql/primary/01_setup_replication.sh   -- runs once: creates the replicator
                                          role and turns on WAL settings
sql/primary/02_create_schema.sql      -- runs once: creates the lab schema
scripts/replica-entrypoint.sh -- runs on every replica start: performs the
                                  base backup on first start, then starts
                                  PostgreSQL as a standby
reset_lab.sh                  -- full reset (destroys data)
verify_lab.sh                 -- smoke test (does not destroy data)
lab_manual.md        -- the actual lab manual
```

## A note on credentials

The replication role's password is hardcoded in
`sql/primary/01_setup_replication.sh` as a plain string. This is
acceptable only because the cluster runs on an isolated Docker network for
a classroom exercise with no external exposure beyond the mapped
localhost ports. The lab manual flags this explicitly as a
simplification that would be inappropriate in production.
