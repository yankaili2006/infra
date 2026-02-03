# 前端架构重构方案

## 目标
将多个独立前端应用整合为单一入口点，提供统一的用户体验。

## 重构策略

### 方案A: 统一Portal架构（推荐）
```
统一Portal (Port 3000)
├── Dashboard (监控面板)
├── Fragments (代码片段)
├── Surf (AI桌面)
└── Resources (资源管理)
```

**优点：**
- 单一入口，统一认证
- 共享导航和布局
- 更好的用户体验

**实施步骤：**
1. 创建Portal应用作为主入口
2. 将Dashboard、Fragments、Surf作为子路由集成
3. 实现统一的侧边栏导航
4. 共享认证状态

### 方案B: 微前端架构
使用iframe或微前端框架集成现有应用。

**优点：**
- 保持各应用独立性
- 渐进式迁移

**缺点：**
- 技术复杂度高
- 性能开销大

## 推荐实施方案A

### 新的目录结构
```
/infra/portal/                    # 统一入口
├── app/
│   ├── page.tsx                 # 主页
│   ├── dashboard/               # 监控面板
│   ├── fragments/               # 代码片段
│   ├── surf/                    # AI桌面
│   └── resources/               # 资源管理
├── components/
│   ├── Layout.tsx               # 统一布局
│   └── Navigation.tsx           # 统一导航
└── lib/
    └── auth.ts                  # 统一认证
```

### 导航结构
```
Portal
├── 🏠 首页
├── 📊 Dashboard (监控)
│   ├── 资源管理
│   ├── 系统监控
│   └── MCP服务
├── 📝 Fragments (代码片段)
└── 🖥️ Surf (AI桌面)
```
