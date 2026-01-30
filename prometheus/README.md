# Prometheus

Installs a simple prometheus container on the host machine, that can be used for federation puposes.

Collects metrics from containers on the `monitoring` network with `prometheus.io/scapre=true` label.

Expects the following services to be present:
- `node-exporter` on port `9100`
- `docker` exposed statistics on port `9104`
- `cadvisor` on port `9105`
