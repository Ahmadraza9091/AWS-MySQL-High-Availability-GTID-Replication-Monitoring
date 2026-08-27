#!/bin/bash

PRIMARY="mysql-node2"
LOG="/home/ubuntu/mysql-ha/logs/failover.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG"
}

log "Starting automatic failover"

# Check Node2
if ! ssh -o BatchMode=yes -o ConnectTimeout=5 "$PRIMARY" \
    "sudo mysqladmin ping" >/dev/null 2>&1
then
    log "ERROR: Node2 is not reachable"
    exit 1
fi

log "Node2 is healthy"

# Stop replication
if ! ssh "$PRIMARY" "sudo mysql -e 'STOP REPLICA;'"
then
    log "ERROR: Could not stop replica"
    exit 1
fi

log "Replica stopped"

# Promote Node2
if ! ssh "$PRIMARY" "sudo mysql -e 'SET GLOBAL super_read_only=OFF; SET GLOBAL read_only=OFF;'"
then
    log "ERROR: Could not promote Node2"
    exit 1
fi

log "Node2 promoted to MASTER"

# Verify
READ_ONLY=$(ssh "$PRIMARY" \
    "sudo mysql -N -e 'SELECT @@read_only;'" 2>/dev/null)

SUPER_READ_ONLY=$(ssh "$PRIMARY" \
    "sudo mysql -N -e 'SELECT @@super_read_only;'" 2>/dev/null)

if [ "$READ_ONLY" = "0" ] && [ "$SUPER_READ_ONLY" = "0" ]; then
    log "FAILOVER SUCCESSFUL"
    log "Node2 is now MASTER"
    exit 0
else
    log "ERROR: Node2 promotion verification failed"
    exit 1
fi
