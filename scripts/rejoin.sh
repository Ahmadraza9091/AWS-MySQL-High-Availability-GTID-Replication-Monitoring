#!/bin/bash

set -u
set -o pipefail

PRIMARY="mysql-node2"
REPLICA="mysql-node1"

PRIMARY_IP="10.0.12.97"
REPLICA_IP="10.0.11.95"

LOG="/home/ubuntu/mysql-ha/logs/rejoin.log"

REPL_USER="repl"
REPL_PASSWORD="ReplPassword@123"

SYNC_ATTEMPTS=30
SYNC_INTERVAL=2

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG"
}

# ============================================================
# START
# ============================================================

log "=========================================="
log "Starting automatic rejoin + failback"
log "=========================================="

# ============================================================
# 1. CHECK NODE2
# ============================================================

if ! ssh \
    -o BatchMode=yes \
    -o ConnectTimeout=5 \
    "$PRIMARY" \
    "sudo mysqladmin ping" >/dev/null 2>&1
then
    log "ERROR: Node2 is not reachable"
    exit 1
fi

log "Node2 is healthy"

# ============================================================
# 2. CHECK NODE1
# ============================================================

if ! ssh \
    -o BatchMode=yes \
    -o ConnectTimeout=5 \
    "$REPLICA" \
    "sudo mysqladmin ping" >/dev/null 2>&1
then
    log "ERROR: Node1 is not reachable"
    exit 1
fi

log "Node1 is healthy"

# ============================================================
# 3. PREPARE NODE1 AS REPLICA
# ============================================================

if ! ssh "$REPLICA" "sudo mysql -e \"
STOP REPLICA;
SET GLOBAL super_read_only=ON;
SET GLOBAL read_only=ON;
\""
then
    log "ERROR: Failed to prepare Node1"
    exit 1
fi

log "Node1 prepared as REPLICA"

# ============================================================
# 4. CONFIGURE NODE1 -> NODE2 REPLICATION
# ============================================================

if ! ssh "$REPLICA" "sudo mysql -e \"
CHANGE REPLICATION SOURCE TO
    SOURCE_HOST='$PRIMARY_IP',
    SOURCE_PORT=3306,
    SOURCE_USER='$REPL_USER',
    SOURCE_PASSWORD='$REPL_PASSWORD',
    SOURCE_AUTO_POSITION=1,
    GET_SOURCE_PUBLIC_KEY=1;
\""
then
    log "ERROR: Failed to configure Node1 replication"
    exit 1
fi

log "GTID replication configured"

# ============================================================
# 5. START NODE1 REPLICATION
# ============================================================

if ! ssh "$REPLICA" \
    "sudo mysql -e 'START REPLICA;'"
then
    log "ERROR: Failed to start Node1 replication"
    exit 1
fi

log "Node1 replication started"

# ============================================================
# 6. WAIT FOR NODE1 SYNCHRONIZATION
# ============================================================

log "Waiting for Node1 to synchronize..."

SYNC_OK=0

for i in $(seq 1 "$SYNC_ATTEMPTS")
do

    STATUS=$(ssh "$REPLICA" \
        "sudo mysql -e 'SHOW REPLICA STATUS\G'" 2>/dev/null || true)

    IO=$(echo "$STATUS" | awk -F': ' '/Replica_IO_Running:/ {print $2}')
    SQL=$(echo "$STATUS" | awk -F': ' '/Replica_SQL_Running:/ {print $2}')
    LAG=$(echo "$STATUS" | awk -F': ' '/Seconds_Behind_Source:/ {print $2}')

    log "Node1 sync check $i/$SYNC_ATTEMPTS - IO=$IO SQL=$SQL Lag=$LAG"

    if [ "$IO" = "Yes" ] &&
       [ "$SQL" = "Yes" ] &&
       [ "$LAG" = "0" ]; then

        SYNC_OK=1
        break
    fi

    sleep "$SYNC_INTERVAL"
done

if [ "$SYNC_OK" -ne 1 ]; then
    log "ERROR: Node1 synchronization failed"
    exit 1
fi

log "Node1 synchronization COMPLETE"

# ============================================================
# 7. STOP NODE1 REPLICATION
# ============================================================

if ! ssh "$REPLICA" \
    "sudo mysql -e 'STOP REPLICA;'"
then
    log "ERROR: Failed to stop Node1 replication"
    exit 1
fi

log "Node1 replication stopped"

# ============================================================
# 8. STOP NODE2 REPLICATION
# ============================================================

if ! ssh "$PRIMARY" \
    "sudo mysql -e 'STOP REPLICA;'"
then
    log "ERROR: Could not stop Node2 replication"
    exit 1
fi

log "Node2 replication stopped"

# ============================================================
# 9. MAKE NODE2 REPLICA
# ============================================================

if ! ssh "$PRIMARY" "sudo mysql -e \"
SET GLOBAL super_read_only=ON;
SET GLOBAL read_only=ON;
\""
then
    log "ERROR: Failed to set Node2 read-only"
    exit 1
fi

log "Node2 changed to REPLICA"

# ============================================================
# 10. CONFIGURE NODE2 -> NODE1 REPLICATION
# ============================================================

if ! ssh "$PRIMARY" "sudo mysql -e \"
CHANGE REPLICATION SOURCE TO
    SOURCE_HOST='$REPLICA_IP',
    SOURCE_PORT=3306,
    SOURCE_USER='$REPL_USER',
    SOURCE_PASSWORD='$REPL_PASSWORD',
    SOURCE_AUTO_POSITION=1,
    GET_SOURCE_PUBLIC_KEY=1;
\""
then
    log "ERROR: Failed to configure Node2 replication"
    exit 1
fi

log "Node2 replication configured"

# ============================================================
# 11. START NODE2 REPLICATION
# ============================================================

if ! ssh "$PRIMARY" \
    "sudo mysql -e 'START REPLICA;'"
then
    log "ERROR: Failed to start Node2 replication"
    exit 1
fi

log "Node2 replication started"

# ============================================================
# 11.1 WAIT FOR NODE2 SYNCHRONIZATION
# ============================================================

log "Waiting for Node2 to synchronize..."

SYNC_OK=0

for i in $(seq 1 "$SYNC_ATTEMPTS")
do

    STATUS=$(ssh "$PRIMARY" \
        "sudo mysql -e 'SHOW REPLICA STATUS\G'" 2>/dev/null || true)

    IO=$(echo "$STATUS" | awk -F': ' '/Replica_IO_Running:/ {print $2}')
    SQL=$(echo "$STATUS" | awk -F': ' '/Replica_SQL_Running:/ {print $2}')
    LAG=$(echo "$STATUS" | awk -F': ' '/Seconds_Behind_Source:/ {print $2}')

    log "Node2 sync check $i/$SYNC_ATTEMPTS - IO=$IO SQL=$SQL Lag=$LAG"

    if [ "$IO" = "Yes" ] &&
       [ "$SQL" = "Yes" ] &&
       [ "$LAG" = "0" ]; then

        SYNC_OK=1
        break
    fi

    sleep "$SYNC_INTERVAL"
done

if [ "$SYNC_OK" -ne 1 ]; then
    log "ERROR: Node2 synchronization failed"
    exit 1
fi

log "Node2 synchronization COMPLETE"

# ============================================================
# 12. PROMOTE NODE1
# ============================================================

if ! ssh "$REPLICA" "sudo mysql -e \"
SET GLOBAL super_read_only=OFF;
SET GLOBAL read_only=OFF;
\""
then
    log "ERROR: Failed to promote Node1"
    exit 1
fi

log "Node1 promoted to PRIMARY"

# ============================================================
# 13. FINAL TOPOLOGY VERIFICATION
# ============================================================

NODE1_STATUS=$(ssh "$REPLICA" \
    "sudo mysql -N -e 'SELECT @@read_only, @@super_read_only;'" \
    2>/dev/null | xargs)

NODE2_STATUS=$(ssh "$PRIMARY" \
    "sudo mysql -N -e 'SELECT @@read_only, @@super_read_only;'" \
    2>/dev/null | xargs)

log "Node1 status: [$NODE1_STATUS]"
log "Node2 status: [$NODE2_STATUS]"

# ============================================================
# 14. VERIFY NODE2 REPLICATION
# ============================================================

NODE2_REPLICA_STATUS=$(ssh "$PRIMARY" \
    "sudo mysql -e 'SHOW REPLICA STATUS\G'" \
    2>/dev/null || true)

NODE2_IO=$(echo "$NODE2_REPLICA_STATUS" |
    awk -F': ' '/Replica_IO_Running:/ {print $2}')

NODE2_SQL=$(echo "$NODE2_REPLICA_STATUS" |
    awk -F': ' '/Replica_SQL_Running:/ {print $2}')

NODE2_LAG=$(echo "$NODE2_REPLICA_STATUS" |
    awk -F': ' '/Seconds_Behind_Source:/ {print $2}')

log "Node2 replication: IO=$NODE2_IO SQL=$NODE2_SQL Lag=$NODE2_LAG"

# ============================================================
# 15. FINAL SUCCESS CHECK
# ============================================================

if [ "$NODE1_STATUS" = "0 0" ] &&
   [ "$NODE2_STATUS" = "1 1" ] &&
   [ "$NODE2_IO" = "Yes" ] &&
   [ "$NODE2_SQL" = "Yes" ] &&
   [ "$NODE2_LAG" = "0" ]; then

    log "=========================================="
    log "AUTOMATIC FAILBACK SUCCESSFUL"
    log "Node1 = PRIMARY"
    log "Node2 = REPLICA"
    log "Node2 IO = Yes"
    log "Node2 SQL = Yes"
    log "Replication Lag = 0"
    log "=========================================="

    exit 0

else

    log "=========================================="
    log "ERROR: FINAL TOPOLOGY VERIFICATION FAILED"
    log "Node1 status: [$NODE1_STATUS]"
    log "Node2 status: [$NODE2_STATUS]"
    log "Node2 IO: $NODE2_IO"
    log "Node2 SQL: $NODE2_SQL"
    log "Node2 Lag: $NODE2_LAG"
    log "=========================================="

    exit 1

fi

