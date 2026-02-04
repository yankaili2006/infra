# 会话导出功能文档

## 📅 实现时间
**日期**: 2026-02-04

---

## 🎯 功能概述

会话导出功能允许用户将聊天会话导出为 Markdown 或 JSON 格式，方便备份、分享和数据分析。

---

## ✨ 主要特性

### 1. 导出格式支持
- **Markdown (.md)**: 人类可读的格式，适合文档和分享
- **JSON (.json)**: 结构化数据格式，适合程序处理和数据分析

### 2. 导出内容
- 会话标题
- 创建时间和更新时间
- 消息数量
- 使用的模板和模型
- 完整的对话历史（用户和助手消息）
- 代码片段（如果有）

### 3. 用户界面
- 导出按钮位于会话列表项的操作区域
- 点击后弹出格式选择对话框
- 支持一键下载

---

## 🔧 技术实现

### 组件修改

**文件**: `components/session-list.tsx`

#### 1. 新增导入
```typescript
import { Download } from 'lucide-react'
```

#### 2. 新增状态
```typescript
const [exportDialogOpen, setExportDialogOpen] = useState(false)
```

#### 3. 导出函数

**exportAsMarkdown**: 导出为 Markdown 格式
```typescript
const exportAsMarkdown = async () => {
  // 1. 获取完整会话数据
  const response = await fetch(`/api/sessions/${selectedSession.id}`)
  const data = await response.json()

  // 2. 格式化为 Markdown
  let markdown = `# ${session.title}\n\n`
  markdown += `**创建时间**: ${new Date(session.createdAt).toLocaleString('zh-CN')}\n`
  // ... 添加元数据和消息

  // 3. 创建下载
  const blob = new Blob([markdown], { type: 'text/markdown' })
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = `${session.title}.md`
  a.click()
}
```

**exportAsJSON**: 导出为 JSON 格式
```typescript
const exportAsJSON = async () => {
  // 1. 获取完整会话数据
  const response = await fetch(`/api/sessions/${selectedSession.id}`)
  const data = await response.json()

  // 2. 格式化为 JSON
  const json = JSON.stringify(session, null, 2)

  // 3. 创建下载
  const blob = new Blob([json], { type: 'application/json' })
  // ... 触发下载
}
```

#### 4. UI 组件

**导出按钮** (添加到会话列表项的操作区域):
```typescript
<Button
  variant="ghost"
  size="icon"
  className="h-7 w-7"
  onClick={(e) => openExportDialog(session, e)}
>
  <Download className="h-3 w-3" />
</Button>
```

**导出对话框**:
```typescript
<AlertDialog open={exportDialogOpen} onOpenChange={setExportDialogOpen}>
  <AlertDialogContent>
    <AlertDialogHeader>
      <AlertDialogTitle>导出会话</AlertDialogTitle>
      <AlertDialogDescription>选择导出格式：</AlertDialogDescription>
    </AlertDialogHeader>
    <div className="flex flex-col gap-2 py-4">
      <Button variant="outline" onClick={exportAsMarkdown}>
        <Download className="h-4 w-4 mr-2" />
        导出为 Markdown (.md)
      </Button>
      <Button variant="outline" onClick={exportAsJSON}>
        <Download className="h-4 w-4 mr-2" />
        导出为 JSON (.json)
      </Button>
    </div>
  </AlertDialogContent>
</AlertDialog>
```

---

## 📝 使用说明

### 导出会话步骤

1. **打开会话历史侧边栏**
   - 点击导航栏的 History 图标

2. **选择要导出的会话**
   - 鼠标悬停在会话项上
   - 会显示操作按钮（导出、编辑、删除）

3. **点击导出按钮**
   - 点击下载图标按钮
   - 弹出格式选择对话框

4. **选择导出格式**
   - 点击 "导出为 Markdown" 或 "导出为 JSON"
   - 文件将自动下载到浏览器默认下载目录

---

## 📄 导出格式示例

### Markdown 格式示例

\`\`\`markdown
# 测试会话

**创建时间**: 2026/2/4 12:47:10
**更新时间**: 2026/2/4 12:47:22
**消息数量**: 2
**模板**: auto
**模型**: deepseek-chat

---

## 用户 (2026/2/4 12:47:10)

你好，这是第一条测试消息

## 助手 (2026/2/4 12:47:15)

你好！我是 AI 助手，很高兴为您服务。
\`\`\`

### JSON 格式示例

\`\`\`json
{
  "id": "session_1770180430029_rt3iqdjuz",
  "title": "测试会话",
  "createdAt": "2026-02-04T04:47:10.029Z",
  "updatedAt": "2026-02-04T04:47:22.246Z",
  "messageCount": 2,
  "template": "auto",
  "model": "deepseek-chat",
  "messages": [
    {
      "role": "user",
      "content": "你好，这是第一条测试消息",
      "timestamp": "2026-02-04T04:47:10.029Z"
    },
    {
      "role": "assistant",
      "content": "你好！我是 AI 助手，很高兴为您服务。",
      "timestamp": "2026-02-04T04:47:15.123Z"
    }
  ]
}
\`\`\`

---

## ✨ 功能优势

### 1. 数据备份
- 定期导出会话，防止数据丢失
- 支持离线保存和查看

### 2. 内容分享
- Markdown 格式易于分享和阅读
- 可直接在文档工具中使用

### 3. 数据分析
- JSON 格式便于程序处理
- 支持批量分析和统计

### 4. 迁移支持
- 标准格式便于数据迁移
- 可导入其他系统

---

## 📊 总结

### 完成的工作
- ✅ 实现 Markdown 导出功能
- ✅ 实现 JSON 导出功能
- ✅ 添加导出按钮和对话框
- ✅ 文件名自动处理（移除特殊字符）
- ✅ 完整的会话数据导出

### 技术特点
- 客户端实现，无需额外 API
- 使用 Blob API 创建下载
- 自动清理 URL 对象
- 支持中文文件名

---

**实现时间**: 2026-02-04
**状态**: ✅ 完成
**测试**: ✅ 通过
