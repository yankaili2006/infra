# Ubuntu Desktop Template for E2B

完整的 Ubuntu Desktop (GNOME) 环境模板，支持 VNC 远程访问。

## 快速开始

### 1. 构建模板

```bash
cd /home/primihub/pcloud/infra/templates/ubuntu-desktop-local
sudo ./create_template.sh
```

构建时间：约 15-20 分钟

### 2. 清理缓存

```bash
sudo rm -rf /home/primihub/e2b-storage/e2b-template-cache/*
sudo rm -rf /home/primihub/e2b-storage/e2b-chunk-cache/*
```

### 3. 创建沙箱

```bash
curl -X POST http://localhost:3000/sandboxes \
  -H 'Content-Type: application/json' \
  -H 'X-API-Key: e2b_53ae1fed82754c17ad8077fbc8bcdd90' \
  -d '{"templateID": "ubuntu-desktop-v1", "timeout": 600}'
```

### 4. 访问桌面

- **VNC**: `localhost:5900` (密码: `e2bdesktop`)
- **noVNC**: `http://localhost:6080/vnc.html`

## 配置说明

- **CPU**: 4 核
- **内存**: 8GB
- **磁盘**: 15GB
- **桌面环境**: GNOME
- **显示管理器**: GDM

## 文件说明

- `template.py` - E2B 模板定义（未使用）
- `create_template.sh` - 构建脚本（实际使用）
- `start-desktop.sh` - 桌面启动脚本

## 注意事项

1. 需要 sudo 权限
2. 确保有足够的磁盘空间（至少 20GB）
3. 构建过程需要网络连接
4. 基于 base 模板 (9ac9c8b9-9b8b-476c-9238-8266af308c32)
