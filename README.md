AWS MySQL High Availability, GTID Replication & Complete Monitoring

Production-style MySQL High Availability and Monitoring project built on AWS EC2 without Docker.

This project demonstrates:

AWS infrastructure
Bastion architecture
MySQL 8
GTID-based replication
Source/Replica architecture
Custom Bash-based failover automation
Replica recovery/rejoin
Prometheus
Grafana
mysqld_exporter
node_exporter
Loki
Promtail
Nagios
NRPE
Alerting
Failure testing
Linux/system administration
1. Project Overview

The project consists of two MySQL EC2 instances.

Initially:

MySQL Node 1
    │
    │ GTID Replication
    ▼
MySQL Node 2

Node 1 acts as the Source/Primary and Node 2 acts as the Replica.

If Node 1 fails, custom HA automation detects the failure and promotes Node 2.

After Node 1 is recovered, it can be reconfigured and synchronized as a replica.

2. Final Architecture
                           INTERNET
                              │
                              │ SSH
                              ▼
                     ┌──────────────────┐
                     │   BASTION EC2    │
                     │                  │
                     │ SSH Access       │
                     │ HA Scripts       │
                     │ Administration   │
                     └────────┬─────────┘
                              │
                    AWS VPC / Private Network
                              │
                 ┌────────────┴────────────┐
                 │                         │
                 ▼                         ▼
        ┌─────────────────┐       ┌─────────────────┐
        │   MySQL Node 1  │       │   MySQL Node 2  │
        │      EC2        │       │      EC2        │
        │                 │       │                 │
        │    PRIMARY      │──────▶│     REPLICA     │
        │    MySQL 8      │ GTID  │     MySQL 8     │
        └────────┬────────┘       └────────┬────────┘
                 │                         │
                 └────────────┬────────────┘
                              │
                       Monitoring Layer
                              │
          ┌───────────────────┼───────────────────┐
          │                   │                   │
          ▼                   ▼                   ▼
     Prometheus             Nagios             Promtail
          │                   │                   │
          ▼                   ▼                   ▼
       Grafana               NRPE                Loki
          │                                       │
          └───────────────────┬───────────────────┘
                              ▼
                     Monitoring & Alerting
3. Project Components
Component	Purpose
AWS EC2	Compute
AWS VPC	Network isolation
Bastion	Secure SSH access
MySQL Node 1	Primary/Source
MySQL Node 2	Replica
GTID	Replication
Bash	HA automation
systemd	HA service management
Prometheus	Metrics collection
mysqld_exporter	MySQL metrics
node_exporter	Linux metrics
Grafana	Visualization & alerting
Loki	Log aggregation
Promtail	Log collection
Nagios	Infrastructure monitoring
NRPE	Remote checks
4. AWS Infrastructure

Recommended infrastructure:

VPC
│
├── Public Subnet
│      │
│      └── Bastion
│
└── Private Subnet
       │
       ├── MySQL Node 1
       │
       └── MySQL Node 2
EC2 Instances
Bastion

Used for:

SSH access
Administration
HA scripts
Operational commands
MySQL Node 1

Initial role:

PRIMARY / SOURCE
MySQL Node 2

Initial role:

REPLICA
5. AWS Security Groups

Recommended rules:

Bastion Security Group

Inbound:

SSH 22
Source: Your IP

Do not use:

0.0.0.0/0

for SSH in a production environment.

MySQL Security Group

Allow:

TCP 3306
Source: Bastion / trusted private security group
Monitoring Ports

Depending on where monitoring services are installed:

9100   node_exporter
9104   mysqld_exporter
5666   NRPE
9090   Prometheus
3000   Grafana
3100   Loki

These should only be accessible from trusted monitoring hosts.

6. Connect to Bastion

From local machine:

ssh -i linux_practice.pem ubuntu@BASTION_PUBLIC_IP

Fix PEM permissions if required:

chmod 400 linux_practice.pem
7. Connect from Bastion to MySQL Nodes

Example:

ssh ubuntu@MYSQL_NODE_1_PRIVATE_IP

and:

ssh ubuntu@MYSQL_NODE_2_PRIVATE_IP

The Bastion acts as the administration entry point.

8. Update Ubuntu

On both MySQL nodes:

sudo apt update
sudo apt upgrade -y

Install useful utilities:

sudo apt install -y \
curl \
wget \
vim \
git \
net-tools \
netcat-openbsd \
unzip \
jq
9. Install MySQL

On both nodes:

sudo apt install mysql-server -y

Check:

sudo systemctl status mysql

Enable MySQL at boot:

sudo systemctl enable mysql

Verify version:

mysql --version
10. Verify MySQL Listening

Run:

sudo ss -lntp | grep 3306

Expected:

LISTEN ... 3306 ... mysqld

Test from Bastion:

nc -zv MYSQL_NODE_1_PRIVATE_IP 3306

and:

nc -zv MYSQL_NODE_2_PRIVATE_IP 3306
11. MySQL Configuration

This is one of the most important parts of the project.

Configuration file:

/etc/mysql/mysql.conf.d/mysqld.cnf
12. Configure MySQL Node 1

Edit:

sudo nano /etc/mysql/mysql.conf.d/mysqld.cnf

Add/modify:

[mysqld]

server-id=1

log_bin=mysql-bin

binlog_format=ROW

gtid_mode=ON

enforce_gtid_consistency=ON

log_replica_updates=ON

Depending on the exact MySQL package/version, existing configuration entries may need to be modified instead of duplicated.

13. Why These Parameters Are Required
server-id
server-id=1

Uniquely identifies Node 1 in replication.

Node 2 must have a different value.

log_bin
log_bin=mysql-bin

Enables binary logging.

Replication uses binary logs to transfer transactions.

binlog_format
binlog_format=ROW

Uses row-based replication.

gtid_mode
gtid_mode=ON

Enables Global Transaction Identifiers.

enforce_gtid_consistency
enforce_gtid_consistency=ON

Prevents transactions that are incompatible with GTID replication.

log_replica_updates
log_replica_updates=ON

Allows replicated transactions to be written to the binary log.

This is useful when a replica may later be promoted and become a source.

14. Configure MySQL Node 2

On Node 2:

sudo nano /etc/mysql/mysql.conf.d/mysqld.cnf

Use a different server ID:

[mysqld]

server-id=2

log_bin=mysql-bin

binlog_format=ROW

gtid_mode=ON

enforce_gtid_consistency=ON

log_replica_updates=ON

The critical difference is:

Node 1 → server-id=1
Node 2 → server-id=2
15. Restart MySQL

On both nodes:

sudo systemctl restart mysql

Check:

sudo systemctl status mysql

If MySQL fails:

sudo journalctl -u mysql -n 100 --no-pager
16. Verify GTID

On both nodes:

mysql -u root -p

Run:

SELECT @@gtid_mode;

Expected:

ON

Verify:

SHOW VARIABLES LIKE 'gtid%';
17. Create Replication User

On Node 1:

CREATE USER 'repl_user'@'10.0.%'
IDENTIFIED BY 'STRONG_REPLICATION_PASSWORD';

Grant replication permissions according to the installed MySQL version:

GRANT REPLICATION SLAVE, REPLICATION CLIENT
ON *.*
TO 'repl_user'@'10.0.%';

Apply:

FLUSH PRIVILEGES;

Use a strong password. Never commit it to GitHub.

18. Check Replication User
SELECT user, host
FROM mysql.user
WHERE user='repl_user';
19. Prepare Test Database

On Node 1:

CREATE DATABASE ha_test;

Then:

USE ha_test;

Create table:

CREATE TABLE test_data (
    id INT AUTO_INCREMENT PRIMARY KEY,
    message VARCHAR(255)
);

Insert test data:

INSERT INTO test_data (message)
VALUES ('Initial replication test');

Verify:

SELECT * FROM test_data;
20. Configure Node 2 as Replica

On Node 2:

CHANGE REPLICATION SOURCE TO
    SOURCE_HOST='NODE_1_PRIVATE_IP',
    SOURCE_PORT=3306,
    SOURCE_USER='repl_user',
    SOURCE_PASSWORD='STRONG_REPLICATION_PASSWORD',
    SOURCE_AUTO_POSITION=1;

Start:

START REPLICA;
21. Verify Replica

Run:

SHOW REPLICA STATUS\G

Important fields:

Replica_IO_Running
Replica_SQL_Running
Seconds_Behind_Source
Auto_Position

Healthy state:

Replica_IO_Running: Yes
Replica_SQL_Running: Yes
Seconds_Behind_Source: 0
Auto_Position: 1
22. Verify Replicated Data

On Node 2:

USE ha_test;

SELECT * FROM test_data;

Expected:

Initial replication test

This confirms replication.

23. Test Continuous Replication

On Node 1:

INSERT INTO ha_test.test_data(message)
VALUES ('GTID replication is working');

On Node 2:

SELECT * FROM ha_test.test_data;

The new row should appear automatically.

24. Check GTID Executed Set

On Node 1:

SHOW MASTER STATUS;

Depending on MySQL version/configuration, GTID state can also be checked with:

SELECT @@GLOBAL.gtid_executed;

On Node 2:

SELECT @@GLOBAL.gtid_executed;

The replica's executed GTID set should reflect transactions received from the source.

25. HA Automation

The project uses custom Bash scripts instead of Orchestrator.

Project structure:

mysql-ha/
│
├── scripts/
│   ├── ha-monitor.sh
│   ├── failover.sh
│   └── rejoin.sh
│
└── logs/

Create:

mkdir -p ~/mysql-ha/scripts
mkdir -p ~/mysql-ha/logs
26. HA Monitor

ha-monitor.sh is responsible for continuously checking the health of the database nodes.

Conceptually:

             HA Monitor
                  │
                  ▼
          Check Node 1
                  │
          ┌───────┴───────┐
          │               │
         UP              DOWN
          │               │
          ▼               ▼
       Continue       Trigger Failover
                          │
                          ▼
                     Node 2
                     PRIMARY

The script should check:

Server reachability
MySQL availability
Replication status
Node state
Failure conditions
Recovery conditions
27. Failover

Initial:

Node 1 → PRIMARY
Node 2 → REPLICA

When Node 1 fails:

Node 1 → DOWN
Node 2 → PRIMARY

The failover procedure should:

Detect failure
Confirm failure
Promote Node 2
Disable replica mode
Make Node 2 writable
Log the event
Continue service from Node 2
28. Important Failover Safety

Automatic failover must be designed carefully to avoid split-brain.

Never allow both nodes to independently become writable.

Before production use, implement:

Failure confirmation
Fencing where appropriate
Single active controller
Locking
Health thresholds
Clear promotion criteria

This project is primarily a learning/engineering implementation of HA automation.

29. Failover Test

First check:

Node 1 → PRIMARY
Node 2 → REPLICA

Insert:

INSERT INTO ha_test.test_data(message)
VALUES ('AUTOMATIC FAILOVER WORKED');

Verify Node 2:

SELECT * FROM ha_test.test_data;

Then simulate failure on Node 1:

sudo systemctl stop mysql

Check Node 1:

sudo systemctl status mysql

The HA monitoring system should detect the failure.

Expected:

Node 1 → DOWN
Node 2 → PRIMARY

Verify Node 2:

SELECT @@read_only;

and:

SELECT * FROM ha_test.test_data;
30. Recover Node 1

Start MySQL:

sudo systemctl start mysql

Check:

sudo systemctl status mysql

Logs:

sudo journalctl -u mysql -f

Node 1 must be synchronized before becoming an active replica.

Expected final state:

Node 1 → REPLICA
Node 2 → PRIMARY
31. Rejoin Process

Conceptually:

Node 1 FAILED
     │
     ▼
MySQL Recovered
     │
     ▼
Replication Reset/Reconfiguration
     │
     ▼
GTID Synchronization
     │
     ▼
Node 1 joins Node 2
     │
     ▼
Node 1 = REPLICA

Always verify:

SHOW REPLICA STATUS\G

before considering recovery complete.

32. systemd HA Service

If HA monitoring is managed using systemd, create:

sudo nano /etc/systemd/system/mysql-ha-monitor.service

Example:

[Unit]
Description=MySQL HA Monitoring Service
After=network-online.target mysql.service
Wants=network-online.target

[Service]
Type=simple
User=ubuntu
ExecStart=/home/ubuntu/mysql-ha/scripts/ha-monitor.sh
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target

Reload:

sudo systemctl daemon-reload

Enable:

sudo systemctl enable mysql-ha-monitor

Start:

sudo systemctl start mysql-ha-monitor

Check:

sudo systemctl status mysql-ha-monitor

Logs:

sudo journalctl -u mysql-ha-monitor -f

Adjust the User and script path to match the actual EC2 environment.

33. Prometheus Monitoring

Prometheus collects metrics from:

mysqld_exporter
node_exporter

Architecture:

MySQL
   │
   ▼
mysqld_exporter
   │
   ▼
Prometheus
   │
   ▼
Grafana

System:

Linux
   │
   ▼
node_exporter
   │
   ▼
Prometheus
   │
   ▼
Grafana
34. node_exporter

Install Node Exporter.

Verify:

sudo systemctl status prometheus-node-exporter

Metrics:

curl http://localhost:9100/metrics

Important metrics include:

CPU
Memory
Disk
Filesystem
Network
Load
35. mysqld_exporter

MySQL exporter exposes MySQL-specific metrics.

Typical endpoint:

http://MYSQL_NODE_IP:9104/metrics

Test:

curl http://localhost:9104/metrics

Look for:

mysql_up
36. Prometheus Configuration

Prometheus configuration:

/etc/prometheus/prometheus.yml

Example:

global:
  scrape_interval: 15s

scrape_configs:

  - job_name: "mysql"
    static_configs:
      - targets:
          - "MYSQL_NODE_1_PRIVATE_IP:9104"
          - "MYSQL_NODE_2_PRIVATE_IP:9104"

  - job_name: "node"
    static_configs:
      - targets:
          - "MYSQL_NODE_1_PRIVATE_IP:9100"
          - "MYSQL_NODE_2_PRIVATE_IP:9100"

Restart:

sudo systemctl restart prometheus

Check:

sudo systemctl status prometheus
37. Prometheus Targets

Open:

Prometheus
→ Status
→ Targets

Expected:

mysql-node1   UP
mysql-node2   UP
node-node1    UP
node-node2    UP
38. Important Prometheus Queries
MySQL Availability
mysql_up

Healthy:

1

Unavailable:

0
MySQL Connections
mysql_global_status_threads_connected
Running Threads
mysql_global_status_threads_running
Queries Per Second
rate(mysql_global_status_questions[5m])
MySQL Uptime
mysql_global_status_uptime
39. Grafana

Grafana is used for:

Visualization
Dashboards
Metrics analysis
Alerting

Start:

sudo systemctl status grafana-server

Open Grafana:

http://GRAFANA_IP:3000
40. Add Prometheus Datasource

Grafana:

Connections
    ↓
Data Sources
    ↓
Add Data Source
    ↓
Prometheus

Use the Prometheus server's private address:

http://PROMETHEUS_IP:9090

Click:

Save & Test
41. Grafana Dashboard

Create:

Dashboards
    ↓
New
    ↓
New Dashboard
    ↓
Add Visualization

Datasource:

Prometheus

First query:

mysql_up

Visualization:

Stat

Title:

MySQL Node Availability
42. Recommended Grafana Panels

Create panels for:

MySQL Node Availability
CPU Usage
Memory Usage
Disk Usage
MySQL Connections
Queries Per Second
Threads Connected
Threads Running
MySQL Uptime
Exporter Availability
43. Grafana Alerting

Example alert:

mysql_up == 0

Alert name:

MySQL Node Down

Labels:

service=mysql
severity=critical

Other useful alerts:

High CPU
High Memory
High Disk Usage
MySQL Down
Exporter Down
Replication Failure
High Replication Lag
44. Loki

Loki is used for log aggregation.

Architecture:

Server Logs
     │
     ▼
 Promtail
     │
     ▼
   Loki
     │
     ▼
  Grafana

Loki receives log streams from Promtail.

45. Promtail

Promtail runs on monitored servers.

Its job is:

Read logs
   ↓
Add labels
   ↓
Send to Loki

Useful logs:

/var/log/syslog
/var/log/auth.log
MySQL logs
HA script logs
service logs
46. Promtail Configuration

Typical location:

/etc/promtail/config.yml

Example structure:

server:
  http_listen_port: 9080

positions:
  filename: /tmp/positions.yaml

clients:
  - url: http://LOKI_IP:3100/loki/api/v1/push

scrape_configs:

  - job_name: system
    static_configs:
      - targets:
          - localhost
        labels:
          job: system
          host: mysql-node
          __path__: /var/log/*.log

Adjust paths and labels for the actual system.

47. Loki Verification

Check:

sudo systemctl status loki

Promtail:

sudo systemctl status promtail

Check Promtail logs:

sudo journalctl -u promtail -f
48. Grafana Loki Datasource

Grafana:

Connections
    ↓
Data Sources
    ↓
Add Data Source
    ↓
Loki

URL:

http://LOKI_IP:3100

Click:

Save & Test
49. Log Investigation

Grafana:

Explore
    ↓
Loki

Useful searches:

error
mysql
replication
failed
connection

This is particularly useful during failover troubleshooting.

50. Nagios

Nagios provides an additional monitoring layer.

Architecture:

Nagios Server
      │
      │ NRPE
      ▼
MySQL Node
      │
      ├── Load
      ├── Disk
      ├── SSH
      ├── PING
      └── MySQL
51. NRPE

On monitored server:

sudo systemctl status nagios-nrpe-server

Check port:

sudo ss -lntp | grep 5666

From Nagios server:

nc -zv MYSQL_NODE_PRIVATE_IP 5666

Expected:

succeeded
52. NRPE Checks

Typical checks:

check_load
check_disk
check_users
check_procs

Custom MySQL checks can also be added.

53. Nagios Host Configuration

Example:

/usr/local/nagios/etc/objects/client.cfg

Example host:

define host {
    use                     linux-server
    host_name               mysql-node1
    alias                   MySQL Node 1
    address                 MYSQL_NODE_1_PRIVATE_IP
}
54. Nagios Services

Example:

define service {
    use                     generic-service
    host_name               mysql-node1
    service_description     PING
    check_command           check_ping!100.0,20%!500.0,60%
}

NRPE load check:

define service {
    use                     generic-service
    host_name               mysql-node1
    service_description     Current Load
    check_command           check_nrpe!check_load
}

Disk:

define service {
    use                     generic-service
    host_name               mysql-node1
    service_description     Disk Usage
    check_command           check_nrpe!check_disk
}

SSH:

define service {
    use                     generic-service
    host_name               mysql-node1
    service_description     SSH
    check_command           check_ssh
}
55. Nagios Configuration Validation

Always validate before restarting:

/usr/local/nagios/bin/nagios \
-v /usr/local/nagios/etc/nagios.cfg

The configuration must not contain critical errors.

Then:

sudo systemctl restart nagios

Check:

sudo systemctl status nagios
56. Nagios Monitoring

Nagios dashboard should show:

mysql-node1
    PING             OK
    Current Load     OK
    Disk Usage       OK
    SSH              OK

mysql-node2
    PING             OK
    Current Load     OK
    Disk Usage       OK
    SSH              OK
57. Email Notifications

Nagios can send notifications for:

HOST DOWN
SERVICE CRITICAL
SERVICE WARNING
RECOVERY

Check mail utility:

which mail

Test:

echo "Nagios email test" | mail -s "Nagios Test" YOUR_EMAIL

If mail is missing, install the appropriate mail package.

58. Monitoring Failure Test

Monitoring should be tested, not just configured.

Stop MySQL:

sudo systemctl stop mysql

Prometheus:

mysql_up

Expected:

0

Nagios should detect the service failure.

Loki/Promtail can be used to inspect related system/MySQL logs.

Grafana alerting should generate the configured alert.

59. Complete Failover Test
Before
Node 1 → PRIMARY
Node 2 → REPLICA

Replication:
IO  = Yes
SQL = Yes
Lag = 0
Insert Data
INSERT INTO ha_test.test_data(message)
VALUES ('FAILOVER TEST');
Verify Replica
SELECT * FROM ha_test.test_data;
Stop Primary
sudo systemctl stop mysql
Expected
Node 1 → DOWN
Node 2 → PRIMARY
Verify Node 2
SELECT * FROM ha_test.test_data;

Verify it is writable according to your promotion procedure:

SELECT @@read_only;
60. Monitoring During Failover

While failure is occurring, check:

Prometheus
mysql_up
Grafana

Check:

MySQL Node Availability
Nagios

Check:

Host status
Service status
Loki

Search:

mysql
fail
error
replication
HA Script
journalctl -u mysql-ha-monitor -f
61. Recovery Test

Start failed MySQL:

sudo systemctl start mysql

Check:

sudo systemctl status mysql

Check logs:

sudo journalctl -u mysql -f

Then configure/rejoin Node 1 as replica of the current primary.

Verify:

SHOW REPLICA STATUS\G

Expected:

Replica_IO_Running: Yes
Replica_SQL_Running: Yes
62. Troubleshooting
MySQL Not Running
sudo systemctl status mysql
sudo journalctl -u mysql -n 100 --no-pager
Port 3306 Timeout

Check:

sudo ss -lntp | grep 3306

From Bastion:

nc -zv NODE_IP 3306

If timeout:

Check:

Security Group
Network ACL
Ubuntu firewall
mysqld bind address
Private IP
Routing
63. Replication IO Connecting

If:

Replica_IO_Running: Connecting

Check:

SHOW REPLICA STATUS\G

Look at:

Last_IO_Error

Then verify network:

nc -zv SOURCE_IP 3306

Check replication user:

SELECT user, host
FROM mysql.user
WHERE user='repl_user';
64. Replica SQL Error

Check:

SHOW REPLICA STATUS\G

Look at:

Last_SQL_Error

Also inspect:

sudo journalctl -u mysql -n 100
65. MySQL Configuration Error

After modifying:

/etc/mysql/mysql.conf.d/mysqld.cnf

restart:

sudo systemctl restart mysql

If it fails:

sudo journalctl -u mysql -xe

Check for:

Duplicate parameters
Invalid parameter names
Invalid values
Configuration syntax errors
66. Prometheus Target Down

Check exporter:

curl http://NODE_IP:9100/metrics

or:

curl http://NODE_IP:9104/metrics

Check service:

sudo systemctl status prometheus-node-exporter

and:

sudo systemctl status mysqld-exporter

Then check Prometheus:

Status
→ Targets
67. Grafana No Data

Check:

Grafana
→ Connections
→ Data Sources
→ Prometheus
→ Save & Test

Then test:

up

and:

mysql_up
68. Promtail Not Sending Logs

Check:

sudo systemctl status promtail

Logs:

sudo journalctl -u promtail -n 100

Verify Loki:

curl http://LOKI_IP:3100/ready
69. Nagios NRPE Timeout

From Nagios server:

nc -zv NODE_IP 5666

On client:

sudo systemctl status nagios-nrpe-server

Check:

sudo ss -lntp | grep 5666

Also verify AWS Security Group.

70. Important Security Rules

Never commit:

*.pem
*.key
.env
passwords
AWS credentials
Slack webhooks
Grafana passwords
MySQL passwords
Nagios secrets

Example .gitignore:

*.pem
*.key
.env
.env.*
secrets/
credentials/
*.log
71. Git Repository Structure

Recommended:

aws-mysql-ha-monitoring/
│
├── README.md
│
├── mysql/
│   ├── node1/
│   │   └── mysqld.cnf.example
│   │
│   └── node2/
│       └── mysqld.cnf.example
│
├── scripts/
│   ├── ha-monitor.sh
│   ├── failover.sh
│   └── rejoin.sh
│
├── systemd/
│   └── mysql-ha-monitor.service
│
├── prometheus/
│   └── prometheus.yml
│
├── grafana/
│   ├── dashboards/
│   └── alerts/
│
├── loki/
│   └── loki-config.yml
│
├── promtail/
│   └── promtail-config.yml
│
├── nagios/
│   ├── hosts/
│   ├── services/
│   └── commands/
│
├── docs/
│   ├── architecture.md
│   ├── failover.md
│   └── troubleshooting.md
│
└── .gitignore
72. Do Not Commit Real Configuration Secrets

Instead of:

SOURCE_PASSWORD=MyRealPassword

use:

SOURCE_PASSWORD=<CHANGE_ME>

For example:

.env.example

can contain:

MYSQL_REPLICATION_USER=repl_user
MYSQL_REPLICATION_PASSWORD=CHANGE_ME
MYSQL_NODE1_PRIVATE_IP=CHANGE_ME
MYSQL_NODE2_PRIVATE_IP=CHANGE_ME
73. Complete Recreation From Zero

If the entire AWS environment needs to be recreated, follow this order.

Phase 1 — AWS
1. Create VPC
2. Create subnets
3. Create route tables
4. Create Security Groups
5. Create Bastion EC2
6. Create MySQL Node 1
7. Create MySQL Node 2
Phase 2 — Bastion
1. Configure SSH
2. Copy/configure PEM access
3. Test Node 1 connection
4. Test Node 2 connection
Phase 3 — MySQL

On both nodes:

1. Install MySQL
2. Enable MySQL
3. Configure server-id
4. Enable binary logs
5. Enable ROW format
6. Enable GTID
7. Enable GTID consistency
8. Enable replica updates
9. Restart MySQL
10. Verify configuration
Phase 4 — Replication
1. Create replication user
2. Create test database
3. Configure Node 2
4. CHANGE REPLICATION SOURCE TO
5. START REPLICA
6. SHOW REPLICA STATUS
7. Verify GTID
8. Test data replication
Phase 5 — HA Automation
1. Create mysql-ha directory
2. Copy scripts
3. Configure node IPs
4. Configure SSH access
5. Test scripts manually
6. Configure systemd
7. Enable service
8. Test failure
9. Test failover
10. Test recovery
Phase 6 — Prometheus
1. Install Prometheus
2. Install node_exporter
3. Install mysqld_exporter
4. Configure prometheus.yml
5. Restart Prometheus
6. Check Targets
7. Verify mysql_up
Phase 7 — Grafana
1. Install Grafana
2. Add Prometheus datasource
3. Create dashboard
4. Add MySQL panels
5. Add system panels
6. Configure alerts
7. Test alert
Phase 8 — Loki/Promtail
1. Install Loki
2. Configure Loki
3. Install Promtail
4. Configure log paths
5. Configure Loki URL
6. Start services
7. Add Loki datasource
8. Test logs in Grafana
Phase 9 — Nagios
1. Install Nagios server
2. Install NRPE client
3. Configure NRPE
4. Create Nagios host
5. Create services
6. Validate configuration
7. Restart Nagios
8. Verify checks
9. Configure notifications
Phase 10 — Final Testing
1. Test MySQL replication
2. Test GTID
3. Test exporter
4. Test Prometheus
5. Test Grafana
6. Test Loki
7. Test Promtail
8. Test Nagios
9. Test NRPE
10. Stop primary
11. Verify failover
12. Recover primary
13. Rejoin replica
14. Verify synchronization
15. Verify monitoring
74. Final Verification Checklist
AWS
[✓] VPC
[✓] Subnets
[✓] Security Groups
[✓] Bastion
[✓] MySQL Node 1
[✓] MySQL Node 2

MySQL
[✓] MySQL installed
[✓] server-id configured
[✓] Binary logging enabled
[✓] ROW binlog format
[✓] GTID enabled
[✓] GTID consistency enabled
[✓] Replica updates enabled

Replication
[✓] Replication user
[✓] Source configured
[✓] Replica configured
[✓] GTID auto-positioning
[✓] IO thread running
[✓] SQL thread running
[✓] Replication lag checked
[✓] Data replication tested

HA
[✓] Health monitor
[✓] Failover script
[✓] Recovery/rejoin script
[✓] systemd service
[✓] Failover tested
[✓] Recovery tested

Prometheus
[✓] Prometheus
[✓] node_exporter
[✓] mysqld_exporter
[✓] Targets UP
[✓] mysql_up working

Grafana
[✓] Prometheus datasource
[✓] MySQL dashboard
[✓] System dashboard
[✓] Alerts
[✓] Alert testing

Logs
[✓] Loki
[✓] Promtail
[✓] Log collection
[✓] Grafana Loki datasource

Nagios
[✓] Nagios server
[✓] NRPE
[✓] PING
[✓] Load
[✓] Disk
[✓] SSH
[✓] MySQL
[✓] Notifications
75. Final Architecture Summary
                         AWS VPC
                            │
                            ▼
                     ┌─────────────┐
                     │   Bastion   │
                     │     EC2     │
                     └──────┬──────┘
                            │
             ┌──────────────┴──────────────┐
             │                             │
             ▼                             ▼
      ┌──────────────┐              ┌──────────────┐
      │ MySQL Node 1 │              │ MySQL Node 2 │
      │              │              │              │
      │   PRIMARY    │──── GTID ──▶│   REPLICA    │
      │              │              │              │
      └──────┬───────┘              └──────┬───────┘
             │                             │
             └─────────────┬───────────────┘
                           │
                    Exporters / Logs
                           │
          ┌────────────────┼─────────────────┐
          │                │                 │
          ▼                ▼                 ▼
     Prometheus         Promtail          Nagios
          │                │                 │
          ▼                ▼                 ▼
       Grafana            Loki              NRPE
          │
          ▼
      Dashboards
      & Alerts
76. Technologies
AWS
EC2
VPC
Security Groups
Linux
Ubuntu
MySQL 8
GTID Replication
Bash
systemd
Prometheus
Grafana
mysqld_exporter
node_exporter
Loki
Promtail
Nagios
NRPE
Git
GitHub
77. What This Project Demonstrates

This project demonstrates practical implementation of:

Database HA

MySQL
+
GTID Replication
+
Failover
+
Recovery

Observability

Metrics
+
Logs
+
Dashboards
+
Alerts

Infrastructure Monitoring

Nagios
+
NRPE
+
System Checks

Cloud Infrastructure

AWS
+
EC2
+
VPC
+
Private Networking
+
Bastion
Author

Ahmad Raza

