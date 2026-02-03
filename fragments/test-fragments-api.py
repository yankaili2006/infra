#!/usr/bin/env python3
"""
Fragments API 测试工具
测试创建简单页面并验证 preview 功能
"""

import requests
import json
import time
import sys

BASE_URL = "http://localhost:3001"

def test_fragments_preview():
    """测试 Fragments 的 preview 功能"""

    print("=" * 60)
    print("Fragments Preview 功能测试")
    print("=" * 60)

    # 1. 测试健康检查
    print("\n[1/4] 测试服务健康状态...")
    try:
        response = requests.get(f"{BASE_URL}/api/health", timeout=5)
        print(f"✓ 服务状态: {response.status_code}")
        if response.status_code == 200:
            print(f"  响应: {response.json()}")
    except Exception as e:
        print(f"✗ 健康检查失败: {e}")
        return False

    # 2. 创建一个简单的 Python 代码片段
    print("\n[2/4] 创建 Python 代码片段...")
    code = """
print("Hello from Fragments!")
print("Testing preview functionality")

# 简单计算
result = 2 + 2
print(f"2 + 2 = {result}")
"""

    payload = {
        "code": code,
        "language": "python"
    }

    try:
        response = requests.post(
            f"{BASE_URL}/api/sandbox",
            json=payload,
            timeout=30
        )
        print(f"✓ 创建请求状态: {response.status_code}")

        if response.status_code == 200:
            result = response.json()
            print(f"  Sandbox ID: {result.get('sandboxId', 'N/A')}")
            sandbox_id = result.get('sandboxId')
        else:
            print(f"✗ 创建失败: {response.text}")
            return False

    except Exception as e:
        print(f"✗ 创建代码片段失败: {e}")
        return False

    # 3. 等待并获取执行结果
    print("\n[3/4] 等待代码执行...")
    time.sleep(3)

    try:
        response = requests.get(
            f"{BASE_URL}/api/sandbox/{sandbox_id}",
            timeout=10
        )
        print(f"✓ 获取结果状态: {response.status_code}")

        if response.status_code == 200:
            result = response.json()
            print(f"  执行状态: {result.get('status', 'N/A')}")
            print(f"  输出预览:")
            output = result.get('output', '')
            for line in output.split('\n')[:10]:  # 只显示前10行
                print(f"    {line}")
        else:
            print(f"  响应: {response.text}")

    except Exception as e:
        print(f"✗ 获取结果失败: {e}")

    # 4. 测试 HTML preview
    print("\n[4/4] 测试 HTML preview...")
    html_code = """
<!DOCTYPE html>
<html>
<head>
    <title>Fragments Test</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            padding: 20px;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
        }
        .container {
            max-width: 600px;
            margin: 0 auto;
            background: rgba(255,255,255,0.1);
            padding: 30px;
            border-radius: 10px;
        }
        h1 { margin-top: 0; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Fragments Preview Test</h1>
        <p>This is a simple HTML page to test the preview functionality.</p>
        <p>Current time: <span id="time"></span></p>
    </div>
    <script>
        document.getElementById('time').textContent = new Date().toLocaleString();
    </script>
</body>
</html>
"""

    payload = {
        "code": html_code,
        "language": "html"
    }

    try:
        response = requests.post(
            f"{BASE_URL}/api/sandbox",
            json=payload,
            timeout=30
        )
        print(f"✓ HTML 创建状态: {response.status_code}")

        if response.status_code == 200:
            result = response.json()
            sandbox_id = result.get('sandboxId')
            preview_url = result.get('previewUrl', f"{BASE_URL}/preview/{sandbox_id}")
            print(f"  Sandbox ID: {sandbox_id}")
            print(f"  Preview URL: {preview_url}")

            # 尝试访问 preview
            time.sleep(2)
            preview_response = requests.get(preview_url, timeout=10)
            print(f"✓ Preview 访问状态: {preview_response.status_code}")
            if preview_response.status_code == 200:
                print(f"  Preview 内容长度: {len(preview_response.text)} 字符")
                print(f"  包含预期内容: {'Fragments Preview Test' in preview_response.text}")
        else:
            print(f"✗ HTML 创建失败: {response.text}")

    except Exception as e:
        print(f"✗ HTML preview 测试失败: {e}")

    print("\n" + "=" * 60)
    print("测试完成")
    print("=" * 60)
    return True

if __name__ == "__main__":
    success = test_fragments_preview()
    sys.exit(0 if success else 1)
