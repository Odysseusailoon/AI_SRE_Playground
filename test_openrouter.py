#!/usr/bin/env python3
"""
简单的 OpenRouter API 连接测试脚本
"""

import os
from pathlib import Path
from openai import OpenAI

# 加载 .env 文件
try:
    from dotenv import load_dotenv
    env_path = Path(__file__).parent / '.env'
    load_dotenv(env_path)
    print(f"✅ 已加载 .env 文件: {env_path}")
except ImportError:
    print("⚠️  python-dotenv 未安装，直接使用环境变量")

# 读取配置
OPENROUTER_API_KEY = os.getenv("OPENROUTER_API_KEY")
OPENROUTER_BASE_URL = os.getenv("OPENROUTER_BASE_URL", "https://openrouter.ai/api/v1")
OPENROUTER_MODEL = os.getenv("OPENROUTER_MODEL", "meta-llama/llama-3.1-8b-instruct:free")

print("\n" + "━" * 60)
print("📋 配置信息")
print("━" * 60)
print(f"API Key: {OPENROUTER_API_KEY[:20]}..." if OPENROUTER_API_KEY else "❌ API Key 未设置")
print(f"Base URL: {OPENROUTER_BASE_URL}")
print(f"Model: {OPENROUTER_MODEL}")
print("━" * 60)

if not OPENROUTER_API_KEY:
    print("\n❌ 错误: OPENROUTER_API_KEY 未设置")
    exit(1)

# 创建客户端
try:
    client = OpenAI(
        api_key=OPENROUTER_API_KEY,
        base_url=OPENROUTER_BASE_URL,
    )
    print("\n✅ OpenAI 客户端创建成功")
except Exception as e:
    print(f"\n❌ 创建客户端失败: {e}")
    exit(1)

# 测试简单的 API 调用
print("\n" + "━" * 60)
print("🧪 测试 API 连接...")
print("━" * 60)

try:
    response = client.chat.completions.create(
        model=OPENROUTER_MODEL,
        messages=[
            {"role": "user", "content": "Hello! Just testing the connection. Reply with 'OK' if you receive this."}
        ],
        max_tokens=50,
        temperature=0.7,
    )
    
    print("\n✅ API 调用成功！")
    print("\n📨 响应内容:")
    print("━" * 60)
    print(response.choices[0].message.content)
    print("━" * 60)
    
    # 打印详细信息
    print(f"\n📊 响应详情:")
    print(f"  Model: {response.model}")
    print(f"  Finish Reason: {response.choices[0].finish_reason}")
    print(f"  Total Tokens: {response.usage.total_tokens if response.usage else 'N/A'}")
    
except Exception as e:
    print(f"\n❌ API 调用失败: {e}")
    print(f"\n错误类型: {type(e).__name__}")
    import traceback
    print("\n详细错误:")
    traceback.print_exc()
    exit(1)

print("\n" + "━" * 60)
print("✅ 测试完成！")
print("━" * 60)

