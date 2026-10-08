# Distributed Databases using PostgreSQL: Replication, Failover, Durability

| Key              | Value                                                                                                                                                                                                                                                        |
|:-----------------|:------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| **Course Codes** | MIT 8107                                                                                                                                                                                                                     |
| **Course Names** | Advanced Database Systems (Week 4-6)                                                                                                                                                                             |
| **Semester**     | September to December 2026                                                                                                                                                                                                           |
| **Lecturer**     | Allan Omondi                                                                                                                                                                                                                 |
| **Contact**      | aomondi@strathmore.edu                                                                                                                                                                                                       |
| **Note**         | The lecture contains both theory and practice.<br/>The code in this repository forms part of the practice.<br/>It is intended for educational purpose only.<br/>Recommended citation: [BibTex](https://raw.githubusercontent.com/course-files/DistributedDatabases-PostgreSQL/refs/heads/main/RecommendedCitation.bib) |

## Technology Stack

<p align="left">
<img src="https://cdn.jsdelivr.net/gh/devicons/devicon@latest/icons/docker/docker-original-wordmark.svg" width="40"/>
<img src="https://cdn.jsdelivr.net/gh/devicons/devicon@latest/icons/postgresql/postgresql-original-wordmark.svg" width="40"/>
</p>

## System Architecture

![System Architecture](/assets/images/system_architecture.jpg)

A three-node PostgreSQL 18 cluster running entirely in Docker:

- `pg-primary`: the writable primary, exposed on host port **5441**
- `pg-replica1`: a streaming replica, exposed on host port **5442**
- `pg-replica2`: a streaming replica, exposed on host port **5443**

The replicas are built using PostgreSQL streaming replication
(`pg_basebackup` against the primary, then `standby.signal` +
`primary_conninfo`). This is the same mechanism used in a production
PostgreSQL cluster.

| Item               | What it is                                                                                                                                               | Analogy                                                                       |
| ------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------- |
| `pg_basebackup`    | A tool that copies the primary's entire data directory to the replica over the network, once, at setup.                                                   | Photocopying a book                                                            |
| `standby.signal`    | An empty file. When PostgreSQL starts and finds it, the server runs as a read-only standby instead of a normal primary.                                   | A label to the photocopied book stating that "this is a copy of the original" |
| `primary_conninfo` | A connection string (`host`, `port`, `user`, `application_name`) that tells the standby where the primary is, so it can stream new changes continuously. | Noting down the original book's publisher's address so that you can receive updates whenever the book is revised. |

1. `pg_basebackup` gives the replica a complete starting copy of the data.
2. The `-R` option will write `standby.signal` and `primary_conninfo` for you.
3. When the replica starts, `standby.signal` puts it in standby mode, and `primary_conninfo` tells it where to connect.
4. The replica then receives the primary's **Write-Ahead Log (WAL)** as a continuous stream and replays it, so that it stays up to date.

**Note:**

- The base backup is a one-time snapshot. Streaming replication is what keeps the replica current afterwards.
- `application_name` inside `primary_conninfo` is how the primary identifies each replica. `synchronous_standby_names` matches against this name in later parts of the lab.
- When you run `pg_promote()` in the lab, PostgreSQL removes `standby.signal` and the node becomes a writable primary. This is why `standby.signal` is the switch between "replica" and "primary".
- `pg_basebackup` only creates the replica's starting point. If the replica later falls too far behind, or the primary removes a WAL that the replica still needs, the replica cannot catch up by streaming alone.
- In a case where the primary has removed a WAL record, you will get an error
stating `requested WAL segment ... has already been removed`. The setup uses `wal_keep_size` to prevent the primary from removing WAL records that the replicas might still need.

## Setup Verification

```bash
chmod u+x verify_lab.sh
sed -i 's/\r$//' verify_lab.sh
./verify_lab.sh
```

This script confirms all three nodes are healthy, streaming, and that a write
on the primary reaches both replicas. This is safe to run at any time; it does
not destroy data.

## Lab Manual

[Link to lab manual](distributed_databases.md)

## Clean Reset

```bash
chmod u+x reset_lab.sh
sed -i 's/\r$//' reset_lab.sh
./reset_lab.sh
```

Destroys all three nodes' data volumes and then rebuilds the cluster from
scratch. Use this between lab sessions, or whenever a cluster
has been left in a promoted / diverged / stopped state by the exercises
and needs to return to a clean starting point.

## Files

```text
.
├── LICENSE
├── README.md                       ← the file you are currently reading
├── RecommendedCitation.bib
├── assets
│   └── images
│       └── system_architecture.jpg
├── docker-compose.yml              ← the three-node cluster definition
├── incident
│   ├── 03_distributed_failover_github2012.md
│   └── 04_distributed_replication_razorpay.md
├── lab_manual.md                   ← the actual lab manual
├── reset_lab.sh
├── scripts
│   └── replica-entrypoint.sh       ← runs on every replica start: performs the
│                                     base backup on first start, then starts
│                                     PostgreSQL as a standby.
├── sql
│   └── primary
│       ├── 01_setup_replication.sh ← runs once: creates the replicator role
                                      and turns on WAL settings
│       └── 02_create_schema.sql    ← runs once: creates the database
└── verify_lab.sh

7 directories, 13 files
```

## Teardown

```bash
docker compose down -v
```
