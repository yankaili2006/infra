# E2B虚拟机使用指南

## 基本信息

- **API地址**: `http://localhost:3000`
- **API Key**: `e2b_53ae1fed82754c17ad8077fbc8bcdd90`
- **当前运行的VM**: `imnpduu72epvud6nngrd1`

## 常用操作

### 1. 列出所有运行中的虚拟机

```bash
curl -X GET http://localhost:3000/sandboxes \
  -H "X-API-Key: e2b_53ae1fed82754c17ad8077fbc8bcdd90"
```

### 2. 查看特定虚拟机详情

```bash
curl -X GET http://localhost:3000/sandboxes/imnpduu72epvud6nngrd1 \
  -H "X-API-Key: e2b_53ae1fed82754c17ad8077fbc8bcdd90"
```

### 3. 创建新的虚拟机

```bash
curl -X POST http://localhost:3000/sandboxes \
  -H "Content-Type: application/json" \
  -H "X-API-Key: e2b_53ae1fed82754c17ad8077fbc8bcdd90" \
  -d '{
    "templateID": "base-template-000-0000-0000-000000000001",
    "timeout": 300
  }'
```

### 4. 延长虚拟机存活时间

```bash
curl -X POST http://localhost:3000/sandboxes/imnpduu72epvud6nngrd1/refreshes \
  -H "Content-Type: application/json" \
  -H "X-API-Key: e2b_53ae1fed82754c17ad8077fbc8bcdd90" \
  -d '{
    "duration": 600
  }'
```

### 5. 设置虚拟机超时时间

```bash
curl -X POST http://localhost:3000/sandboxes/imnpduu72epvud6nngrd1/timeout \
  -H "Content-Type: application/json" \
  -H "X-API-Key: e2b_53ae1fed82754c17ad8077fbc8bcdd90" \
  -d '{
    "timeout": 600
  }'
```

### 6. 暂停虚拟机

```bash
curl -X POST http://localhost:3000/sandboxes/imnpduu72epvud6nngrd1/pause \
  -H "X-API-Key: e2b_53ae1fed82754c17ad8077fbc8bcdd90"
```

### 7. 恢复虚拟机

```bash
curl -X POST http://localhost:3000/sandboxes/imnpduu72epvud6nngrd1/resume \
  -H "X-API-Key: e2b_53ae1fed82754c17ad8077fbc8bcdd90"
```

### 8. 连接到虚拟机（恢复并延长TTL）

```bash
curl -X POST http://localhost:3000/sandboxes/imnpduu72epvud6nngrd1/connect \
  -H "X-API-Key: e2b_53ae1fed82754c17ad8077fbc8bcdd90"
```

### 9. 查看虚拟机日志

```bash
curl -X GET "http://localhost:3000/sandboxes/imnpduu72epvud6nngrd1/logs?start=0" \
  -H "X-API-Key: e2b_53ae1fed82754c17ad8077fbc8bcdd90"
```

### 10. 删除虚拟机

```bash
curl -X DELETE http://localhost:3000/sandboxes/imnpduu72epvud6nngrd1 \
  -H "X-API-Key: e2b_53ae1fed82754c17ad8077fbc8bcdd90"
```

### 11. 查看虚拟机指标

```bash
curl -X GET http://localhost:3000/sandboxes/imnpduu72epvud6nngrd1/metrics \
  -H "X-API-Key: e2b_53ae1fed82754c17ad8077fbc8bcdd90"
```

## 使用便捷脚本

使用已有的管理脚本：

```bash
# 创建VM
/home/primihub/pcloud/infra/e2b-vm-manager.sh create

# 列出所有VM
/home/primihub/pcloud/infra/e2b-vm-manager.sh list

# 删除VM
/home/primihub/pcloud/infra/e2b-vm-manager.sh delete <sandbox-id>
```

## 注意事项

1. **VM生命周期**: 默认timeout为300秒（5分钟），需要定期刷新
2. **资源限制**:
   - CPU: 2核
   - 内存: 512MB
   - 可以在创建时自定义
3. **网络**: VM有独立的网络命名空间，通过tap设备连接
4. **存储**: 基于rootfs.ext4镜像，修改不持久化（除非创建快照）

## 高级用法

### 创建带自定义配置的VM

```bash
curl -X POST http://localhost:3000/sandboxes \
  -H "Content-Type: application/json" \
  -H "X-API-Key: e2b_53ae1fed82754c17ad8077fbc8bcdd90" \
  -d '{
    "templateID": "base-template-000-0000-0000-000000000001",
    "timeout": 600,
    "metadata": {
      "user": "test-user",
      "app": "dev"
    }
  }'
```

### 根据metadata筛选VM

```bash
curl -X GET "http://localhost:3000/sandboxes?metadata=user%3Dtest-user%26app%3Ddev" \
  -H "X-API-Key: e2b_53ae1fed82754c17ad8077fbc8bcdd90"
```

## 故障排查

### 检查VM是否真正运行

```bash
# 查看Firecracker进程
ps aux | grep firecracker

# 查看orchestrator日志
nomad alloc logs $(nomad job allocs orchestrator | grep running | awk '{print $1}') | tail -50
```

### 查看API日志

```bash
nomad alloc logs $(nomad job allocs api | grep running | awk '{print $1}') api | tail -50
```
