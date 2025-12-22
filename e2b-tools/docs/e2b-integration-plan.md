# E2B与Infra功能集成方案

## 🎯 集成概述

E2B和Dashboard可以与infra中的现有功能深度集成，创建一个统一的管理和监控平台。

## 📊 当前架构分析

### 现有服务（运行中）

```
当前运行的服务:
├── API (Nomad)          - Port 3000 - E2B主API服务
├── Orchestrator (Nomad) - Port 5008 - VM编排服务
├── PostgreSQL (Docker)  - Port 5432 - 数据库
└── Redis (可选)         - Port 6379 - 缓存

可用但未启用:
├── Grafana             - Port 3001 - 监控面板
├── Loki                - 日志聚合
├── Traefik             - API网关
└── Client Proxy        - Port 3002 - 代理服务
```

## 🔗 集成方案

### 方案1: Dashboard集成 ⭐⭐⭐⭐⭐（强烈推荐）

#### 1.1 Grafana监控面板

**集成目标**: 统一的VM监控和管理界面

**架构**:
```
Grafana Dashboard
    ├── E2B API Metrics (通过Prometheus)
    ├── VM状态监控 (Sandbox列表、状态、资源)
    ├── 系统资源监控 (CPU、内存、磁盘)
    ├── 日志查看 (通过Loki)
    └── 告警配置
```

**实现步骤**:

```bash
# 1. 启动Grafana (在e2b Docker Compose中已配置)
cd /home/primihub/pcloud/infra/e2b/config
docker-compose -f docker-compose.e2b.yml up -d grafana

# 2. 配置数据源
# 访问 http://localhost:3001 (admin/admin)
# 添加数据源:
#   - Prometheus: http://localhost:9090
#   - Loki: http://localhost:3100
#   - PostgreSQL: postgres:5432/e2b

# 3. 导入E2B仪表板
# 使用预制的dashboard JSON或创建自定义dashboard
```

**Dashboard功能**:
- 📊 **VM概览**: 总数、运行中、已停止
- 📈 **资源使用**: CPU、内存、网络IO
- 📝 **日志流**: 实时查看VM日志
- ⚠️ **告警**: VM失败、资源超限
- 🔍 **查询**: SQL查询VM数据

---

### 方案2: Web管理界面 ⭐⭐⭐⭐

#### 2.1 自定义Web Dashboard

**集成目标**: 专门的E2B管理界面

**技术栈**:
- **前端**: React / Vue / Next.js
- **后端**: E2B API (已有，port 3000)
- **实时通信**: WebSocket / SSE
- **认证**: JWT / OAuth

**目录结构**:
```
infra/
├── e2b-dashboard/              # 新建
│   ├── frontend/
│   │   ├── src/
│   │   │   ├── components/
│   │   │   │   ├── VMList.jsx          # VM列表
│   │   │   │   ├── VMDetail.jsx        # VM详情
│   │   │   │   ├── CreateVM.jsx        # 创建VM
│   │   │   │   ├── Logs.jsx            # 日志查看
│   │   │   │   └── Metrics.jsx         # 指标图表
│   │   │   ├── pages/
│   │   │   │   ├── Dashboard.jsx       # 主页
│   │   │   │   ├── VMs.jsx             # VM管理
│   │   │   │   └── Settings.jsx        # 设置
│   │   │   └── App.jsx
│   │   └── package.json
│   ├── docker-compose.dashboard.yml
│   └── README.md
```

**实现示例** (React):

```javascript
// frontend/src/components/VMList.jsx
import React, { useState, useEffect } from 'react';
import axios from 'axios';

const VMList = () => {
  const [vms, setVMs] = useState([]);
  const API_URL = 'http://localhost:3000';
  const API_KEY = process.env.REACT_APP_E2B_API_KEY;

  useEffect(() => {
    const fetchVMs = async () => {
      try {
        const response = await axios.get(`${API_URL}/sandboxes`, {
          headers: { 'X-API-Key': API_KEY }
        });
        setVMs(response.data);
      } catch (error) {
        console.error('Failed to fetch VMs:', error);
      }
    };

    fetchVMs();
    const interval = setInterval(fetchVMs, 5000); // 每5秒刷新
    return () => clearInterval(interval);
  }, []);

  return (
    <div className="vm-list">
      <h2>虚拟机列表</h2>
      <table>
        <thead>
          <tr>
            <th>ID</th>
            <th>状态</th>
            <th>CPU</th>
            <th>内存</th>
            <th>启动时间</th>
            <th>操作</th>
          </tr>
        </thead>
        <tbody>
          {vms.map(vm => (
            <tr key={vm.sandboxID}>
              <td>{vm.sandboxID.substring(0, 8)}...</td>
              <td>
                <span className={`status ${vm.state}`}>
                  {vm.state}
                </span>
              </td>
              <td>{vm.cpuCount} 核</td>
              <td>{vm.memoryMB} MB</td>
              <td>{new Date(vm.startedAt).toLocaleString()}</td>
              <td>
                <button onClick={() => viewVM(vm.sandboxID)}>详情</button>
                <button onClick={() => deleteVM(vm.sandboxID)}>删除</button>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
};

export default VMList;
```

---

### 方案3: CLI与服务集成 ⭐⭐⭐⭐⭐

#### 3.1 增强e2b CLI工具

**集成目标**: CLI工具直接调用infra服务

**当前**: CLI通过HTTP API与E2B通信
**增强**: 
- 直接连接到orchestrator gRPC
- 访问PostgreSQL查询数据
- 调用envd执行命令

**实现**:

```bash
# e2b-tools/cli/e2b-advanced
#!/bin/bash

# 直接连接orchestrator
grpcurl -plaintext \
  -d "{\"config\":{\"template_id\":\"$TEMPLATE_ID\"}}" \
  localhost:5008 \
  sandbox.SandboxService/Create

# 查询数据库
psql -h localhost -U postgres -d postgres -c "
  SELECT sandbox_id, state, started_at 
  FROM sandboxes 
  WHERE state = 'running'
"

# 执行VM内命令（通过envd）
grpcurl -plaintext \
  -d "{\"process\":{\"cmd\":\"$CMD\"}}" \
  10.11.13.173:49983 \
  process.Process/Start
```

---

### 方案4: 统一API网关 ⭐⭐⭐⭐

#### 4.1 Traefik集成

**集成目标**: 统一的API入口和路由

**架构**:
```
Traefik (Port 80/443)
    ├── /api/*        → E2B API (3000)
    ├── /orchestrator → Orchestrator (5008)
    ├── /grafana      → Grafana (3001)
    ├── /dashboard    → Web Dashboard (3003)
    └── /docs         → API文档
```

**配置** (traefik.yml):
```yaml
entryPoints:
  web:
    address: ":80"
  websecure:
    address: ":443"

providers:
  docker:
    exposedByDefault: false

api:
  dashboard: true
  insecure: true

http:
  routers:
    e2b-api:
      rule: "PathPrefix(`/api`)"
      service: e2b-api
      entryPoints:
        - web
    
    grafana:
      rule: "PathPrefix(`/grafana`)"
      service: grafana
      entryPoints:
        - web
  
  services:
    e2b-api:
      loadBalancer:
        servers:
          - url: "http://localhost:3000"
    
    grafana:
      loadBalancer:
        servers:
          - url: "http://localhost:3001"
```

---

## 🚀 推荐实施路径

### 阶段1: 基础监控（1-2天）✅ 立即可做

**目标**: 快速建立监控能力

**步骤**:
1. 启动Grafana
2. 配置Prometheus数据源
3. 创建基础Dashboard
4. 设置基本告警

**命令**:
```bash
# 1. 启动Grafana
cd /home/primihub/pcloud/infra/e2b/config
docker-compose -f docker-compose.e2b.yml up -d grafana

# 2. 访问Grafana
open http://localhost:3001
# 默认账号: admin/admin

# 3. 添加PostgreSQL数据源
# Settings → Data Sources → Add PostgreSQL
# Host: postgres:5432
# Database: postgres
# User: postgres
```

**预期效果**:
- ✅ 可视化VM状态
- ✅ 查看历史数据
- ✅ 基本告警通知

---

### 阶段2: Web界面（1-2周）

**目标**: 提供用户友好的管理界面

**步骤**:
1. 搭建前端项目框架
2. 实现VM列表和详情页
3. 添加创建/删除功能
4. 集成日志查看
5. 添加认证和权限

**技术选择**:
- **快速原型**: Streamlit (Python)
- **生产级**: React + TypeScript
- **全栈框架**: Next.js

---

### 阶段3: 深度集成（2-4周）

**目标**: 完整的企业级平台

**功能**:
- 多租户支持
- RBAC权限控制
- 审计日志
- 成本分析
- 自动扩缩容
- API限流和配额

---

## 💻 快速启动示例

### 启动Grafana监控

```bash
# 1. 进入e2b配置目录
cd /home/primihub/pcloud/infra/e2b/config

# 2. 确保Grafana配置存在
grep -A 10 "grafana:" docker-compose.e2b.yml

# 3. 启动Grafana
docker-compose -f docker-compose.e2b.yml up -d grafana

# 4. 检查状态
docker-compose -f docker-compose.e2b.yml ps grafana

# 5. 查看日志
docker-compose -f docker-compose.e2b.yml logs -f grafana

# 6. 访问界面
echo "Grafana URL: http://localhost:3001"
echo "默认账号: admin / admin"
```

### 创建简单的Web Dashboard (Python/Streamlit)

```bash
# 1. 创建dashboard目录
mkdir -p /home/primihub/pcloud/infra/e2b-dashboard
cd /home/primihub/pcloud/infra/e2b-dashboard

# 2. 创建requirements.txt
cat > requirements.txt <<EOF
streamlit
requests
pandas
plotly
EOF

# 3. 创建app.py
cat > app.py <<'EOFPY'
import streamlit as st
import requests
import pandas as pd
from datetime import datetime

# 配置
API_URL = "http://localhost:3000"
API_KEY = "e2b_53ae1fed82754c17ad8077fbc8bcdd90"

st.set_page_config(page_title="E2B Dashboard", layout="wide")

# 标题
st.title("🚀 E2B虚拟机管理面板")

# 侧边栏
with st.sidebar:
    st.header("操作")
    if st.button("🔄 刷新"):
        st.rerun()
    
    if st.button("➕ 创建VM"):
        # TODO: 创建VM逻辑
        st.success("VM创建功能开发中")

# 获取VM列表
@st.cache_data(ttl=5)
def get_vms():
    try:
        response = requests.get(
            f"{API_URL}/sandboxes",
            headers={"X-API-Key": API_KEY}
        )
        return response.json()
    except Exception as e:
        st.error(f"获取VM列表失败: {e}")
        return []

vms = get_vms()

# 显示统计
col1, col2, col3, col4 = st.columns(4)
with col1:
    st.metric("总VM数", len(vms))
with col2:
    running = sum(1 for vm in vms if vm.get('state') == 'running')
    st.metric("运行中", running)
with col3:
    total_cpu = sum(vm.get('cpuCount', 0) for vm in vms)
    st.metric("总CPU", f"{total_cpu} 核")
with col4:
    total_mem = sum(vm.get('memoryMB', 0) for vm in vms)
    st.metric("总内存", f"{total_mem} MB")

# VM列表
st.header("📋 虚拟机列表")
if vms:
    df = pd.DataFrame(vms)
    st.dataframe(
        df[['sandboxID', 'state', 'cpuCount', 'memoryMB', 'startedAt']],
        use_container_width=True
    )
else:
    st.info("当前没有运行中的VM")

# 详细信息
st.header("📊 资源使用趋势")
# TODO: 添加图表
st.info("图表功能开发中")
EOFPY

# 4. 安装依赖
pip install -r requirements.txt

# 5. 运行dashboard
streamlit run app.py --server.port 8501
```

---

## 📈 集成效果预览

### Grafana Dashboard
```
┌─────────────────────────────────────────────────────────┐
│  E2B Firecracker VM 监控面板                            │
├─────────────────────────────────────────────────────────┤
│  [总VM: 5] [运行中: 3] [CPU: 10核] [内存: 2560MB]      │
├─────────────────────────────────────────────────────────┤
│  ┌───────────────┐  ┌───────────────┐  ┌─────────────┐ │
│  │  VM创建趋势   │  │  资源使用率   │  │  失败率     │ │
│  │   📈          │  │   📊          │  │   ⚠️        │ │
│  └───────────────┘  └───────────────┘  └─────────────┘ │
├─────────────────────────────────────────────────────────┤
│  VM列表                                                 │
│  ┌────────┬────────┬──────┬────────┬─────────────────┐ │
│  │ ID     │ 状态   │ CPU  │ 内存   │ 启动时间        │ │
│  ├────────┼────────┼──────┼────────┼─────────────────┤ │
│  │ abc... │ 运行中 │ 2核  │ 512MB  │ 12-22 03:26    │ │
│  └────────┴────────┴──────┴────────┴─────────────────┘ │
└─────────────────────────────────────────────────────────┘
```

---

## 🎯 总结

### 集成优势

1. **统一管理**: 一个界面管理所有VM
2. **可视化**: 直观的图表和指标
3. **自动化**: 告警、扩缩容
4. **易用性**: Web界面 vs 命令行
5. **监控**: 实时掌握系统状态

### 推荐组合

**短期（立即实施）**:
- ✅ Grafana + PostgreSQL数据源
- ✅ e2b CLI增强

**中期（1-2周）**:
- ✅ Streamlit简易Dashboard
- ✅ Traefik API网关

**长期（1个月+）**:
- ✅ React专业Dashboard
- ✅ 完整的监控和告警系统

---

**文档创建时间**: 2025-12-22
**状态**: 待实施
**优先级**: 高
