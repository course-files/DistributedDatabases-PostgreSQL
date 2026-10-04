#!/usr/bin/env bash
# Completely resets the Module 2 cluster: destroys all three nodes' data
# volumes and rebuilds the primary + two replicas from scratch.
set -euo pipefail

echo "Stopping and removing all containers and volumes..."
docker compose down -v

echo "Rebuilding the cluster..."
docker compose up -d

echo "Waiting for the primary to become healthy..."
for i in {1..40}; do
  status="$(docker inspect -f '{{.State.Health.Status}}' mod2_pg_primary 2>/dev/null || true)"
  if [ "$status" = "healthy" ]; then
    break
  fi
  sleep 2
done
status="$(docker inspect -f '{{.State.Health.Status}}' mod2_pg_primary)"
if [ "$status" != "healthy" ]; then
  echo "Primary did not become healthy. Recent logs:"
  docker compose logs --tail=100 pg-primary
  exit 1
fi

echo "Waiting for replica1 and replica2 to become healthy (this includes a base backup and can take up to a minute)..."
for name in mod2_pg_replica1 mod2_pg_replica2; do
  for i in {1..40}; do
    status="$(docker inspect -f '{{.State.Health.Status}}' "$name" 2>/dev/null || true)"
    if [ "$status" = "healthy" ]; then
      break
    fi
    sleep 3
  done
  status="$(docker inspect -f '{{.State.Health.Status}}' "$name")"
  if [ "$status" != "healthy" ]; then
    echo "$name did not become healthy. Recent logs:"
    docker compose logs --tail=100 "${name#mod2_}"
    exit 1
  fi
done

echo ""
echo "Verifying replication is actually streaming..."
docker compose exec -T pg-primary psql -U lab_user -d distributed_lab -v ON_ERROR_STOP=1 <<-'SQL'
SELECT application_name, state, sync_state FROM pg_stat_replication ORDER BY application_name;
SQL

echo ""
echo "SUCCESS: primary + 2 replicas are up and streaming."
