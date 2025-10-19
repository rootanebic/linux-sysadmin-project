# Step 4: Monitoring (Prometheus + Grafana)

I’m setting up **Prometheus**, **node\_exporter**, **nginx-prometheus-exporter**, and **Grafana** on Ubuntu — **no Alertmanager** 

---

## 0. What I’m building

- Host metrics (CPU, RAM, disk, network) with **node\_exporter**
- NGINX metrics via **nginx-prometheus-exporter** (`stub_status`)
- **Prometheus** to scrape/store; alerts visible in the UI (no notifications)
- **Grafana** with a pre-provisioned Prometheus data source + ready dashboards



---

## 1. Create Service Users & Folders

```bash
sudo useradd --no-create-home --shell /usr/sbin/nologin prometheus
sudo useradd --no-create-home --shell /usr/sbin/nologin node_exporter
sudo useradd --no-create-home --shell /usr/sbin/nologin nginx_exporter

sudo mkdir -p /etc/prometheus /etc/prometheus/rules /var/lib/prometheus
sudo chown -R prometheus:prometheus /etc/prometheus /var/lib/prometheus
```

`screenshots/monitoring-users.png`

---

## 2. Install Prometheus

```bash
cd /tmp
wget https://github.com/prometheus/prometheus/releases/download/v3.7.1/prometheus-3.7.1.linux-amd64.tar.gz

tar xzf prometheus-3.7.1.linux-amd64.tar.gz
cd prometheus-3.7.1.linux-amd64

# Install binaries
sudo mv prometheus promtool /usr/local/bin/

sudo mkdir -p /var/lib/prometheus /etc/prometheus
sudo chown -R prometheus:prometheus /var/lib/prometheus /etc/prometheus


# Create Prometheus config
sudo nano /etc/prometheus/prometheus.yml
```

### 2.1 Prometheus configuration

Create `/etc/prometheus/prometheus.yml`:

```yaml
global:
  scrape_interval: 15s
  evaluation_interval: 15s
  external_labels:
    env: "prod"

# No Alertmanager (UI-only alerts)
rule_files:
  - "/etc/prometheus/rules/*.yml"

scrape_configs:
  - job_name: "prometheus"
    static_configs:
      - targets: ["localhost:9090"]

  - job_name: "node_exporter"
    static_configs:
      - targets: ["localhost:9100"]

  - job_name: "nginx_exporter"
    static_configs:
      - targets: ["localhost:9113"]
```

### 2.2 Prometheus systemd unit

Create `/etc/systemd/system/prometheus.service`:

```ini
[Unit]
Description=Prometheus
Wants=network-online.target
After=network-online.target

[Service]
User=prometheus
Group=prometheus
Type=simple
ExecStart=/usr/local/bin/prometheus \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/var/lib/prometheus/ \
  --web.console.templates=/etc/prometheus/consoles \
  --web.console.libraries=/etc/prometheus/console_libraries \
  --web.listen-address=0.0.0.0:9090

Restart=on-failure
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target

```

`screenshots/prometheus-status.png`

---

## 3. Install node\_exporter

```bash
cd /tmp

wget https://github.com/prometheus/node_exporter/releases/download/v1.9.1/node_exporter-1.9.1.linux-amd64.tar.gz
tar xzf node_exporter-1.9.1.linux-amd64.tar.gz
cd node_exporter-1.9.1.linux-amd64

sudo mv node_exporter /usr/local/bin/
sudo chown node_exporter:node_exporter /usr/local/bin/node_exporter
```

Create `/etc/systemd/system/node_exporter.service`:

```ini
[Unit]
Description=Node Exporter
After=network-online.target

[Service]
User=node_exporter
ExecStart=/usr/local/bin/node_exporter
Restart=on-failure
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
```

!(screenshots/node-exporter-status.png)

---

## 4. Enable NGINX `stub_status` (for OSS metrics)

Create `/etc/nginx/conf.d/stub_status.conf`:

```nginx
server {
  listen 127.0.0.1:8080;
  server_name 127.0.0.1;

  location /stub_status {
    stub_status;
    allow 127.0.0.1;
    deny all;
  }
}
```

Apply and reload:

```bash
sudo nginx -t && sudo systemctl reload nginx
```

Verify:

```bash
curl http://127.0.0.1:8080/stub_status
```

`screenshots/nginx-stub-status.png`

---

## 5. Install nginx-prometheus-exporter

> The NGINX Prometheus exporter is provided by **nginxinc**.

```bash
cd /tmp
wget -q https://github.com/nginx/nginx-prometheus-exporter/releases/download/v1.5.1/nginx-prometheus-exporter_1.5.1_linux_amd64.tar.gz

tar xzf nginx-prometheus-exporter_1.5.1_linux_amd64.tar.gz
sudo mv nginx-prometheus-exporter /usr/local/bin/
sudo chown nginx_exporter:nginx_exporter /usr/local/bin/nginx-prometheus-exporter
```

Create `/etc/systemd/system/nginx-prometheus-exporter.service`:

```ini
[Unit]
Description=NGINX Prometheus Exporter
After=network-online.target nginx.service
Wants=nginx.service

[Service]
User=nginx_exporter
ExecStart=/usr/local/bin/nginx-prometheus-exporter \
  --web.listen-address=:9113 \
  --nginx.scrape-uri=http://127.0.0.1:8080/stub_status
Restart=on-failure
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
```

`screenshots/nginx-exporter-status.png`

---

## 6. (Optional) Prometheus Alert Rules (UI-only)

sudo mkdir /etc/prometheus/rules

Create `/etc/prometheus/rules/system.yml`:

```yaml
groups:
- name: host-health
  rules:
  - alert: InstanceDown
    expr: up == 0
    for: 5m
    labels: { severity: critical }
    annotations:
      summary: "Instance {{ $labels.instance }} down"
      description: "Target unreachable for 5 minutes."

  - alert: HostHighCPU
    expr: (1 - avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m]))) * 100 > 85
    for: 10m
    labels: { severity: warning }
    annotations:
      summary: "High CPU on {{ $labels.instance }}"
      description: "CPU > 85% for 10 minutes."

  - alert: HostLowMemory
    expr: (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100 < 10
    for: 10m
    labels: { severity: warning }
    annotations:
      summary: "Low memory on {{ $labels.instance }}"
      description: "Available RAM < 10%."

  - alert: HostDiskSpaceLow
    expr: 100 * (node_filesystem_avail_bytes{fstype!~"tmpfs|overlay|squashfs"} / node_filesystem_size_bytes{fstype!~"tmpfs|overlay|squashfs"}) < 10
    for: 10m
    labels: { severity: warning }
    annotations:
      summary: "Low disk on {{ $labels.instance }} ({{ $labels.mountpoint }})"
      description: "Free space < 10%."
```

Create `/etc/prometheus/rules/nginx.yml`:

```yaml
groups:
- name: nginx-health
  rules:
  - alert: NginxExporterDown
    expr: up{job="nginx_exporter"} == 0
    for: 2m
    labels: { severity: critical }
    annotations:
      summary: "NGINX exporter down on {{ $labels.instance }}"

  - alert: NginxScrapeFailing
    expr: nginx_up == 0
    for: 2m
    labels: { severity: critical }
    annotations:
      summary: "NGINX scrape failing on {{ $labels.instance }}"

  - alert: NginxHighActiveConnections
    expr: nginx_connections_active > 500
    for: 5m
    labels: { severity: warning }
    annotations:
      summary: "High active connections on {{ $labels.instance }}"

  - alert: NginxHighRPS
    expr: rate(nginx_http_requests_total[5m]) > 2000
    for: 5m
    labels: { severity: warning }
    annotations:
      summary: "High requests/sec on {{ $labels.instance }}"
```

---

## 7. Enable & Start Services

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now node_exporter nginx-prometheus-exporter prometheus
```

Verify in Prometheus:

- Targets: `http://localhost:9090/targets`
- Alerts:  `http://localhost:9090/alerts`
- Graph:   `http://localhost:9090/graph` (try `up`)

`screenshots/prometheus-targets.png`

### 7.1 Open required ports with UFW



```bash
# Prometheus (9090), Node Exporter (9100), NGINX Exporter (9113), Grafana (3000)
sudo ufw allow 9090/tcp
sudo ufw allow 9100/tcp
sudo ufw allow 9113/tcp
sudo ufw allow 3000/tcp

sudo ufw status
```

`screenshots/ufw-rules.png`

---

## 8. Install Grafana + Provision Prometheus

```bash
# Repo & install
sudo mkdir -p /etc/apt/keyrings/
wget -q -O - https://apt.grafana.com/gpg.key | gpg --dearmor | sudo tee /etc/apt/keyrings/grafana.gpg > /dev/null
echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" | \
  sudo tee /etc/apt/sources.list.d/grafana.list

sudo apt update
sudo apt install -y grafana
sudo systemctl enable --now grafana-server
```

Create `/etc/grafana/provisioning/datasources/prometheus.yml`:

```yaml
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://localhost:9090
    isDefault: true
    editable: false
```

```bash
sudo systemctl restart grafana-server
```

- Log in at `http://localhost:3000/` (default `admin` / `admin`)
- Import dashboards: **Node Exporter Full (ID 1860)** and **NGINX by nginxinc (ID 11199)**

**Screenshot Placeholders:**

- `screenshots/grafana-login.png`
- `screenshots/grafana-node-exporter-1860.png`
- `screenshots/grafana-nginx.png`

---

---

## ✅ Summary

- Prometheus **v3.7.1** installed via `wget`, configured at `/etc/prometheus/prometheus.yml`, running on `:9090`.
- **node\_exporter** on `:9100` and **nginx-prometheus-exporter v1.5.1** on `:9113` (scraping NGINX `stub_status` on `127.0.0.1:8080`).
- **Grafana** running on `:3000` with a Prometheus datasource provisioned.
- If I expose services remotely, I allow them with UFW: `9090/tcp` (Prometheus), `9100/tcp` (node\_exporter), `9113/tcp` (NGINX exporter), `3000/tcp` (Grafana).

Quick access:

- Prometheus Targets → `http://<host>:9090/targets`
- Prometheus Alerts  → `http://<host>:9090/alerts`
- Grafana            → `http://<host>:3000/`



