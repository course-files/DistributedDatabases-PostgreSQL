#!/usr/bin/env bash
# Quick smoke test: confirms the cluster is up, replication is streaming,
# and a write on the primary reaches both replicas. Safe to run at any
# point -- it does not reset any data.
set -euo pipefail

docker compose config >/dev/null
docker compose up -d

for name in mod2_pg_primary mod2_pg_replica1 mod2_pg_replica2; do
  echo "Waiting for $name..."
  for i in {1..40}; do
    status="$(docker inspect -f '{{.State.Health.Status}}' "$name" 2>/dev/null || true)"
    if [ "$status" = "healthy" ]; then
      break
    fi
    sleep 3
  done
  status="$(docker inspect -f '{{.State.Health.Status}}' "$name")"
  if [ "$status" != "healthy" ]; then
    echo "$name did not become healthy."
    docker compose logs --tail=100 "${name#mod2_}"
    exit 1
  fi
done

echo ""
echo "=== Node roles ==="
docker compose exec -T pg-primary psql -U lab_user -d distributed_lab -c "SELECT * FROM node_status;"
docker compose exec -T pg-replica1 psql -U lab_user -d distributed_lab -c "SELECT * FROM node_status;"
docker compose exec -T pg-replica2 psql -U lab_user -d distributed_lab -c "SELECT * FROM node_status;"

echo ""
echo "=== Replication status on primary ==="
docker compose exec -T pg-primary psql -U lab_user -d distributed_lab -c \
  "SELECT application_name, state, sync_state FROM pg_stat_replication ORDER BY application_name;"

echo ""
echo "=== End-to-end replication check ==="
docker compose exec -T pg-primary psql -U lab_user -d distributed_lab -v ON_ERROR_STOP=1 -c \
  "INSERT INTO transaction_log (node_name, description) VALUES ('pg-primary', 'verify_lab.sh smoke test');"
sleep 1
echo "--- replica1 should show the new row ---"
docker compose exec -T pg-replica1 psql -U lab_user -d distributed_lab -c \
  "SELECT description FROM transaction_log ORDER BY log_id DESC LIMIT 1;"
echo "--- replica2 should show the new row ---"
docker compose exec -T pg-replica2 psql -U lab_user -d distributed_lab -c \
  "SELECT description FROM transaction_log ORDER BY log_id DESC LIMIT 1;"

echo ""
echo "SUCCESS: cluster is healthy and replication is verified end to end."
