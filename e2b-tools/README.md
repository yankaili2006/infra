# E2B Tools - 工具集合

本目录包含E2B Firecracker VM项目开发过程中创建的各种工具、脚本和文档。

## 📁 目录结构

```
e2b-tools/
├── README.md           # 本文档
├── cli/                # 命令行工具
│   ├── e2b             # E2B VM管理CLI工具
│   └── install.sh      # CLI安装脚本
├── scripts/            # 实用脚本
│   ├── fix-*.sh        # 各种问题修复脚本
│   └── ...
├── docs/               # 文档指南
│   ├── vm-usage-guide.md           # VM使用指南
│   ├── interactive-shell-guide.md  # 交互式Shell实现指南
│   └── directory-analysis.md       # E2B目录完整分析
└── examples/           # 示例代码
    ├── shell-client.go # Go语言Shell客户端
    └── shell-simple.py # Python简单Shell示例
```

## 🛠️ CLI工具

### E2B命令行工具

**位置**: `cli/e2b`

**功能**:
- 创建和管理虚拟机
- 查看VM列表和详情
- 查看VM日志
- 延长VM生命周期
- 删除VM

**安装**:
```bash
cd /home/primihub/pcloud/infra/e2b-tools/cli
bash install.sh
```

**使用**:
```bash
# 创建VM
e2b create

# 列出所有VM
e2b ls

# 查看VM详情
e2b info

# 查看日志
e2b logs

# 延长生命周期
e2b extend 3600

# 删除VM
e2b rm <vm-id>

# 帮助
e2b help
```

## 📜 修复脚本

**位置**: `scripts/`

### fix-cache-with-password.sh
修复E2B模板缓存，填充空的缓存目录。

### fix-rootfs-with-envd.sh
向rootfs添加envd二进制文件和正确的init脚本。

### fix-hardcoded-rootfs.sh
修复硬编码路径的rootfs（用于测试的特定build ID）。

### fix-original-rootfs.sh
修复原始模板存储的rootfs。

### fix-cache.sh
简单的缓存修复脚本（早期版本）。

## 📚 文档指南

**位置**: `docs/`

### vm-usage-guide.md
完整的E2B虚拟机使用指南，包括：
- 基本操作（列出、创建、删除VM）
- API使用方法
- 高级配置选项
- 故障排查

### interactive-shell-guide.md
交互式Shell实现指南，包括：
- 需求分析
- 技术方案对比（envd vs SSH）
- 实现计划
- Python和Go示例代码
- 快速参考命令

### directory-analysis.md
E2B目录完整功能分析，包括：
- 目录结构详解
- 核心功能说明
- 脚本和工具分析
- 使用场景和最佳实践
- 技术栈和资源需求

## 💻 示例代码

**位置**: `examples/`

### shell-client.go
Go语言实现的交互式Shell客户端框架。

**特性**:
- 使用Connect RPC连接envd
- PTY（伪终端）支持
- 流式输入输出处理
- 终端大小自适应

**编译**:
```bash
cd examples
go build -o e2b-shell shell-client.go
```

### shell-simple.py
Python简单Shell示例（概念验证）。

**特性**:
- 连接到E2B API
- 获取VM信息
- 模拟交互式访问
- 展示实现思路

**运行**:
```bash
cd examples
python3 shell-simple.py <sandbox-id>
```

## 🎯 快速开始

### 1. 安装CLI工具
```bash
cd /home/primihub/pcloud/infra/e2b-tools/cli
bash install.sh
```

### 2. 创建并管理VM
```bash
# 创建VM
e2b create

# 查看VM
e2b ls

# 查看详情
e2b info
```

### 3. 阅读文档
```bash
# 查看VM使用指南
cat docs/vm-usage-guide.md

# 查看交互式Shell指南
cat docs/interactive-shell-guide.md

# 查看完整分析
cat docs/directory-analysis.md
```

## 📖 相关文档

- **E2B主项目**: `/home/primihub/pcloud/infra/e2b/`
- **E2B文档**: `/home/primihub/pcloud/infra/CLAUDE.md`
- **官方文档**: https://e2b.dev/docs

## 🔧 维护说明

### 添加新工具
1. 在相应目录（cli/scripts/examples）创建文件
2. 添加执行权限: `chmod +x <file>`
3. 更新本README

### 更新文档
1. 编辑docs/目录下的Markdown文件
2. 保持格式一致
3. 添加更新日期

### 版本控制
所有文件都在git仓库中，使用git进行版本管理：
```bash
git add e2b-tools/
git commit -m "描述更改"
```

---

**创建时间**: 2025-12-22
**最后更新**: 2025-12-22
**维护者**: E2B项目团队
