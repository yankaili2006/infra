# E2B目录结构说明

## 整体结构
```
infra/e2b/
├── README.md                    # 主文档
├── DIRECTORY_STRUCTURE.md       # 目录结构说明 (本文档)
├── config/                      # 配置文件目录
│   ├── .env.e2b                 # 环境变量配置 (从.example复制)
│   ├── .env.e2b.example         # 环境变量配置示例
│   ├── docker-compose.e2b.yml   # Docker Compose配置
│   └── init.sql                 # 数据库初始化脚本
├── docs/                        # 文档目录
│   ├── e2b_complete_deployment_guide.md    # 完整部署指南
│   └── upgrade_for_e2b_deployment.md       # 资源升级指南
├── scripts/                     # 脚本目录
│   ├── check_e2b_requirements.sh           # 系统资源检查
│   ├── manage_e2b.sh                       # E2B服务管理
│   ├── quick_start.sh                      # 快速启动脚本
│   └── start_e2b_service.sh                # 服务启动脚本
└── examples/                    # 示例代码目录
    ├── create_e2b_vm.py                    # Python VM创建示例
    ├── create_e2b_vm_fixed.py              # 修复版Python示例
    ├── test_e2b.py                         # 完整测试脚本
    └── test_e2b_simple.py                  # 简单测试脚本
```

## 文件说明

### 配置文件 (config/)
| 文件 | 说明 |
|------|------|
| `.env.e2b.example` | 环境变量配置示例，复制为`.env.e2b`使用 |
| `docker-compose.e2b.yml` | Docker Compose服务配置 |
| `init.sql` | 数据库初始化脚本 |

### 文档文件 (docs/)
| 文件 | 说明 |
|------|------|
| `e2b_complete_deployment_guide.md` | 完整部署指南，包含生产环境配置 |
| `upgrade_for_e2b_deployment.md` | 资源升级指南，系统优化建议 |

### 脚本文件 (scripts/)
| 文件 | 说明 | 用法 |
|------|------|------|
| `check_e2b_requirements.sh` | 系统资源检查 | `bash scripts/check_e2b_requirements.sh` |
| `manage_e2b.sh` | E2B服务管理 | `bash scripts/manage_e2b.sh [命令]` |
| `quick_start.sh` | 快速启动脚本 | `bash scripts/quick_start.sh` |
| `start_e2b_service.sh` | 服务启动脚本 | `bash scripts/start_e2b_service.sh` |

### 示例代码 (examples/)
| 文件 | 说明 |
|------|------|
| `create_e2b_vm.py` | Python VM创建示例 (旧版API) |
| `create_e2b_vm_fixed.py` | Python VM创建示例 (新版API) |
| `test_e2b.py` | E2B功能测试脚本 |
| `test_e2b_simple.py` | 简单测试脚本 |

## 使用流程

### 1. 初始化配置
```bash
cd /root/pcloud/infra/e2b

# 复制配置文件
cp config/.env.e2b.example config/.env.e2b

# 编辑配置
vim config/.env.e2b
```

### 2. 检查系统要求
```bash
bash scripts/check_e2b_requirements.sh
```

### 3. 启动服务
```bash
# 方法A: 使用管理脚本
bash scripts/manage_e2b.sh start

# 方法B: 使用快速启动
bash scripts/quick_start.sh

# 方法C: 直接启动
bash scripts/start_e2b_service.sh
```

### 4. 管理服务
```bash
# 查看状态
bash scripts/manage_e2b.sh status

# 查看日志
bash scripts/manage_e2b.sh logs

# 健康检查
bash scripts/manage_e2b.sh health

# 备份数据
bash scripts/manage_e2b.sh backup
```

### 5. 创建VM
```bash
# 使用Python示例
cd examples
source ../../e2b-venv/bin/activate
python create_e2b_vm_fixed.py
```

## 环境变量配置

### 必需配置
```bash
# 数据库配置
POSTGRES_USER=postgres
POSTGRES_PASSWORD=your_password
POSTGRES_DB=e2b

# Redis配置
REDIS_PASSWORD=your_password

# E2B API配置
E2B_API_KEY=e2b_$(openssl rand -hex 16)
```

### 可选配置
```bash
# 端口配置
E2B_API_PORT=3000
E2B_CLIENT_PROXY_PORT=3002
GRAFANA_PORT=3001

# 资源限制
MAX_CONCURRENT_SANDBOXES=10
SANDBOX_TIMEOUT_SECONDS=3600
```

## 服务管理命令

### 启动/停止
```bash
# 启动所有服务
docker-compose -f config/docker-compose.e2b.yml up -d

# 停止所有服务
docker-compose -f config/docker-compose.e2b.yml down

# 重启服务
docker-compose -f config/docker-compose.e2b.yml restart
```

### 监控和日志
```bash
# 查看服务状态
docker-compose -f config/docker-compose.e2b.yml ps

# 查看日志
docker-compose -f config/docker-compose.e2b.yml logs -f

# 进入容器
docker-compose -f config/docker-compose.e2b.yml exec e2b-api bash
```

### 数据管理
```bash
# 备份数据库
docker-compose -f config/docker-compose.e2b.yml exec postgres pg_dump -U postgres e2b > backup.sql

# 恢复数据库
docker-compose -f config/docker-compose.e2b.yml exec -T postgres psql -U postgres e2b < backup.sql
```

## 故障排除

### 常见问题
1. **端口冲突**: 修改`.env.e2b`中的端口配置
2. **内存不足**: 参考`docs/upgrade_for_e2b_deployment.md`
3. **权限问题**: 确保用户有Docker和KVM权限
4. **网络问题**: 检查防火墙和网络配置

### 日志位置
- **Docker日志**: `docker-compose logs`
- **应用日志**: `config/logs/`目录
- **系统日志**: `/var/log/syslog`

## 扩展开发

### 添加新脚本
1. 在`scripts/`目录创建新脚本
2. 添加执行权限: `chmod +x scripts/your_script.sh`
3. 更新`README.md`文档

### 修改配置
1. 更新`config/docker-compose.e2b.yml`
2. 更新`config/.env.e2b.example`
3. 测试配置变更

### 添加示例
1. 在`examples/`目录添加新示例
2. 确保代码可运行
3. 更新相关文档

## 维护说明

### 定期任务
- [ ] 检查服务状态
- [ ] 备份重要数据
- [ ] 清理日志文件
- [ ] 更新Docker镜像

### 版本控制
- 配置文件使用环境变量
- 数据库变更使用迁移脚本
- 重要变更更新文档

### 安全建议
- 定期轮换API密钥
- 使用强密码
- 限制网络访问
- 启用日志审计

---

**最后更新**: 2025-12-17  
**维护者**: E2B集成团队