# E2B 系统性能分析报告

**生成时间**: 2026-02-01
**分析工具**: `/home/primihub/pcloud/infra/local-deploy/scripts/analyze-resources.sh`

---

## 执行摘要

✅ **系统状态**: 健康
✅ **资源使用**: 正常范围内
⚠️ **优化空间**: 存在改进机会

---

## 1. 系统资源概览

### 硬件配置

| 资源 | 配置 | 使用率 | 状态 |
|------|------|--------|------|
| **CPU** | 64 核 (Intel Xeon Platinum 8352Y @ 2.20GHz) | 低负载 | ✅ 正常 |
| **内存** | 251 GB | 26% (65 GB 已用) | ✅ 正常 |
| **磁盘** | 多块 (3.6T - 11T) | 55% 平均 | ✅ 正常 |
| **网络** | 1 Gbps | 低流量 | ✅ 正常 |

### 关键发现

1. **内存充足**: 183 GB 可用内存，足以支持大量并发 VM
2. **CPU 空闲**: 64 核心大部分空闲，可以处理更多负载
3. **磁盘空间**: 部分磁盘接近满载 (/dev/sdc1, /dev/sdd1 100%)
4. **无活跃 VM**: 当前没有运行的 Firecracker VM

---

## 2. 服务资源使用分析

### Docker 容器 (32 个运行中)

**高资源消耗容器**:

| 容器 | CPU | 内存 | 说明 |
|------|-----|------|------|
| local-dev-clickhouse-1 | 16.18% | 1.93 GB | 分析数据库 - 正常 |
| application0/1/2 | 0.56-0.93% | 9+ GB 各 | PrimiHub 应用 |
| gateway0/1/2 | 0.51-0.95% | 3-5 GB 各 | 网关服务 |
| nacos-server | 2.24% | 1.89 GB | 服务注册中心 |

**总计**: ~50 GB 内存用于 Docker 容器 (20% 系统内存)

### Nomad Jobs

| Job | 状态 | 分配 | 版本 |
|-----|------|------|------|
| **api** | running | 1 个实例 | v1 |
| **orchestrator** | running | 1 个实例 (system) | v8 |

**历史失败**: API job 有 4 次失败记录 (已恢复)

### 前端应用

| 应用 | 端口 | 进程数 | 状态 |
|------|------|--------|------|
| **Fragments** | 3001 | 3 个 Node.js 进程 | ✅ 运行中 |
| **Surf** | 3002 | 2 个 Node.js 进程 | ✅ 运行中 |

---

## 3. 网络分析

### 监听端口 (前15个)

```
Port    Service              Protocol
11211   Memcached           TCP
18081   Unknown             TCP
22      SSH                 TCP
3002    Surf (Next.js)      TCP
3100    Loki                TCP
3307    MySQL Proxy         TCP
5432    PostgreSQL          TCP
53000   Grafana             TCP
```

### 活跃连接

- **外部连接**: 10 个活跃 ESTABLISHED 连接
- **内部连接**: Docker 容器间通信正常
- **网络流量**: 低流量，无异常

---

## 4. 性能瓶颈识别

### 当前瓶颈

1. ❌ **无活跃 VM**: 系统空闲，未处理实际工作负载
2. ⚠️ **磁盘接近满载**: /dev/sdc1 和 /dev/sdd1 使用率 100%
3. ⚠️ **API 历史失败**: 4 次失败记录需要调查

### 潜在问题

1. **模板存储为空**: `/home/primihub/e2b-storage/e2b-template-storage/` 目录存在但无文件
2. **缓存未使用**: 所有缓存目录 (template-cache, chunk-cache) 仅 4KB
3. **日志累积**: 需要定期清理日志文件

---

## 5. 优化建议

### 立即执行 (高优先级)

#### 5.1 清理磁盘空间

```bash
# 检查大文件
find /mnt/sdc -type f -size +1G -exec ls -lh {} \; 2>/dev/null | head -20
find /mnt/sdd -type f -size +1G -exec ls -lh {} \; 2>/dev/null | head -20

# 清理旧日志
find /home/primihub/e2b-storage/nomad-local/alloc/*/alloc/logs/ -name "*.log.*" -mtime +7 -delete

# 清理 Docker 未使用资源
docker system prune -a --volumes -f
```

#### 5.2 配置 Nomad Job 资源限制

**API Job** (`infra/local-deploy/jobs/api.hcl`):

```hcl
resources {
  cpu    = 2000  # 2 CPU cores
  memory = 2048  # 2 GB RAM

  memory_max = 4096  # 允许突发到 4 GB
}
```

**Orchestrator Job** (`infra/local-deploy/jobs/orchestrator.hcl`):

```hcl
resources {
  cpu    = 4000  # 4 CPU cores (需要更多用于 VM 管理)
  memory = 4096  # 4 GB RAM

  memory_max = 8192  # 允许突发到 8 GB
}
```

#### 5.3 启用日志轮转

创建 `/etc/logrotate.d/e2b`:

```
/home/primihub/e2b-storage/nomad-local/alloc/*/alloc/logs/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 0644 primihub primihub
}
```

### 短期优化 (中优先级)

#### 5.4 配置 VM 资源池

限制最大并发 VM 数量以防止资源耗尽:

```bash
# 在 orchestrator 环境变量中设置
MAX_CONCURRENT_VMS=50
VM_CPU_LIMIT=2
VM_MEMORY_LIMIT=1024  # MB
```

#### 5.5 启用监控告警

配置 Prometheus 告警规则 (`monitoring/alert-rules.yml`):

```yaml
groups:
  - name: e2b_resource_alerts
    rules:
      - alert: HighMemoryUsage
        expr: (node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / node_memory_MemTotal_bytes > 0.85
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Memory usage above 85%"

      - alert: DiskSpaceLow
        expr: (node_filesystem_avail_bytes / node_filesystem_size_bytes) < 0.15
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Disk space below 15%"

      - alert: TooManyFirecrackerVMs
        expr: count(up{job="firecracker"}) > 100
        for: 1m
        labels:
          severity: warning
        annotations:
          summary: "More than 100 VMs running"
```

#### 5.6 优化 Docker 容器资源

为高内存容器设置限制:

```bash
# 限制 ClickHouse 内存
docker update --memory="4g" --memory-swap="4g" local-dev-clickhouse-1

# 限制 application 容器
docker update --memory="8g" --memory-swap="8g" application0
docker update --memory="8g" --memory-swap="8g" application1
docker update --memory="8g" --memory-swap="8g" application2
```

### 长期优化 (低优先级)

#### 5.7 实施自动扩缩容

- 配置 Nomad autoscaler
- 根据负载自动调整 API/Orchestrator 实例数
- 实现 VM 预热池以减少启动延迟

#### 5.8 优化网络性能

- 启用 jumbo frames (MTU 9000)
- 配置 TCP BBR 拥塞控制
- 优化 iptables 规则

#### 5.9 数据库优化

- PostgreSQL 连接池调优
- ClickHouse 分区策略优化
- Redis 持久化配置优化

---

## 6. 性能基准测试

### 6.1 VM 创建性能

**测试脚本**: `/home/primihub/pcloud/infra/local-deploy/scripts/benchmark-vm-creation.sh`

```bash
#!/bin/bash
# 测试创建 10 个 VM 的平均时间

ITERATIONS=10
TOTAL_TIME=0

for i in $(seq 1 $ITERATIONS); do
    START=$(date +%s.%N)

    RESPONSE=$(curl -s -X POST http://localhost:3000/sandboxes \
      -H "Content-Type: application/json" \
      -H "X-API-Key: e2b_53ae1fed82754c17ad8077fbc8bcdd90" \
      -d '{"templateID": "base", "timeout": 300}')

    SANDBOX_ID=$(echo $RESPONSE | jq -r '.sandboxID')

    END=$(date +%s.%N)
    DURATION=$(echo "$END - $START" | bc)
    TOTAL_TIME=$(echo "$TOTAL_TIME + $DURATION" | bc)

    echo "Iteration $i: ${DURATION}s (Sandbox: $SANDBOX_ID)"

    # 清理
    curl -s -X DELETE "http://localhost:3000/sandboxes/$SANDBOX_ID" \
      -H "X-API-Key: e2b_53ae1fed82754c17ad8077fbc8bcdd90"

    sleep 2
done

AVG_TIME=$(echo "scale=2; $TOTAL_TIME / $ITERATIONS" | bc)
echo ""
echo "Average VM creation time: ${AVG_TIME}s"
```

**目标性能**:
- 冷启动: < 5 秒
- 热启动 (有快照): < 2 秒

### 6.2 代码执行性能

**测试脚本**: `/home/primihub/pcloud/infra/local-deploy/scripts/benchmark-code-execution.sh`

```bash
#!/bin/bash
# 测试代码执行延迟

SANDBOX_ID="<创建的 sandbox ID>"

# 测试简单命令
START=$(date +%s.%N)
curl -s -X POST "http://localhost:3001/api/sandbox" \
  -H "Content-Type: application/json" \
  -d "{\"fragment\":{\"template\":\"code-interpreter-v1\",\"code\":\"print('Hello')\"}}"
END=$(date +%s.%N)
DURATION=$(echo "$END - $START" | bc)

echo "Simple command execution: ${DURATION}s"
```

**目标性能**:
- 简单命令: < 500ms
- 复杂计算: < 5s

---

## 7. 监控仪表板

### Grafana 仪表板

访问: `http://localhost:53000`

**推荐仪表板**:

1. **系统概览**
   - CPU/内存/磁盘使用率
   - 网络流量
   - 活跃 VM 数量

2. **E2B 服务**
   - API 请求率和延迟
   - Orchestrator VM 创建/销毁速率
   - 错误率和失败次数

3. **资源分配**
   - 每个 VM 的资源使用
   - Nomad job 资源使用
   - Docker 容器资源使用

### Prometheus 查询示例

```promql
# API 请求率
rate(http_requests_total{job="api"}[5m])

# VM 创建延迟 (P95)
histogram_quantile(0.95, rate(vm_creation_duration_seconds_bucket[5m]))

# 内存使用率
(node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / node_memory_MemTotal_bytes * 100

# 活跃 VM 数量
count(up{job="firecracker"})
```

---

## 8. 故障排查清单

### 性能下降时检查

- [ ] 检查内存使用率: `free -h`
- [ ] 检查 CPU 负载: `top` 或 `htop`
- [ ] 检查磁盘 I/O: `iostat -x 1`
- [ ] 检查网络连接: `netstat -tunap | grep ESTABLISHED | wc -l`
- [ ] 检查 Firecracker VM 数量: `ps aux | grep firecracker | wc -l`
- [ ] 检查 Nomad job 状态: `nomad job status`
- [ ] 检查 Docker 容器状态: `docker stats`
- [ ] 查看 API 日志: `nomad alloc logs <api-alloc-id>`
- [ ] 查看 Orchestrator 日志: `nomad alloc logs <orch-alloc-id>`

### 常见问题解决

**问题**: VM 创建失败
**检查**:
- 模板文件是否存在
- 内存是否充足
- NBD 模块是否加载

**问题**: API 响应慢
**检查**:
- 数据库连接池是否耗尽
- Redis 是否响应
- 网络延迟

**问题**: 磁盘空间不足
**解决**:
- 清理旧日志
- 清理模板缓存
- 清理 Docker 未使用资源

---

## 9. 下一步行动

### 立即执行

1. ✅ 运行资源分析脚本 (已完成)
2. 🔲 清理磁盘空间 (100% 使用率的磁盘)
3. 🔲 配置 Nomad job 资源限制
4. 🔲 启用日志轮转

### 本周内完成

1. 🔲 创建性能基准测试脚本
2. 🔲 配置 Prometheus 告警规则
3. 🔲 优化 Docker 容器资源限制
4. 🔲 创建 Grafana 监控仪表板

### 本月内完成

1. 🔲 实施自动扩缩容
2. 🔲 优化网络性能
3. 🔲 数据库性能调优
4. 🔲 建立性能基线和 SLA

---

## 10. 附录

### 相关文档

- **资源分析脚本**: `/home/primihub/pcloud/infra/local-deploy/scripts/analyze-resources.sh`
- **系统检查脚本**: `/home/primihub/pcloud/infra/local-deploy/scripts/check-system-status.sh`
- **依赖检查脚本**: `/home/primihub/pcloud/infra/local-deploy/scripts/check-dependencies.sh`
- **CLAUDE.md**: 完整的故障排查指南

### 联系信息

如有问题或需要支持，请参考:
- GitHub Issues: https://github.com/anthropics/claude-code/issues
- E2B 文档: `/home/primihub/pcloud/infra/local-deploy/README.md`

---

**报告生成**: 2026-02-01
**下次审查**: 2026-02-08 (每周)
