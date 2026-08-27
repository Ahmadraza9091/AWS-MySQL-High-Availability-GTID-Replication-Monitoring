#!/bin/bash

NODE1="mysql-node1"
NODE2="mysql-node2"

FAILOVER_SCRIPT="/home/ubuntu/mysql-ha/scripts/failover.sh"
REJOIN_SCRIPT="/home/ubuntu/mysql-ha/scripts/rejoin.sh"

LOG="/home/ubuntu/mysql-ha/logs/ha-monitor.log"

FAIL_THRESHOLD=3
RECOVERY_THRESHOLD=3
CHECK_INTERVAL=10

NODE1_FAILURES=0
NODE1_RECOVERY=0
FAILOVER_DONE=0

LAST_NODE1_STATE=""
LAST_NODE2_STATE=""

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG"
}

mysql_alive() {
    local NODE="$1"

    ssh -o BatchMode=yes \
        -o ConnectTimeout=3 \
        -o ServerAliveInterval=2 \
        -o ServerAliveCountMax=2 \
        "$NODE" \
        "sudo mysqladmin ping" >/dev/null 2>&1
}

log "=========================================="
log "MySQL HA Monitor Started"
log "Node1: $NODE1"
log "Node2: $NODE2"
log "=========================================="

while true
do
    NODE1_UP=0
    NODE2_UP=0

    # ----------------------------------------
    # HEALTH CHECK
    # ----------------------------------------

    if mysql_alive "$NODE1"; then
        NODE1_UP=1
    fi

    if mysql_alive "$NODE2"; then
        NODE2_UP=1
    fi

    # ----------------------------------------
    # NODE1 HEALTHY
    # ----------------------------------------

    if [ "$NODE1_UP" -eq 1 ]; then

        if [ "$LAST_NODE1_STATE" != "UP" ]; then
            log "Node1: UP"
            LAST_NODE1_STATE="UP"
        fi

        NODE1_FAILURES=0
        NODE1_RECOVERY=$((NODE1_RECOVERY + 1))

        # ------------------------------------
        # NODE1 RECOVERY AFTER FAILOVER
        # ------------------------------------

        if [ "$FAILOVER_DONE" -eq 1 ] && \
           [ "$NODE1_RECOVERY" -ge "$RECOVERY_THRESHOLD" ]; then

            log "Node1 recovery confirmed"
            log "Starting automatic rejoin"

            if "$REJOIN_SCRIPT"; then

                log "=========================================="
                log "AUTOMATIC REJOIN SUCCESSFUL"
                log "Node1 = PRIMARY"
                log "Node2 = REPLICA"
                log "=========================================="

                FAILOVER_DONE=0
                NODE1_RECOVERY=0

            else

                log "ERROR: Automatic rejoin failed"

                # Prevent continuous rejoin attempts
                NODE1_RECOVERY=0
            fi
        fi

    # ----------------------------------------
    # NODE1 DOWN
    # ----------------------------------------

    else

        NODE1_RECOVERY=0
        NODE1_FAILURES=$((NODE1_FAILURES + 1))

        if [ "$LAST_NODE1_STATE" != "DOWN" ]; then
            log "Node1 health check failed"
            LAST_NODE1_STATE="DOWN"
        fi

        log "Node1 failure check: $NODE1_FAILURES/$FAIL_THRESHOLD"

        # ------------------------------------
        # AUTOMATIC FAILOVER
        # ------------------------------------

        if [ "$NODE1_FAILURES" -ge "$FAIL_THRESHOLD" ] && \
           [ "$FAILOVER_DONE" -eq 0 ]; then

            if [ "$NODE2_UP" -eq 1 ]; then

                log "=========================================="
                log "Node1 failure CONFIRMED"
                log "Node2 is healthy"
                log "Starting AUTOMATIC FAILOVER"
                log "=========================================="

                if "$FAILOVER_SCRIPT"; then

                    log "=========================================="
                    log "FAILOVER SUCCESSFUL"
                    log "Node2 = PRIMARY"
                    log "=========================================="

                    FAILOVER_DONE=1
                    NODE1_FAILURES=0

                else

                    log "ERROR: FAILOVER FAILED"

                fi

            else

                log "CRITICAL: Both nodes unavailable"
                log "FAILOVER CANCELLED"

            fi
        fi
    fi

    # ----------------------------------------
    # NODE2 STATE CHANGE ONLY
    # ----------------------------------------

    if [ "$NODE2_UP" -eq 1 ]; then

        if [ "$LAST_NODE2_STATE" != "UP" ]; then
            log "Node2: UP"
            LAST_NODE2_STATE="UP"
        fi

    else

        if [ "$LAST_NODE2_STATE" != "DOWN" ]; then
            log "Node2: DOWN"
            LAST_NODE2_STATE="DOWN"
        fi

    fi

    sleep "$CHECK_INTERVAL"

done
