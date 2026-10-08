-- Module 2 lab schema.
-- Deliberately similar in spirit to Module 1's accounts/products tables so
-- the SQL itself feels familiar; everything new in this module is in the
-- surrounding cluster, not the schema.

CREATE TABLE IF NOT EXISTS accounts (
    account_id   INTEGER PRIMARY KEY,
    account_name TEXT NOT NULL,
    balance      NUMERIC(12,2) NOT NULL CHECK (balance >= 0)
);

-- transaction_log records which node a write happened on. In Part F
-- (failover) you will use this column to make split-brain visible: after
-- a failover, two nodes can each insert rows that the other one never
-- receives.
CREATE TABLE IF NOT EXISTS transaction_log (
    log_id      BIGSERIAL PRIMARY KEY,
    event_time  TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    node_name   TEXT NOT NULL,
    description TEXT NOT NULL
);

-- A convenience view so you can always ask "which node is this, and can it
-- currently accept writes?" without memorizing the underlying function.
-- pg_is_in_recovery() returns true on a standby (replica) and false on a
-- writable primary. Because this is a VIEW, it is created once on the
-- primary and then ships to every replica automatically through normal
-- replication -- you do not need to create it again on the replicas.
CREATE OR REPLACE VIEW node_status AS
SELECT
    CASE WHEN pg_is_in_recovery()
         THEN 'REPLICA (read-only)'
         ELSE 'PRIMARY (read-write)'
    END AS role,
    pg_is_in_recovery() AS in_recovery,
    inet_server_addr()  AS server_address,
    now()               AS checked_at;

INSERT INTO accounts (account_id, account_name, balance) VALUES
    (1, 'Account A', 1000.00),
    (2, 'Account B', 1000.00)
ON CONFLICT (account_id) DO NOTHING;

INSERT INTO transaction_log (node_name, description) VALUES
    ('pg-primary', 'Initial schema and seed data created.');

-- Verify initialisation.
SELECT 'accounts' AS table_name, COUNT(*) AS row_count FROM accounts;
SELECT 'transaction_log' AS table_name, COUNT(*) AS row_count FROM transaction_log;
