# E2B工具集 - 文件索引

本目录包含从 /tmp 移动过来的所有E2B相关工具和脚本。

## 📁 目录结构

```
e2b-tools/
├── docs/                    # 文档
│   ├── E2B_CODE_ANALYSIS_AND_INTEGRATION_CN.md
│   ├── PYTHON_SDK_INTEGRATION_GUIDE.md
│   ├── NETWORK_FIX_GUIDE.md
│   ├── FINAL_EXECUTION_REPORT.md
│   ├── QUICK_REFERENCE.md
│   └── VM_EXECUTION_TEST_REPORT.md
│
├── examples/                # Python示例脚本
│   ├── sdk_local_integration.py     ⭐ SDK集成演示（推荐运行）
│   ├── test_e2b_complete.py        ⭐ 完整测试套件
│   ├── test_e2b_sdk.py             # SDK基础测试
│   ├── execute_in_vm.py            # REST API客户端
│   ├── execute_code.py             # gRPC代码执行
│   ├── demo_execution.py           # 执行演示
│   ├── test_vm_execution.py        # VM执行测试
│   └── shell-simple.py             # 简单Shell
│
├── scripts/                 # Shell脚本
│   ├── setup_e2b_env.sh            ⭐ 环境设置（推荐先运行）
│   ├── build-template-auto-modified.sh
│   ├── build_template_with_hugepages.sh
│   ├── build_template_with_proxy.sh
│   ├── verify_hugepages.sh
│   ├── fix-cache.sh
│   ├── fix-rootfs-with-envd.sh
│   └── 其他修复脚本...
│
└── cli/                     # CLI工具
    └── e2b (链接到 /usr/local/bin/e2b)
```

---

## 🚀 快速开始

### 1. 环境设置

```bash
# 运行环境设置脚本
bash scripts/setup_e2b_env.sh

# 激活Python虚拟环境
source ~/e2b-env/bin/activate
```

### 2. 运行SDK集成演示

```bash
# 这是最推荐的演示脚本
python3 examples/sdk_local_integration.py
```

这个脚本会：
- ✅ 验证SDK配置
- ✅ 检查API健康状态
- ✅ 演示REST API功能
- ✅ 尝试完整SDK功能
- ✅ 显示SDK所有能力

### 3. 运行完整测试套件

```bash
# 8个完整测试用例
python3 examples/test_e2b_complete.py
```

---

## 📚 Python脚本说明

### 核心脚本

#### `sdk_local_integration.py` ⭐⭐⭐⭐⭐

**完整的SDK集成演示和验证工具**

功能:
- ✅ 配置本地E2B环境
- ✅ 健康检查（API、Orchestrator）
- ✅ 演示REST API基础功能（列表、查询、创建、删除VM）
- ✅ 演示SDK完整功能（代码执行、文件操作等）
- ✅ 显示SDK完整能力清单
- ✅ 提供详细的故障排查信息

使用:
```bash
source ~/e2b-env/bin/activate
python3 examples/sdk_local_integration.py
```

输出示例:
```
╔====================================================================╗
║               E2B Python SDK 本地集成测试                        ║
╚====================================================================╝

🔧 配置本地E2B SDK环境
✅ 环境变量已设置
✅ SDK连接配置正常

🏥 检查E2B服务健康状态
✅ API服务 - 正常
✅ Orchestrator服务 - 正常

📡 演示1: 使用REST API管理VM
...
```

---

#### `test_e2b_complete.py` ⭐⭐⭐⭐

**包含8个测试用例的完整测试套件**

测试用例:
1. ✅ Hello World - 基础代码执行
2. ✅ 基础计算 - 数字处理
3. ✅ 系统信息 - 获取VM信息
4. ✅ 数据处理 - 数据分析
5. ✅ 文件操作 - 读写文件
6. ✅ Shell命令 - 执行系统命令
7. ✅ 复杂程序 - 斐波那契数列
8. ✅ 网络访问 - HTTP请求测试

使用:
```bash
python3 examples/test_e2b_complete.py
```

---

#### `execute_in_vm.py` ⭐⭐⭐⭐

**REST API客户端包装类**

提供的功能:
- ✅ `E2BClient` 类 - 完整的REST API封装
- ✅ `demo_basic_usage()` - 基础使用演示
- ✅ `demo_with_grpc()` - gRPC示例说明
- ✅ `demo_with_sdk()` - SDK使用说明

使用:
```bash
# 运行基础演示
python3 examples/execute_in_vm.py demo

# 查看gRPC示例
python3 examples/execute_in_vm.py grpc

# 查看SDK示例
python3 examples/execute_in_vm.py sdk

# 在代码中使用
from execute_in_vm import E2BClient
client = E2BClient()
vms = client.list_sandboxes()
```

---

### 辅助脚本

#### `test_e2b_sdk.py`

SDK基础测试，验证SDK导入和基本功能。

#### `execute_code.py`

gRPC直连envd执行代码（需要网络修复）。

#### `demo_execution.py`

执行演示脚本。

#### `test_vm_execution.py`

VM执行测试。

#### `shell-simple.py`

简单交互式Shell概念验证。

---

## 🔧 Shell脚本说明

### 核心脚本

#### `setup_e2b_env.sh` ⭐⭐⭐⭐⭐

**一键环境设置脚本**

功能:
1. ✅ 创建Python虚拟环境 (`~/e2b-env`)
2. ✅ 安装pip
3. ✅ 安装E2B SDK和依赖
4. ✅ 设置环境变量
5. ✅ 测试SDK导入

使用:
```bash
bash scripts/setup_e2b_env.sh
```

---

### 模板构建脚本

#### `build-template-auto-modified.sh`

自动化模板构建脚本（修改版）。

#### `build_template_with_hugepages.sh`

使用HugePages构建模板。

#### `build_template_with_proxy.sh`

使用代理构建模板。

---

### 修复脚本

#### `fix-cache.sh`

修复模板缓存。

#### `fix-rootfs-with-envd.sh`

修复rootfs并添加envd。

#### `verify_hugepages.sh`

验证HugePages配置。

---

## 📊 文件移动记录

### 从 /tmp 移动的文件

**Python脚本** (移动到 `examples/`):
- ✅ `/tmp/test_e2b_complete.py` → `examples/test_e2b_complete.py`
- ✅ `/tmp/test_e2b_sdk.py` → `examples/test_e2b_sdk.py`
- ✅ `/tmp/execute_code.py` → `examples/execute_code.py`
- ✅ `/tmp/demo_execution.py` → `examples/demo_execution.py`
- ✅ `/tmp/test_vm_execution.py` → `examples/test_vm_execution.py`

**Shell脚本** (移动到 `scripts/`):
- ✅ `/tmp/setup_e2b_env.sh` → `scripts/setup_e2b_env.sh`
- ✅ `/tmp/build-template-auto-modified.sh` → `scripts/build-template-auto-modified.sh`
- ✅ `/tmp/build_template_with_hugepages.sh` → `scripts/build_template_with_hugepages.sh`
- ✅ `/tmp/build_template_with_proxy.sh` → `scripts/build_template_with_proxy.sh`
- ✅ `/tmp/verify_hugepages.sh` → `scripts/verify_hugepages.sh`
- ✅ `/tmp/orchestrator-sudo.sh` → `scripts/orchestrator-sudo.sh`
- ✅ `/tmp/init-script.sh` → `scripts/init-script.sh`
- ✅ `/tmp/move-files.sh` → `scripts/move-files.sh`

**权限设置**:
- ✅ 所有Python脚本设置为可执行 (`chmod +x`)
- ✅ Shell脚本保持原有权限

---

## 🎯 推荐使用流程

### 首次设置

```bash
# 1. 环境设置
cd /home/primihub/pcloud/infra/e2b-tools
bash scripts/setup_e2b_env.sh

# 2. 激活环境
source ~/e2b-env/bin/activate

# 3. 验证SDK
python3 -c "from e2b import Sandbox; print('SDK已就绪')"
```

### 日常使用

```bash
# 1. 激活环境
source ~/e2b-env/bin/activate

# 2. 运行集成演示（推荐）
python3 examples/sdk_local_integration.py

# 3. 或运行完整测试
python3 examples/test_e2b_complete.py

# 4. 或使用REST API客户端
python3 examples/execute_in_vm.py demo
```

---

## 📖 相关文档

详细文档位于 `docs/` 目录:

1. **`E2B_CODE_ANALYSIS_AND_INTEGRATION_CN.md`** - 代码分析与集成方案总结
2. **`PYTHON_SDK_INTEGRATION_GUIDE.md`** - Python SDK完整集成指南
3. **`NETWORK_FIX_GUIDE.md`** - 网络修复指南
4. **`FINAL_EXECUTION_REPORT.md`** - 最终执行报告
5. **`QUICK_REFERENCE.md`** - 快速参考

阅读顺序建议:
1. 先读: `E2B_CODE_ANALYSIS_AND_INTEGRATION_CN.md`
2. 再读: `PYTHON_SDK_INTEGRATION_GUIDE.md`
3. 如需修复网络: `NETWORK_FIX_GUIDE.md`

---

## ⚠️ 已知问题

### 当前状态

| 功能 | 状态 | 说明 |
|------|------|------|
| SDK配置 | ✅ 正常 | 完全支持本地部署 |
| REST API | ✅ 部分可用 | 查询功能正常 |
| VM创建 | ❌ 失败 | "no node available"错误 |
| 代码执行 | ❌ 失败 | 需要VM创建修复 |
| 网络路由 | ❌ 未配置 | envd:49983无法连接 |

### 解决方案

参考文档:
- VM创建问题 → `E2B_CODE_ANALYSIS_AND_INTEGRATION_CN.md` 第6节
- 网络问题 → `NETWORK_FIX_GUIDE.md`

---

## 🎉 总结

所有工具和脚本已从 `/tmp` 目录整理到 `e2b-tools/` 下:
- ✅ 8个Python示例脚本
- ✅ 13个Shell工具脚本
- ✅ 6份完整文档
- ✅ 所有脚本可执行

推荐立即运行: `python3 examples/sdk_local_integration.py`

---

**文件整理完成时间**: 2025-12-22
**总文件数**: 21个脚本 + 6份文档
**总大小**: ~150KB (脚本) + ~100KB (文档)
**状态**: ✅ 完全整理完毕
