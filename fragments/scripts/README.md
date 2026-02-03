# Fragments 工具脚本

## 双层端口转发工具

### 文件
- `setup-dual-layer-forwarding.sh` - E2B 沙箱双层端口转发设置工具

### 用途

为 E2B 沙箱设置完整的双层 TCP 端口转发，解决 Web 应用预览无法访问的问题。

### 快速开始

```bash
# 设置端口转发
./setup-dual-layer-forwarding.sh setup 10.11.1.58 3000 31988

# 查看状态
./setup-dual-layer-forwarding.sh status 10.11.1.58 3000

# 清理转发
./setup-dual-layer-forwarding.sh cleanup 10.11.1.58 3000 31988
```

### 网络架构

```
外部访问 → 100.64.0.23:31988 (Tailscale IP)
         ↓ Layer 1 (Host)
         → 10.12.2.117:3000 (vpeerIP)
         ↓ Layer 2 (Namespace)
         → 169.254.0.21:3000 (VM Internal)
         ↓
         Next.js App
```

### 相关文档

- [Fragments Preview 修复文档](../../../docs/FRAGMENTS_PREVIEW_FIX.md)
- [E2B 网络架构](../../packages/orchestrator/internal/sandbox/network/)
