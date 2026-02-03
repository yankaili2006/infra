# Fragments 模板自动选择 - 快速开始

## 🚀 立即使用

### 1. 访问界面
打开浏览器访问：http://localhost:3001

### 2. 选择Auto模式
在界面顶部的模板选择器中，选择 **"Auto"** 选项

### 3. 开始对话
直接输入你的任务，系统会自动选择合适的模板：

#### 示例任务

**Python数据分析：**
```
帮我分析这个CSV文件，计算平均值和标准差
```
→ 自动使用 code-interpreter-v1

**前端开发：**
```
创建一个登录表单组件，包含用户名和密码输入框
```
→ 自动使用 nextjs-developer-dev

**桌面操作：**
```
打开Firefox浏览器并访问github.com
```
→ 自动使用 desktop-template

**Linux命令：**
```
查找当前目录下所有的.txt文件
```
→ 自动使用 base

## 📊 模板选择规则

| 关键词 | 选择的模板 |
|--------|-----------|
| python, pandas, 数据分析 | code-interpreter-v1 |
| react, nextjs, 前端, 组件 | nextjs-developer-dev |
| browser, desktop, 浏览器, 桌面 | desktop-template |
| bash, command, 命令, 文件 | base |

## 🔍 查看选择结果

打开终端查看日志：
```bash
tail -f /tmp/fragments.log | grep "Auto-selected"
```

你会看到类似输出：
```
🤖 Auto-selected template: code-interpreter-v1 (Python data analyst)
```

## ⚙️ 手动选择模板

如果需要，你仍然可以在界面中手动选择特定模板，系统会使用你选择的模板而不是自动选择。

## 📚 更多信息

- 详细文档：`/mnt/data1/pcloud/infra/fragments/TEMPLATE_AUTO_SELECTION.md`
- 演示脚本：`/tmp/demo_template_selection.sh`
