# Fragments 系统集成功能

## 概述

Fragments 现在作为 pcloud 系统的统一入口界面，集成了系统监控和管理功能。

## 新增功能

### 1. 系统状态监控面板

**访问路径**: `/system` 或点击导航栏的活动图标 (Activity)

**功能特性**:
- 实时显示系统服务状态
- 资源使用情况监控（磁盘、Docker）
- 自动刷新（每30秒）
- 手动刷新按钮

### 2. 服务分类

系统状态面板按以下类别组织服务：

#### 核心服务 (Core Services)
- Fragments UI - AI代码执行界面
- E2B Orchestrator - 代码执行编排器
- NocoDB - 数据管理平台

#### MCP 服务 (MCP Services)
- MCP Proxy - MCP服务代理
- 各类 MCP 服务器

#### Skills 技能
- Infrastructure Skill - 基础设施监控
- Server Skill - 服务器管理
- 其他技能模块

#### 基础设施 (Infrastructure)
- Proxmox - 虚拟化平台
- Docker - 容器平台

## 技术实现

### API 端点

**GET /api/system/status**

返回系统状态信息：
```json
{
  "timestamp": "2026-02-04T12:00:00.000Z",
  "services": {
    "core": [...],
    "mcp": [...],
    "skills": [...],
    "infrastructure": [...]
  },
  "resources": {
    "disk": {...},
    "docker": {...}
  }
}
```

### 组件结构

- `app/api/system/status/route.ts` - 系统状态 API
- `app/system/page.tsx` - 系统状态页面
- `components/system-status.tsx` - 系统状态组件
- `components/navbar.tsx` - 增强的导航栏

## 使用指南

### 查看系统状态

1. 启动 Fragments 服务
2. 访问 http://localhost:3001
3. 点击导航栏右侧的活动图标 (Activity)
4. 查看各服务的运行状态

### 状态指示器

- 🟢 **Running** - 服务正常运行
- 🔴 **Stopped** - 服务已停止
- 🟡 **Error** - 服务出现错误
- ⚪ **Unknown** - 状态未知

## 下一步计划

- [ ] 实现实时服务状态检测
- [ ] 添加服务启动/停止控制
- [ ] 集成日志查看功能
- [ ] 添加告警通知
- [ ] 实现性能指标图表

## 相关文档

- [PROJECT_SUMMARY.md](./PROJECT_SUMMARY.md) - 项目总结
- [QUICKSTART.md](./QUICKSTART.md) - 快速开始
- [TEMPLATE_AUTO_SELECTION.md](./TEMPLATE_AUTO_SELECTION.md) - 模板自动选择
