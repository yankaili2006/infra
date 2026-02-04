# 会话分组模式选择器功能文档

## 📅 实现时间
**日期**: 2026-02-04

---

## 🎯 功能概述

分组模式选择器允许用户在三种不同的分组方式之间切换，以不同的视角组织和查看会话历史。

---

## ✨ 主要特性

### 1. 三种分组模式
- **按时间**: 按最后更新时间分组（今天、昨天、本周、本月、更早）
- **按模板**: 按使用的模板分组（auto、code-interpreter-v1、nextjs-developer等）
- **按模型**: 按使用的AI模型分组（deepseek-chat、claude-3等）

### 2. 一键切换
- 点击按钮即可切换分组模式
- 当前选中的模式高亮显示
- 切换后立即重新分组显示

### 3. 保持状态
- 分组模式在会话期间保持
- 折叠状态独立于分组模式

---

## 🔧 技术实现

### 组件修改

**文件**: `components/session-list.tsx`

#### 1. 新增状态
```typescript
const [groupMode, setGroupMode] = useState<'date' | 'template' | 'model'>('date')
```

#### 2. 分组函数

**按模板分组**:
```typescript
const groupSessionsByTemplate = (sessions: ChatSession[]) => {
  const groups: { [key: string]: ChatSession[] } = {}
  sessions.forEach((session) => {
    const template = session.template || 'auto'
    if (!groups[template]) {
      groups[template] = []
    }
    groups[template].push(session)
  })
  return Object.entries(groups).filter(([_, sessions]) => sessions.length > 0)
}
```

**按模型分组**:
```typescript
const groupSessionsByModel = (sessions: ChatSession[]) => {
  const groups: { [key: string]: ChatSession[] } = {}
  sessions.forEach((session) => {
    const model = session.model || 'unknown'
    if (!groups[model]) {
      groups[model] = []
    }
    groups[model].push(session)
  })
  return Object.entries(groups).filter(([_, sessions]) => sessions.length > 0)
}
```

#### 3. 动态分组选择
```typescript
const groupedSessions =
  groupMode === 'date' ? groupSessionsByDate(filteredSessions) :
  groupMode === 'template' ? groupSessionsByTemplate(filteredSessions) :
  groupSessionsByModel(filteredSessions)
```

#### 4. UI 选择器
```typescript
<div className="px-4 py-2 border-b">
  <div className="flex gap-1 p-1 bg-muted rounded-lg">
    <Button
      variant={groupMode === 'date' ? 'default' : 'ghost'}
      size="sm"
      onClick={() => setGroupMode('date')}
    >
      按时间
    </Button>
    <Button
      variant={groupMode === 'template' ? 'default' : 'ghost'}
      size="sm"
      onClick={() => setGroupMode('template')}
    >
      按模板
    </Button>
    <Button
      variant={groupMode === 'model' ? 'default' : 'ghost'}
      size="sm"
      onClick={() => setGroupMode('model')}
    >
      按模型
    </Button>
  </div>
</div>
```

---

## 📝 使用说明

### 切换分组模式

1. **打开会话历史侧边栏**
2. **查看分组模式选择器**（位于搜索框下方）
3. **点击按钮切换模式**：
   - 按时间：查看最近的会话
   - 按模板：查看不同项目类型的会话
   - 按模型：查看使用不同AI模型的会话

---

## 📊 总结

### 完成的工作
- ✅ 实现三种分组模式（时间、模板、模型）
- ✅ 添加分组模式选择器UI
- ✅ 动态切换分组逻辑
- ✅ 保持一致的用户体验

### 技术特点
- 统一的分组接口
- 动态分组切换
- 响应式UI设计

---

**实现时间**: 2026-02-04
**状态**: ✅ 完成
**测试**: ✅ 通过

