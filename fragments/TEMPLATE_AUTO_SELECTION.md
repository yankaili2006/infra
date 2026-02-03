# Fragments 模板自动选择功能

## 功能概述

Fragments 现在支持基于用户任务类型的智能模板自动选择。系统会分析用户的对话内容，自动选择最合适的执行环境模板。

## 支持的模板

| 模板ID | 名称 | 适用场景 | 触发关键词 |
|--------|------|---------|-----------|
| `code-interpreter-v1` | Python数据分析 | Python编程、数据分析、可视化 | python, pandas, numpy, jupyter, 数据分析 |
| `nextjs-developer-dev` | Next.js开发 | 前端开发、React应用 | nextjs, react, frontend, 前端, 组件 |
| `desktop-template-000-0000-0000-000000000001` | 桌面环境 | GUI操作、浏览器自动化 | desktop, browser, gui, 桌面, 浏览器 |
| `base` | Linux基础环境 | Shell命令、文件操作 | bash, shell, command, 命令, 文件, 目录 |

## 使用方法

### 自动模板选择

用户只需要用自然语言描述任务，系统会自动选择合适的模板：

**示例 1 - Python数据分析：**
```
用户: "帮我分析这个CSV文件，使用pandas读取数据"
→ 系统自动选择: code-interpreter-v1
```

**示例 2 - 前端开发：**
```
用户: "创建一个React组件显示用户列表"
→ 系统自动选择: nextjs-developer-dev
```

**示例 3 - 桌面操作：**
```
用户: "打开浏览器访问google.com"
→ 系统自动选择: desktop-template-000-0000-0000-000000000001
```

**示例 4 - Linux命令：**
```
用户: "列出当前目录的所有文件"
→ 系统自动选择: base
```

### 手动指定模板

如果需要，用户仍然可以手动指定模板（通过API参数）。

## 技术实现

### 核心文件

1. **`lib/templates.ts`** - 模板定义
2. **`lib/template-selector.ts`** - 模板选择逻辑
3. **`app/api/chat/route.ts`** - Chat API集成

### 选择逻辑

系统使用关键词匹配算法：

1. 提取用户最后一条消息
2. 转换为小写进行匹配
3. 按优先级检查关键词：
   - Desktop环境（最高优先级）
   - Next.js开发
   - Python数据分析
   - Base Linux环境
4. 如果没有匹配，默认使用 `code-interpreter-v1`

### 日志输出

系统会在控制台输出选择信息：

```
🤖 Auto-selected template: code-interpreter-v1 (Python data analyst)
auto-selected: true
```

或

```
📌 Using requested template: nextjs-developer-dev
```

## 配置说明

### 添加新模板

1. 在 `lib/templates.ts` 中添加模板定义：

```typescript
'new-template-id': {
  name: 'Template Name',
  lib: ['dependency1', 'dependency2'],
  file: 'main.ext',
  instructions: 'Template description',
  port: 8080,
}
```

2. 在 `lib/template-selector.ts` 中添加关键词：

```typescript
const newTemplateKeywords = [
  'keyword1', 'keyword2', '关键词1', '关键词2'
]

// 添加检查逻辑
if (newTemplateKeywords.some(keyword => content.includes(keyword))) {
  return 'new-template-id'
}
```

### 调整优先级

在 `template-selector.ts` 中调整检查顺序来改变优先级。先检查的模板优先级更高。

## 监控和调试

### 查看日志

```bash
tail -f /tmp/fragments.log | grep -E "Auto-selected|template"
```

### 测试模板选择

```bash
curl -X POST "http://localhost:3001/api/chat" \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [{"role": "user", "content": "你的测试消息"}],
    "model": "gpt-4",
    "config": {"apiKey": "test"}
  }'
```

## 故障排查

### 问题：模板选择不正确

**解决方案：**
1. 检查关键词列表是否包含相关词汇
2. 查看日志确认实际选择的模板
3. 调整关键词或优先级

### 问题：服务启动失败

**解决方案：**
```bash
# 检查端口占用
lsof -i :3001

# 查看错误日志
tail -50 /tmp/fragments.log

# 重启服务
cd /mnt/data1/pcloud/infra/fragments
npm run dev
```

## 性能优化

- 关键词匹配使用简单的字符串包含检查，性能开销极小
- 默认模板选择在毫秒级完成
- 不影响后续代码生成的性能

## 未来改进

- [ ] 使用LLM进行更智能的意图识别
- [ ] 支持多模板组合使用
- [ ] 添加用户偏好记忆
- [ ] 支持自定义关键词配置

## 版本历史

- **v1.0** (2026-02-03) - 初始版本，支持4种模板自动选择
