# 会话分组功能文档

## 📅 实现时间
**日期**: 2026-02-04

---

## 🎯 功能概述

会话分组功能按时间自动将会话分类，帮助用户更好地组织和查找历史会话。

---

## ✨ 主要特性

### 1. 自动时间分组
会话按最后更新时间自动分为5个组：
- **今天**: 今日更新的会话
- **昨天**: 昨日更新的会话
- **本周**: 本周内更新的会话（周一至今）
- **本月**: 本月内更新的会话
- **更早**: 更早之前的会话

### 2. 可折叠分组
- 每个分组都可以独立折叠/展开
- 点击分组标题切换显示状态
- 折叠状态在会话期间保持

### 3. 分组统计
- 每个分组标题显示会话数量
- 格式：`今天 (3)` 表示今天有3个会话

---

## 🔧 技术实现

### 组件修改

**文件**: `components/session-list.tsx`

#### 1. 新增导入
```typescript
import { isToday, isYesterday, isThisWeek, isThisMonth } from 'date-fns'
import { ChevronDown, ChevronRight } from 'lucide-react'
```

#### 2. 新增状态
```typescript
const [collapsedGroups, setCollapsedGroups] = useState<Set<string>>(new Set())
```

#### 3. 分组函数
```typescript
const groupSessionsByDate = (sessions: ChatSession[]) => {
  const groups: { [key: string]: ChatSession[] } = {
    '今天': [],
    '昨天': [],
    '本周': [],
    '本月': [],
    '更早': []
  }

  sessions.forEach((session) => {
    const date = new Date(session.updatedAt)
    if (isToday(date)) {
      groups['今天'].push(session)
    } else if (isYesterday(date)) {
      groups['昨天'].push(session)
    } else if (isThisWeek(date, { weekStartsOn: 1 })) {
      groups['本周'].push(session)
    } else if (isThisMonth(date)) {
      groups['本月'].push(session)
    } else {
      groups['更早'].push(session)
    }
  })

  // 过滤掉空分组
  return Object.entries(groups).filter(([_, sessions]) => sessions.length > 0)
}
```

#### 4. 折叠切换函数
```typescript
const toggleGroup = (groupName: string) => {
  setCollapsedGroups((prev) => {
    const newSet = new Set(prev)
    if (newSet.has(groupName)) {
      newSet.delete(groupName)
    } else {
      newSet.add(groupName)
    }
    return newSet
  })
}
```

#### 5. UI 渲染
```typescript
{groupedSessions.map(([groupName, groupSessions]) => (
  <div key={groupName} className="space-y-1">
    {/* 分组标题 */}
    <div
      className="flex items-center gap-2 px-2 py-1 cursor-pointer"
      onClick={() => toggleGroup(groupName)}
    >
      {collapsedGroups.has(groupName) ? (
        <ChevronRight className="h-4 w-4" />
      ) : (
        <ChevronDown className="h-4 w-4" />
      )}
      <span className="text-xs font-semibold">
        {groupName} ({groupSessions.length})
      </span>
    </div>

    {/* 会话列表 */}
    {!collapsedGroups.has(groupName) && groupSessions.map((session) => (
      // ... 会话项渲染
    ))}
  </div>
))}
```

---

## 📝 使用说明

### 查看分组会话

1. **打开会话历史侧边栏**
   - 点击导航栏的 History 图标

2. **查看分组**
   - 会话自动按时间分组显示
   - 每个分组显示标题和会话数量

3. **折叠/展开分组**
   - 点击分组标题切换显示状态
   - 折叠的分组显示右箭头 (→)
   - 展开的分组显示下箭头 (↓)

---

## 🎨 分组规则

### 时间判断逻辑

| 分组 | 判断条件 | 示例 |
|------|---------|------|
| 今天 | 会话更新日期是今天 | 2026-02-04 (当前日期) |
| 昨天 | 会话更新日期是昨天 | 2026-02-03 |
| 本周 | 会话更新在本周内（周一开始） | 2026-02-01 至今 |
| 本月 | 会话更新在本月内 | 2026-02-01 至今 |
| 更早 | 更早之前的会话 | 2026-01-31 及之前 |

### 分组优先级
按从上到下的顺序判断，满足第一个条件即分组：
1. 今天
2. 昨天
3. 本周
4. 本月
5. 更早

---

## ✨ 功能优势

### 1. 时间导向
- 快速找到最近的会话
- 清晰的时间层次结构

### 2. 减少滚动
- 折叠不常用的分组
- 专注于当前需要的会话

### 3. 自动管理
- 无需手动分类
- 会话自动归入正确分组

### 4. 视觉清晰
- 分组标题醒目
- 会话数量一目了然

---

## 📊 总结

### 完成的工作
- ✅ 实现5级时间分组（今天、昨天、本周、本月、更早）
- ✅ 添加可折叠分组功能
- ✅ 显示每个分组的会话数量
- ✅ 使用 date-fns 进行时间判断
- ✅ 保持折叠状态

### 技术特点
- 使用 date-fns 标准时间函数
- Set 数据结构管理折叠状态
- 自动过滤空分组
- 响应式交互设计

---

**实现时间**: 2026-02-04
**状态**: ✅ 完成
**测试**: ✅ 通过

