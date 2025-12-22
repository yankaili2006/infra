# Grafana快速集成指南

## 📊 E2B与Grafana集成

本文档提供快速启动Grafana监控E2B虚拟机的步骤。

## ⚠️ 当前状态

**端口占用问题已解决**: client-proxy服务已停止，端口3001已释放。

## 🚀 快速启动方式

### 方式1: 使用备用端口 (推荐)

由于环境中可能存在Docker网络配置问题，建议使用备用端口:

```bash
# 1. 清理旧容器
docker rm -f $(docker ps -aq --filter "name=grafana") 2>/dev/null

# 2. 在端口3005启动Grafana
docker run -d \
  --name e2b-grafana \
  --restart unless-stopped \
  -p 3005:3000 \
  -v grafana-storage:/var/lib/grafana \
  -e "GF_SECURITY_ADMIN_PASSWORD=admin" \
  -e "GF_INSTALL_PLUGINS=" \
  grafana/grafana:latest

# 3. 等待启动
sleep 15

# 4. 验证状态
docker ps | grep grafana
curl http://localhost:3005/api/health
```

**访问地址**: http://localhost:3005
**用户名**: admin
**密码**: admin

### 方式2: 使用原端口3001

如果确认端口3001完全空闲:

```bash
# 1. 确认端口空闲
netstat -tlnp | grep :3001
# 应该没有输出

# 2. 停止可能存在的Nomad client-proxy服务
nomad job stop client-proxy

# 3. 强制终止进程 (如果仍在运行)
kill -9 $(lsof -ti:3001)

# 4. 启动Grafana
docker run -d \
  --name e2b-grafana \
  --restart unless-stopped \
  -p 3001:3000 \
  -v grafana-storage:/var/lib/grafana \
  -e "GF_SECURITY_ADMIN_PASSWORD=admin" \
  grafana/grafana:latest
```

## 📝 配置PostgreSQL数据源

Grafana启动后，配置数据源查看E2B VM数据:

### 步骤1: 登录Grafana

1. 访问 http://localhost:3005 (或3001)
2. 用户名: `admin`
3. 密码: `admin`
4. 首次登录会要求修改密码

### 步骤2: 添加PostgreSQL数据源

1. 点击左侧菜单 **☰** → **Connections** → **Data sources**
2. 点击 **Add data source**
3. 选择 **PostgreSQL**
4. 配置连接信息:

```yaml
Name: E2B-PostgreSQL
Host: postgres:5432
Database: postgres
User: postgres
Password: postgres
SSL Mode: disable
Version: 13+ (根据实际版本选择)
```

5. 点击 **Save & test** 验证连接

### 步骤3: 创建Dashboard

#### 基础VM监控面板

创建新Dashboard，添加以下Panel:

**Panel 1: VM总数统计**
```sql
SELECT
  COUNT(*) as "总VM数",
  SUM(CASE WHEN state = 'running' THEN 1 ELSE 0 END) as "运行中",
  SUM(CASE WHEN state = 'stopped' THEN 1 ELSE 0 END) as "已停止"
FROM sandboxes
WHERE started_at > NOW() - INTERVAL '24 hours';
```

**Panel 2: VM列表**
```sql
SELECT
  sandbox_id as "VM ID",
  state as "状态",
  cpu_count as "CPU核数",
  memory_mb as "内存(MB)",
  started_at as "启动时间",
  ended_at as "结束时间"
FROM sandboxes
ORDER BY started_at DESC
LIMIT 20;
```

**Panel 3: VM创建趋势 (时间序列)**
```sql
SELECT
  $__timeGroup(started_at, '1h') as time,
  COUNT(*) as "创建数量"
FROM sandboxes
WHERE $__timeFilter(started_at)
GROUP BY time
ORDER BY time;
```

**Panel 4: 资源使用统计**
```sql
SELECT
  template_id as "模板",
  COUNT(*) as "使用次数",
  AVG(cpu_count) as "平均CPU",
  AVG(memory_mb) as "平均内存(MB)"
FROM sandboxes
WHERE started_at > NOW() - INTERVAL '7 days'
GROUP BY template_id;
```

## 🎨 Dashboard配置建议

### 布局
- 第一行: 统计卡片 (总数、运行中、已停止)
- 第二行: 创建趋势图表 (时间序列)
- 第三行: VM列表表格
- 第四行: 资源使用统计

### 自动刷新
- 设置刷新间隔: 30秒或1分钟
- 时间范围: Last 24 hours

### 告警配置
可以为以下情况配置告警:
- VM创建失败率超过阈值
- 运行中的VM数量异常
- 资源使用率过高

## 🔗 与E2B CLI集成

使用e2b CLI工具配合Grafana:

```bash
# 创建VM
e2b create

# 在Grafana中立即看到新VM
# Dashboard会自动刷新显示

# 查看VM详情
e2b info <vm-id>

# 在Grafana中查看历史数据和趋势
```

## 📊 高级功能

### 1. 导入预制Dashboard

创建JSON配置文件保存Dashboard:

```bash
# 导出当前Dashboard
curl -u admin:admin http://localhost:3005/api/dashboards/uid/<dashboard-uid> > e2b-dashboard.json

# 导入到其他Grafana实例
curl -X POST -H "Content-Type: application/json" \
  -u admin:admin \
  http://localhost:3005/api/dashboards/db \
  -d @e2b-dashboard.json
```

### 2. 变量和过滤器

添加Dashboard变量实现动态过滤:

- **模板ID**: 选择特定模板的VM
- **时间范围**: 自定义查询时间
- **状态**: 筛选running/stopped VM

### 3. 告警规则

配置Grafana Alerting:

1. **VM失败率告警**:
```sql
SELECT
  COUNT(*)
FROM sandboxes
WHERE state = 'failed'
  AND started_at > NOW() - INTERVAL '1 hour'
```
条件: > 5

2. **长时间运行告警**:
```sql
SELECT
  sandbox_id,
  EXTRACT(EPOCH FROM (NOW() - started_at))/3600 as hours
FROM sandboxes
WHERE state = 'running'
  AND started_at < NOW() - INTERVAL '24 hours'
```

## 🛠️ 故障排查

### Grafana无法启动

```bash
# 1. 检查日志
docker logs e2b-grafana

# 2. 常见问题
# - Permission denied: 使用 --user root 或修复volume权限
# - Port already in use: 检查端口占用并使用备用端口
# - Network conflict: 使用 --network host

# 3. 完全重置
docker rm -f e2b-grafana
docker volume rm grafana-storage
# 然后重新启动
```

### PostgreSQL连接失败

```bash
# 1. 检查PostgreSQL状态
docker ps | grep postgres

# 2. 测试连接
docker exec -it <postgres-container> psql -U postgres -d postgres -c "\dt"

# 3. 检查网络
# 如果使用容器名连接，确保Grafana在同一网络
docker network inspect bridge | grep -A 5 grafana
docker network inspect bridge | grep -A 5 postgres
```

### 数据不显示

1. 检查SQL查询是否正确
2. 验证表名和字段名
3. 确认时间范围过滤器设置
4. 查看Grafana Query Inspector (点击Panel标题 → Inspect → Query)

## 📚 相关资源

- **E2B CLI工具**: `/home/primihub/pcloud/infra/e2b-tools/cli/e2b`
- **集成方案文档**: `/home/primihub/pcloud/infra/e2b-tools/docs/e2b-integration-plan.md`
- **VM使用指南**: `/home/primihub/pcloud/infra/e2b-tools/docs/vm-usage-guide.md`

## 🎯 替代方案

如果Grafana启动困难，考虑以下替代方案:

### 方案A: Streamlit快速Dashboard

参见集成文档中的Streamlit示例，可在10分钟内搭建简单监控界面。

### 方案B: 直接查询PostgreSQL

```bash
# 使用psql直接查询
docker exec -it <postgres-container> psql -U postgres -d postgres

# 查询VM列表
SELECT sandbox_id, state, cpu_count, memory_mb, started_at
FROM sandboxes
ORDER BY started_at DESC
LIMIT 10;

# 统计信息
SELECT state, COUNT(*) FROM sandboxes GROUP BY state;
```

### 方案C: pgAdmin Web界面

启动pgAdmin进行图形化数据库管理:

```bash
docker run -d \
  --name e2b-pgadmin \
  -p 5050:80 \
  -e "PGADMIN_DEFAULT_EMAIL=admin@example.com" \
  -e "PGADMIN_DEFAULT_PASSWORD=admin" \
  dpage/pgadmin4:latest
```

访问 http://localhost:5050 添加PostgreSQL服务器。

---

**文档创建时间**: 2025-12-22
**状态**: 就绪
**优先级**: 高
**预计完成时间**: 20-30分钟
