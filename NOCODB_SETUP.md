# NocoDB 服务配置文档

## 📅 配置时间
**日期**: 2026-02-04

---

## 🎯 服务概述

NocoDB 是一个开源的 Airtable 替代品，用于管理 pcloud 集群的服务信息和配置数据。其他 pcloud 节点可以通过 API 更新和查询服务信息。

---

## ✅ 服务状态

- **状态**: ✅ 运行中
- **容器名称**: `nocodb`
- **镜像**: `swr.cn-north-4.myhuaweicloud.com/ddn-k8s/docker.io/nocodb/nocodb:latest`
- **启动时间**: 2026-02-04 05:42:01 AM

---

## 🌐 访问信息

### 本地访问
- **URL**: http://localhost:8080
- **健康检查**: http://localhost:8080/api/v1/health

### 远程访问（其他 pcloud 节点）
- **服务器 IP**: `10.12.0.62`
- **端口**: `8080`
- **访问 URL**: http://10.12.0.62:8080
- **API 端点**: http://10.12.0.62:8080/api/v1/
- **健康检查**: http://10.12.0.62:8080/api/v1/health

### 监听配置
- **绑定地址**: `0.0.0.0:8080` (允许所有网络接口访问)
- **防火墙**: 确保端口 8080 在防火墙中开放

---

## 🔧 技术配置

### Docker Compose 配置

**文件位置**: `/mnt/data1/pcloud/infra/packages/local-dev/docker-compose.yaml`

```yaml
nocodb:
  image: swr.cn-north-4.myhuaweicloud.com/ddn-k8s/docker.io/nocodb/nocodb:latest
  container_name: nocodb
  ports:
    - "0.0.0.0:8080:8080"
  environment:
    NC_DB: "pg://postgres:5432?u=postgres&p=postgres&d=nocodb"
    NC_AUTH_JWT_SECRET: "nocodb-jwt-secret-change-in-production"
    NC_PUBLIC_URL: "http://0.0.0.0:8080"
    NC_DISABLE_TELE: "true"
  volumes:
    - nocodb:/usr/app/data
  depends_on:
    - postgres
  restart: unless-stopped
```

### 环境变量说明

| 变量 | 值 | 说明 |
|------|-----|------|
| `NC_DB` | `pg://postgres:5432?u=postgres&p=postgres&d=nocodb` | PostgreSQL 数据库连接字符串 |
| `NC_AUTH_JWT_SECRET` | `nocodb-jwt-secret-change-in-production` | JWT 密钥（生产环境需更改） |
| `NC_PUBLIC_URL` | `http://0.0.0.0:8080` | 公共访问 URL |
| `NC_DISABLE_TELE` | `true` | 禁用遥测数据收集 |

### 数据持久化

- **数据库**: PostgreSQL (共享 postgres 容器)
- **数据库名**: `nocodb`
- **数据卷**: `nocodb` (Docker volume)
- **数据路径**: `/usr/app/data` (容器内)

---

## 🚀 服务管理

### 启动服务
```bash
cd /mnt/data1/pcloud/infra/packages/local-dev
docker compose up -d nocodb
```

### 停止服务
```bash
cd /mnt/data1/pcloud/infra/packages/local-dev
docker compose stop nocodb
```

### 重启服务
```bash
cd /mnt/data1/pcloud/infra/packages/local-dev
docker compose restart nocodb
```

### 查看日志
```bash
docker logs nocodb --tail 100 -f
```

### 查看服务状态
```bash
docker ps | grep nocodb
```

### 健康检查
```bash
curl http://localhost:8080/api/v1/health
```

---

## 📊 服务验证

### 验证结果

**端口监听**:
```
tcp 0 0 0.0.0.0:8080 0.0.0.0:* LISTEN
```
✅ 端口 8080 已在所有网络接口上监听

**健康检查响应**:
```json
{
  "message": "OK",
  "timestamp": 1770183737720,
  "uptime": 22.916066614
}
```
✅ 服务健康状态正常

**容器状态**:
```
CONTAINER ID   IMAGE                                                                    STATUS
13516eac1263   swr.cn-north-4.myhuaweicloud.com/ddn-k8s/docker.io/nocodb/nocodb:latest Up 11 seconds
```
✅ 容器运行正常

---

## 🔐 安全建议

### 生产环境配置

1. **更改 JWT 密钥**
   ```yaml
   NC_AUTH_JWT_SECRET: "your-secure-random-secret-here"
   ```

2. **配置访问控制**
   - 使用防火墙限制访问来源
   - 配置 nginx 反向代理
   - 启用 HTTPS

3. **数据库安全**
   - 更改默认数据库密码
   - 限制数据库访问权限

4. **定期备份**
   - 备份 PostgreSQL 数据库
   - 备份 Docker volume

---

## 📝 使用场景

### pcloud 节点服务注册

其他 pcloud 节点可以通过 NocoDB API 注册和更新服务信息：

```bash
# 示例：注册服务信息
curl -X POST http://10.12.0.62:8080/api/v1/db/data/noco/services \
  -H "Content-Type: application/json" \
  -d '{
    "node_id": "pcloud-node-01",
    "service_name": "fragments",
    "service_url": "http://10.12.0.63:3000",
    "status": "running",
    "last_updated": "2026-02-04T05:42:00Z"
  }'
```

### 查询服务信息

```bash
# 查询所有服务
curl http://10.12.0.62:8080/api/v1/db/data/noco/services

# 查询特定节点的服务
curl "http://10.12.0.62:8080/api/v1/db/data/noco/services?where=(node_id,eq,pcloud-node-01)"
```

---

## 🔄 集成说明

### 与 pcloud 集群集成

1. **服务发现**: 各节点启动时向 NocoDB 注册服务信息
2. **健康监控**: 定期更新服务状态到 NocoDB
3. **配置管理**: 从 NocoDB 读取集群配置
4. **负载均衡**: 根据 NocoDB 中的服务信息进行负载分配

### API 认证

首次访问需要创建管理员账户：
1. 访问 http://10.12.0.62:8080
2. 创建管理员账户
3. 获取 API Token 用于程序访问

---

## 📈 监控指标

### 关键指标

- **服务可用性**: 通过健康检查端点监控
- **响应时间**: API 请求响应时间
- **数据库连接**: PostgreSQL 连接状态
- **容器资源**: CPU 和内存使用情况

### 监控命令

```bash
# 查看容器资源使用
docker stats nocodb --no-stream

# 查看数据库连接
docker exec nocodb-postgres-1 psql -U postgres -d nocodb -c "SELECT count(*) FROM pg_stat_activity;"
```

---

## 🐛 故障排查

### 常见问题

1. **服务无法启动**
   - 检查 PostgreSQL 是否运行: `docker ps | grep postgres`
   - 查看日志: `docker logs nocodb`

2. **无法从其他服务器访问**
   - 检查防火墙: `sudo ufw status`
   - 检查端口监听: `netstat -tlnp | grep 8080`
   - 测试网络连通性: `ping 10.12.0.62`

3. **数据库连接失败**
   - 检查 PostgreSQL 状态
   - 验证数据库凭据
   - 检查网络连接

---

## 📚 相关文档

- [NocoDB 官方文档](https://docs.nocodb.com/)
- [NocoDB API 文档](https://docs.nocodb.com/developer-resources/rest-apis)
- [Docker Compose 文档](https://docs.docker.com/compose/)

---

## ✨ 总结

### 完成的工作
- ✅ 配置 NocoDB 服务到 docker-compose.yaml
- ✅ 使用镜像仓库解决网络访问问题
- ✅ 配置服务监听所有网络接口 (0.0.0.0)
- ✅ 连接到 PostgreSQL 数据库
- ✅ 验证服务健康状态
- ✅ 确认远程访问能力

### 服务信息
- **本地访问**: http://localhost:8080
- **远程访问**: http://10.12.0.62:8080
- **健康状态**: ✅ 正常运行
- **数据持久化**: ✅ PostgreSQL + Docker Volume

### 下一步
1. 创建管理员账户
2. 配置 API Token
3. 创建服务信息表结构
4. 集成到 pcloud 节点服务发现

---

**配置完成时间**: 2026-02-04
**服务状态**: ✅ 运行中
**可访问性**: ✅ 本地 + 远程
**数据持久化**: ✅ 已配置
