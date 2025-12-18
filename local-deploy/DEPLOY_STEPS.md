# E2B 本地部署执行步骤

由于需要 sudo 权限，请按以下顺序手动执行脚本：

## 步骤 1: 系统检查（已完成）
```bash
cd /home/primihub/pcloud/infra/local-deploy
bash scripts/01-check-requirements.sh
```

## 步骤 2: 安装依赖（需要 sudo）
```bash
sudo bash scripts/02-install-deps.sh
```
**说明**: 安装 Docker, Go, Make 等必需软件
**预计时间**: 5-10 分钟

**重要**: 安装完成后需要重新登录，使 docker 和 kvm 组权限生效！

## 步骤 3: 重新登录
```bash
# 退出当前会话
exit
# 重新登录
```

## 步骤 4: 配置内核（需要 sudo）
```bash
cd /home/primihub/pcloud/infra/local-deploy
sudo bash scripts/03-setup-kernel.sh
```
**说明**: 加载 KVM 和 NBD 模块，配置 Hugepages
**预计时间**: 1 分钟

## 步骤 5: 配置 Sudo 权限（需要 sudo）
```bash
sudo bash scripts/04-setup-sudo.sh
```
**说明**: 为 Firecracker 配置权限
**选择**: 推荐选择 A (Capabilities)
**预计时间**: 1 分钟

## 步骤 6: 创建存储目录（需要 sudo）
```bash
sudo bash scripts/05-setup-storage.sh
```
**说明**: 创建所有必需的存储目录
**预计时间**: 1 分钟

## 步骤 7: 构建 Go 二进制
```bash
bash scripts/06-build-binaries.sh
```
**说明**: 构建 Orchestrator 和 Envd
**预计时间**: 10-20 分钟

## 步骤 8: 构建 Docker 镜像
```bash
bash scripts/07-build-images.sh
```
**说明**: 构建 API, Client-Proxy, DB-Migrator 镜像
**预计时间**: 10-20 分钟

## 步骤 9: 安装 Nomad & Consul（需要 sudo）
```bash
sudo bash scripts/08-install-nomad-consul.sh
```
**说明**: 安装 HashiCorp 工具
**预计时间**: 2-3 分钟

## 步骤 10: 初始化数据库
```bash
bash scripts/09-init-database.sh
```
**说明**: 启动基础设施并运行数据库迁移
**预计时间**: 2-3 分钟

## 步骤 11: 启动所有服务
```bash
bash scripts/start-all.sh
```
**说明**: 启动 Consul, Nomad, 和所有 Jobs
**预计时间**: 2-5 分钟

## 步骤 12: 验证部署
```bash
bash scripts/verify-deployment.sh
```

## 步骤 13: 访问服务
- 主页: http://localhost:80
- API: http://localhost:3000
- Grafana: http://localhost:53000  
- Nomad UI: http://localhost:4646
- Consul UI: http://localhost:8500

---

## 一键执行（适用于后续部署）

首次部署完成后，下次可以使用：

```bash
cd /home/primihub/pcloud/infra
make local-deploy-start    # 启动所有服务
make local-deploy-stop     # 停止所有服务
make local-deploy-verify   # 验证部署
```

## 故障排除

如遇问题，查看日志：
```bash
# Nomad/Consul 日志
tail -f /mnt/sdb/e2b-storage/logs/*.log

# Nomad Job 日志
nomad alloc logs -f <alloc-id>

# Docker 日志
docker compose -f packages/local-dev/docker-compose.yaml logs -f
```

完整文档请查看: `/home/primihub/pcloud/infra/local-deploy/README.md`
