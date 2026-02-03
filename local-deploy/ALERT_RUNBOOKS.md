# E2B Infrastructure Alert Runbooks

## 目录
- [API服务告警](#api服务告警)
- [Orchestrator服务告警](#orchestrator服务告警)
- [Sandbox告警](#sandbox告警)
- [系统告警](#系统告警)
- [通用故障排查步骤](#通用故障排查步骤)

---

## API服务告警

### APIHighCPU - API服务CPU使用率过高

**触发条件**: CPU使用率超过80%持续5分钟

**严重程度**: Warning

**可能原因**:
1. 请求量突增
2. 某个API端点存在性能问题
3. 数据库查询慢
4. 内存泄漏导致GC频繁

**排查步骤**:
```bash
# 1. 检查API服务状态
curl http://localhost:3000/health

# 2. 查看API日志
nomad alloc logs $(nomad job allocs api | grep running | awk '{print $1}') api 2>&1 | tail -100

# 3. 检查CPU使用情况
top -p $(pgrep -f "api.*--port")

# 4. 检查请求量
curl http://localhost:3000/metrics | grep http_requests_total

# 5. 检查慢查询
# 连接PostgreSQL查看慢查询日志
PGPASSWORD=postgres psql -h localhost -U postgres -d postgres -c "SELECT query, calls, mean_exec_time FROM pg_stat_statements ORDER BY mean_exec_time DESC LIMIT 10;"
```

**解决方案**:
- 如果是请求量突增：考虑水平扩展或限流
- 如果是慢查询：优化数据库查询，添加索引
- 如果是内存泄漏：重启服务并调查内存泄漏原因

**升级条件**: CPU持续>90%超过10分钟

---

### APIHighMemory - API服务内存使用率过高

**触发条件**: 内存使用超过3.4GB (85% of 4GB)持续5分钟

**严重程度**: Warning

**可能原因**:
1. 内存泄漏
2. 缓存过大
3. 并发请求过多
4. 大对象未释放

**排查步骤**:
```bash
# 1. 检查内存使用
ps aux | grep api | grep -v grep

# 2. 查看Go内存统计
curl http://localhost:3000/debug/pprof/heap > /tmp/heap.prof
go tool pprof -top /tmp/heap.prof

# 3. 检查活跃连接数
netstat -an | grep :3000 | grep ESTABLISHED | wc -l

# 4. 查看最近的错误日志
nomad alloc logs $(nomad job allocs api | grep running | awk '{print $1}') api 2>&1 | grep -i "error\|panic" | tail -50
```

**解决方案**:
- 立即重启服务释放内存：`nomad job restart api`
- 调查内存泄漏：分析heap profile
- 调整内存限制：修改Nomad job配置中的memory参数

**升级条件**: 内存使用>95%或服务OOM

---

### APIHighErrorRate - API错误率过高

**触发条件**: 5xx错误率超过5%持续3分钟

**严重程度**: Critical

**可能原因**:
1. 数据库连接失败
2. Orchestrator服务不可用
3. 代码bug导致panic
4. 资源耗尽

**排查步骤**:
```bash
# 1. 检查最近的错误
nomad alloc logs $(nomad job allocs api | grep running | awk '{print $1}') api 2>&1 | grep "ERROR\|PANIC" | tail -50

# 2. 检查数据库连接
PGPASSWORD=postgres psql -h localhost -U postgres -d postgres -c "SELECT count(*) FROM pg_stat_activity;"

# 3. 检查Orchestrator健康状态
curl http://localhost:5008/health

# 4. 查看错误分布
curl http://localhost:3000/metrics | grep http_requests_total | grep "status=\"5"

# 5. 检查最近创建的sandbox
curl -s http://localhost:3000/sandboxes -H "X-API-Key: e2b_53ae1fed82754c17ad8077fbc8bcdd90" | python3 -m json.tool
```

**解决方案**:
- 如果数据库连接失败：检查PostgreSQL服务状态
- 如果Orchestrator不可用：重启Orchestrator服务
- 如果是代码bug：查看panic堆栈，修复代码
- 紧急情况：回滚到上一个稳定版本

**升级条件**: 错误率>20%或持续超过10分钟

---

### APISlowResponse - API响应时间过长

**触发条件**: P95响应时间超过2秒持续5分钟

**严重程度**: Warning

**可能原因**:
1. 数据库查询慢
2. Orchestrator响应慢
3. 网络延迟
4. 资源竞争

**排查步骤**:
```bash
# 1. 检查响应时间分布
curl http://localhost:3000/metrics | grep http_request_duration_seconds

# 2. 识别慢端点
nomad alloc logs $(nomad job allocs api | grep running | awk '{print $1}') api 2>&1 | grep "duration" | sort -k5 -n | tail -20

# 3. 检查数据库性能
PGPASSWORD=postgres psql -h localhost -U postgres -d postgres -c "SELECT query, mean_exec_time, calls FROM pg_stat_statements WHERE mean_exec_time > 100 ORDER BY mean_exec_time DESC LIMIT 10;"

# 4. 检查Orchestrator响应时间
time curl http://localhost:5008/health
```

**解决方案**:
- 优化慢查询：添加索引或重写查询
- 增加数据库连接池大小
- 优化Orchestrator性能
- 考虑添加缓存层

**升级条件**: P95响应时间>5秒

---

### APIDown - API服务不可用

**触发条件**: 服务停止响应超过1分钟

**严重程度**: Critical

**可能原因**:
1. 服务崩溃
2. 端口被占用
3. 配置错误
4. 资源耗尽导致OOM

**排查步骤**:
```bash
# 1. 检查服务状态
nomad job status api

# 2. 检查进程是否存在
ps aux | grep api | grep -v grep

# 3. 检查端口占用
netstat -tlnp | grep :3000

# 4. 查看最近的日志
nomad alloc logs $(nomad job allocs api | grep -E "running|failed" | head -1 | awk '{print $1}') api 2>&1 | tail -100

# 5. 检查系统资源
free -h
df -h
```

**解决方案**:
1. **立即重启服务**:
   ```bash
   nomad job restart api
   ```

2. **如果重启失败，检查配置**:
   ```bash
   nomad job validate /home/primihub/pcloud/infra/local-deploy/jobs/api.hcl
   ```

3. **如果端口被占用**:
   ```bash
   # 找到占用进程
   lsof -i :3000
   # 杀死进程
   kill -9 <PID>
   # 重启服务
   nomad job run /home/primihub/pcloud/infra/local-deploy/jobs/api.hcl
   ```

**升级条件**: 服务无法恢复超过5分钟

---

## Orchestrator服务告警

### OrchestratorHighCPU - Orchestrator CPU使用率过高

**触发条件**: CPU使用率超过80%持续5分钟

**严重程度**: Warning

**可能原因**:
1. VM创建请求过多
2. Firecracker进程管理开销大
3. 网络命名空间操作频繁
4. 模板缓存操作密集

**排查步骤**:
```bash
# 1. 检查运行中的VM数量
ps aux | grep firecracker | grep -v grep | wc -l

# 2. 查看Orchestrator日志
nomad alloc logs $(nomad job allocs orchestrator | grep running | awk '{print $1}') 2>&1 | tail -100

# 3. 检查网络命名空间数量
sudo ip netns list | wc -l

# 4. 检查最近的VM创建请求
nomad alloc logs $(nomad job allocs orchestrator | grep running | awk '{print $1}') 2>&1 | grep "created sandbox" | tail -20
```

**解决方案**:
- 清理僵尸VM进程
- 清理未使用的网络命名空间
- 限制并发VM创建数量
- 考虑水平扩展Orchestrator

**升级条件**: CPU持续>90%超过10分钟

---

### OrchestratorHighMemory - Orchestrator内存使用率过高

**触发条件**: 内存使用超过3.4GB持续5分钟

**严重程度**: Warning

**可能原因**:
1. VM进程未正确清理
2. 模板缓存过大
3. 网络资源未释放
4. 内存泄漏

**排查步骤**:
```bash
# 1. 检查内存使用
ps aux | grep orchestrator | grep -v grep

# 2. 检查Firecracker进程数量
ps aux | grep firecracker | wc -l

# 3. 检查模板缓存大小
du -sh /home/primihub/e2b-storage/e2b-template-cache/

# 4. 检查网络命名空间
sudo ip netns list | wc -l
```

**解决方案**:
- 清理旧的VM进程
- 清理模板缓存
- 清理网络命名空间
- 重启Orchestrator服务

**升级条件**: 内存使用>95%或服务OOM

---

### OrchestratorDown - Orchestrator服务不可用

**触发条件**: 服务停止响应超过1分钟

**严重程度**: Critical

**可能原因**:
1. 服务崩溃
2. 权限问题（需要sudo）
3. NBD模块未加载
4. 资源耗尽

**排查步骤**:
```bash
# 1. 检查服务状态
nomad job status orchestrator

# 2. 检查NBD模块
lsmod | grep nbd

# 3. 查看日志
nomad alloc logs $(nomad job allocs orchestrator | grep -E "running|failed" | head -1 | awk '{print $1}') 2>&1 | tail -100

# 4. 检查权限
ls -la /home/primihub/pcloud/infra/packages/orchestrator/bin/orchestrator
```

**解决方案**:
1. **加载NBD模块**:
   ```bash
   sudo modprobe nbd max_part=8 nbds_max=64
   ```

2. **重启服务**:
   ```bash
   nomad job restart orchestrator
   ```

3. **如果权限问题，检查Nomad配置**:
   ```bash
   grep -A 5 "task \"orchestrator\"" /home/primihub/pcloud/infra/local-deploy/jobs/orchestrator.hcl
   ```

**升级条件**: 服务无法恢复超过5分钟

---

## Sandbox告警

### SandboxHighFailureRate - Sandbox创建失败率过高

**触发条件**: 创建失败率超过10%持续5分钟

**严重程度**: Warning

**可能原因**:
1. 模板文件损坏
2. 网络资源耗尽
3. 磁盘空间不足
4. Firecracker启动失败

**排查步骤**:
```bash
# 1. 查看最近的失败日志
nomad alloc logs $(nomad job allocs orchestrator | grep running | awk '{print $1}') 2>&1 | grep -i "error\|failed" | tail -50

# 2. 检查磁盘空间
df -h

# 3. 检查网络命名空间可用性
sudo ip netns list | wc -l

# 4. 检查模板文件
ls -lh /home/primihub/e2b-storage/e2b-template-storage/*/rootfs.ext4
```

**解决方案**:
- 清理磁盘空间
- 清理网络命名空间
- 验证模板文件完整性
- 重启Orchestrator服务

**升级条件**: 失败率>50%

---

### TooManySandboxes - 活跃Sandbox数量过多

**触发条件**: 活跃Sandbox数量超过100持续5分钟

**严重程度**: Warning

**可能原因**:
1. Sandbox未正确清理
2. 客户端未调用kill()
3. 超时机制失效

**排查步骤**:
```bash
# 1. 检查活跃Sandbox数量
curl -s http://localhost:3000/sandboxes -H "X-API-Key: e2b_53ae1fed82754c17ad8077fbc8bcdd90" | python3 -c "import sys, json; print(len(json.load(sys.stdin)))"

# 2. 检查Firecracker进程
ps aux | grep firecracker | wc -l

# 3. 查看Sandbox列表
curl -s http://localhost:3000/sandboxes -H "X-API-Key: e2b_53ae1fed82754c17ad8077fbc8bcdd90" | python3 -m json.tool | head -50
```

**解决方案**:
- 手动清理超时的Sandbox
- 检查超时配置
- 调查为什么Sandbox未自动清理

**升级条件**: Sandbox数量>200

---

## 系统告警

### DiskSpaceLow - 磁盘空间不足

**触发条件**: 根分区可用空间低于15%持续5分钟

**严重程度**: Warning

**可能原因**:
1. 日志文件过大
2. 模板缓存过多
3. Sandbox缓存未清理
4. Docker镜像过多

**排查步骤**:
```bash
# 1. 检查磁盘使用情况
df -h

# 2. 查找大文件
du -sh /* 2>/dev/null | sort -h | tail -10

# 3. 检查日志大小
du -sh /home/primihub/e2b-storage/nomad-local/alloc/*/alloc/logs/

# 4. 检查缓存大小
du -sh /home/primihub/e2b-storage/e2b-*-cache/
```

**解决方案**:
```bash
# 1. 清理旧日志
find /home/primihub/e2b-storage/nomad-local/alloc/*/alloc/logs/ -name "*.0" -mtime +7 -delete

# 2. 清理模板缓存
sudo rm -rf /home/primihub/e2b-storage/e2b-template-cache/*
sudo rm -rf /home/primihub/e2b-storage/e2b-chunk-cache/*

# 3. 清理Docker
docker system prune -a -f

# 4. 清理npm缓存
npm cache clean --force
```

**升级条件**: 可用空间<5%

---

### DiskSpaceCritical - 磁盘空间严重不足

**触发条件**: 根分区可用空间低于5%持续2分钟

**严重程度**: Critical

**排查步骤**: 同DiskSpaceLow

**解决方案**:
1. **立即清理空间**（按优先级）:
   ```bash
   # 1. 清理所有缓存（最安全）
   sudo rm -rf /home/primihub/e2b-storage/e2b-*-cache/*

   # 2. 清理旧日志
   find /home/primihub/e2b-storage/nomad-local/ -name "*.log.*" -delete

   # 3. 清理Docker
   docker system prune -a -f --volumes

   # 4. 清理临时文件
   sudo rm -rf /tmp/*
   ```

2. **停止非关键服务**:
   ```bash
   nomad job stop surf
   ```

3. **扩展磁盘空间**（如果可能）

**升级条件**: 可用空间<2%或服务开始失败

---

## 通用故障排查步骤

### 1. 快速健康检查
```bash
# 检查所有服务状态
curl http://localhost:3000/health  # API
curl http://localhost:5008/health  # Orchestrator
nomad job status                    # Nomad jobs
nomad node status                   # Nomad nodes

# 检查系统资源
free -h
df -h
top -bn1 | head -20
```

### 2. 日志收集
```bash
# API日志
nomad alloc logs $(nomad job allocs api | grep running | awk '{print $1}') api 2>&1 > /tmp/api.log

# Orchestrator日志
nomad alloc logs $(nomad job allocs orchestrator | grep running | awk '{print $1}') 2>&1 > /tmp/orchestrator.log

# 系统日志
journalctl -u nomad -n 100 > /tmp/nomad.log
```

### 3. 重启服务顺序
```bash
# 1. 重启API（影响最小）
nomad job restart api

# 2. 重启Orchestrator（会影响VM创建）
nomad job restart orchestrator

# 3. 重启Nomad（影响所有服务）
sudo systemctl restart nomad
```

### 4. 紧急回滚
```bash
# 1. 停止当前版本
nomad job stop api
nomad job stop orchestrator

# 2. 部署上一个版本
nomad job run /home/primihub/pcloud/infra/local-deploy/jobs/api.hcl.backup
nomad job run /home/primihub/pcloud/infra/local-deploy/jobs/orchestrator.hcl.backup
```

### 5. 联系人
- **On-call工程师**: oncall@example.com
- **团队Slack**: #e2b-alerts
- **紧急电话**: +86-xxx-xxxx-xxxx

---

## 告警配置文件位置

- **告警规则**: `/home/primihub/pcloud/infra/local-deploy/prometheus-alerts.yml`
- **Alertmanager配置**: `/home/primihub/pcloud/infra/local-deploy/alertmanager-config.yml`
- **Runbook**: `/home/primihub/pcloud/infra/local-deploy/ALERT_RUNBOOKS.md`

## 更新历史

- 2026-01-23: 初始版本创建
