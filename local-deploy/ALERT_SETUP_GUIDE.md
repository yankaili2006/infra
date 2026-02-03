# E2B Infrastructure Alert System Setup Guide

## 概述

本文档描述如何为 E2B 基础设施配置告警系统。告警系统基于 Prometheus + Alertmanager 架构。

## 文件清单

已创建的配置文件：

1. **prometheus-alerts.yml** - Prometheus 告警规则定义
2. **alertmanager-config.yml** - Alertmanager 配置（告警路由和接收者）
3. **ALERT_RUNBOOKS.md** - 告警处理手册（Runbooks）

## 告警规则概览

### API 服务告警（5个）
- **APIHighCPU**: CPU使用率>80%持续5分钟
- **APIHighMemory**: 内存使用>3.4GB持续5分钟
- **APIHighErrorRate**: 5xx错误率>5%持续3分钟（Critical）
- **APISlowResponse**: P95响应时间>2秒持续5分钟
- **APIDown**: 服务不可用超过1分钟（Critical）

### Orchestrator 服务告警（3个）
- **OrchestratorHighCPU**: CPU使用率>80%持续5分钟
- **OrchestratorHighMemory**: 内存使用>3.4GB持续5分钟
- **OrchestratorDown**: 服务不可用超过1分钟（Critical）

### Sandbox 告警（2个）
- **SandboxHighFailureRate**: 创建失败率>10%持续5分钟
- **TooManySandboxes**: 活跃Sandbox数量>100持续5分钟

### 系统告警（2个）
- **DiskSpaceLow**: 磁盘可用空间<15%持续5分钟
- **DiskSpaceCritical**: 磁盘可用空间<5%持续2分钟（Critical）

**总计**: 12个告警规则

## 部署步骤

### 前提条件

1. **Prometheus 已安装并运行**
   - 如果未安装，参考：https://prometheus.io/docs/prometheus/latest/installation/

2. **Alertmanager 已安装并运行**
   - 如果未安装，参考：https://prometheus.io/docs/alerting/latest/alertmanager/

3. **服务已配置 OpenTelemetry metrics 导出**
   - API 和 Orchestrator 已配置（参考 CLAUDE.md）

### 步骤 1: 配置 Prometheus

编辑 Prometheus 配置文件（通常是 `/etc/prometheus/prometheus.yml`）：

```yaml
# 全局配置
global:
  scrape_interval: 15s
  evaluation_interval: 15s

# Alertmanager 配置
alerting:
  alertmanagers:
    - static_configs:
        - targets:
            - localhost:9093

# 加载告警规则
rule_files:
  - "/home/primihub/pcloud/infra/local-deploy/prometheus-alerts.yml"

# 抓取配置
scrape_configs:
  # API 服务
  - job_name: 'orchestration-api'
    static_configs:
      - targets: ['localhost:3000']
    metrics_path: '/metrics'

  # Orchestrator 服务
  - job_name: 'orchestrator'
    static_configs:
      - targets: ['localhost:5008']
    metrics_path: '/metrics'

  # Node Exporter（系统指标）
  - job_name: 'node'
    static_configs:
      - targets: ['localhost:9100']
```

### 步骤 2: 配置 Alertmanager

将 `alertmanager-config.yml` 复制到 Alertmanager 配置目录：

```bash
# 备份原配置
sudo cp /etc/alertmanager/alertmanager.yml /etc/alertmanager/alertmanager.yml.backup

# 复制新配置
sudo cp /home/primihub/pcloud/infra/local-deploy/alertmanager-config.yml /etc/alertmanager/alertmanager.yml

# 修改邮件配置
sudo vim /etc/alertmanager/alertmanager.yml
# 更新以下字段：
# - smtp_smarthost
# - smtp_from
# - smtp_auth_username
# - smtp_auth_password
# - email_configs.to
```

### 步骤 3: 验证配置

```bash
# 验证 Prometheus 配置
promtool check config /etc/prometheus/prometheus.yml

# 验证告警规则
promtool check rules /home/primihub/pcloud/infra/local-deploy/prometheus-alerts.yml

# 验证 Alertmanager 配置
amtool check-config /etc/alertmanager/alertmanager.yml
```

### 步骤 4: 重启服务

```bash
# 重启 Prometheus
sudo systemctl restart prometheus

# 重启 Alertmanager
sudo systemctl restart alertmanager

# 检查服务状态
sudo systemctl status prometheus
sudo systemctl status alertmanager
```

### 步骤 5: 验证告警系统

```bash
# 1. 检查 Prometheus 是否加载了告警规则
curl http://localhost:9090/api/v1/rules | python3 -m json.tool

# 2. 检查 Alertmanager 是否运行
curl http://localhost:9093/api/v1/status

# 3. 触发测试告警（可选）
# 临时停止 API 服务来触发 APIDown 告警
nomad job stop api
# 等待1分钟后检查告警
curl http://localhost:9093/api/v1/alerts
# 恢复服务
nomad job run /home/primihub/pcloud/infra/local-deploy/jobs/api.hcl
```

## 配置 Webhook 通知（可选）

### Slack 集成

1. 创建 Slack Incoming Webhook：
   - 访问：https://api.slack.com/messaging/webhooks
   - 创建新的 Webhook URL

2. 更新 `alertmanager-config.yml`：

```yaml
receivers:
  - name: 'critical-alerts'
    slack_configs:
      - api_url: 'https://hooks.slack.com/services/YOUR/WEBHOOK/URL'
        channel: '#e2b-alerts'
        title: 'E2B Critical Alert'
        text: |
          *Alert:* {{ .GroupLabels.alertname }}
          *Service:* {{ .GroupLabels.service }}
          *Severity:* {{ .GroupLabels.severity }}
          *Description:* {{ range .Alerts }}{{ .Annotations.description }}{{ end }}
```

### PagerDuty 集成

1. 获取 PagerDuty Integration Key

2. 更新 `alertmanager-config.yml`：

```yaml
receivers:
  - name: 'critical-alerts'
    pagerduty_configs:
      - service_key: 'YOUR_PAGERDUTY_SERVICE_KEY'
        description: '{{ .GroupLabels.alertname }}: {{ range .Alerts }}{{ .Annotations.description }}{{ end }}'
```

## 自定义告警规则

### 添加新的告警规则

编辑 `prometheus-alerts.yml`，添加新的规则：

```yaml
groups:
  - name: custom_alerts
    interval: 30s
    rules:
      - alert: CustomAlert
        expr: your_metric > threshold
        for: 5m
        labels:
          severity: warning
          service: your-service
        annotations:
          summary: "告警摘要"
          description: "详细描述: {{ $value }}"
```

### 修改告警阈值

根据实际情况调整阈值：

```yaml
# 例如：将 CPU 告警阈值从 80% 改为 90%
- alert: APIHighCPU
  expr: rate(process_cpu_seconds_total{job="orchestration-api"}[5m]) > 0.9  # 改为 0.9
  for: 5m
```

## 监控指标说明

### API 服务指标

- `process_cpu_seconds_total`: CPU 使用时间（秒）
- `process_resident_memory_bytes`: 内存使用（字节）
- `http_requests_total`: HTTP 请求总数
- `http_request_duration_seconds`: HTTP 请求延迟

### Orchestrator 服务指标

- `process_cpu_seconds_total`: CPU 使用时间
- `process_resident_memory_bytes`: 内存使用
- `sandbox_create_total`: Sandbox 创建总数
- `sandbox_create_errors_total`: Sandbox 创建失败数
- `sandbox_active_count`: 活跃 Sandbox 数量

### 系统指标（需要 Node Exporter）

- `node_filesystem_avail_bytes`: 文件系统可用空间
- `node_filesystem_size_bytes`: 文件系统总大小
- `node_cpu_seconds_total`: CPU 使用时间
- `node_memory_MemAvailable_bytes`: 可用内存

## 安装 Node Exporter（可选）

如果需要系统级别的告警（磁盘、CPU、内存），需要安装 Node Exporter：

```bash
# 下载 Node Exporter
wget https://github.com/prometheus/node_exporter/releases/download/v1.7.0/node_exporter-1.7.0.linux-amd64.tar.gz

# 解压
tar xvfz node_exporter-1.7.0.linux-amd64.tar.gz

# 移动到系统目录
sudo mv node_exporter-1.7.0.linux-amd64/node_exporter /usr/local/bin/

# 创建 systemd 服务
sudo tee /etc/systemd/system/node_exporter.service > /dev/null <<EOF
[Unit]
Description=Node Exporter
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/node_exporter
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# 启动服务
sudo systemctl daemon-reload
sudo systemctl start node_exporter
sudo systemctl enable node_exporter

# 验证
curl http://localhost:9100/metrics
```

## 故障排查

### Prometheus 无法加载告警规则

**症状**: 告警规则不生效

**解决方案**:
```bash
# 检查配置文件语法
promtool check rules /home/primihub/pcloud/infra/local-deploy/prometheus-alerts.yml

# 检查 Prometheus 日志
sudo journalctl -u prometheus -n 100

# 检查规则是否加载
curl http://localhost:9090/api/v1/rules
```

### Alertmanager 无法发送邮件

**症状**: 告警触发但未收到邮件

**解决方案**:
```bash
# 检查 Alertmanager 日志
sudo journalctl -u alertmanager -n 100

# 测试 SMTP 连接
telnet smtp.example.com 587

# 检查告警状态
curl http://localhost:9093/api/v1/alerts
```

### 告警未触发

**症状**: 条件满足但告警未触发

**解决方案**:
```bash
# 检查指标是否存在
curl http://localhost:9090/api/v1/query?query=process_cpu_seconds_total

# 检查告警规则评估
curl http://localhost:9090/api/v1/rules | grep -A 10 "APIHighCPU"

# 检查 Prometheus 与 Alertmanager 连接
curl http://localhost:9090/api/v1/alertmanagers
```

## 最佳实践

1. **定期审查告警规则**: 每月检查告警规则是否合理，调整阈值
2. **避免告警疲劳**: 确保告警有意义，减少误报
3. **文档化 Runbooks**: 为每个告警编写详细的处理步骤
4. **测试告警系统**: 定期触发测试告警验证系统工作正常
5. **监控告警系统本身**: 确保 Prometheus 和 Alertmanager 正常运行

## 下一步

1. **配置 Grafana 仪表板**: 可视化监控指标
2. **添加更多告警规则**: 根据业务需求添加自定义告警
3. **集成 On-call 系统**: 配置 PagerDuty 或类似系统
4. **建立告警响应流程**: 定义告警升级路径和响应时间

## 参考资料

- [Prometheus 文档](https://prometheus.io/docs/)
- [Alertmanager 文档](https://prometheus.io/docs/alerting/latest/alertmanager/)
- [PromQL 查询语言](https://prometheus.io/docs/prometheus/latest/querying/basics/)
- [告警规则最佳实践](https://prometheus.io/docs/practices/alerting/)

## 联系方式

如有问题，请联系：
- **技术支持**: support@example.com
- **On-call**: oncall@example.com
- **Slack**: #e2b-infrastructure
