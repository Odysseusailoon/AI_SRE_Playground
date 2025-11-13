#!/usr/bin/env python3
from openai import OpenAI

# 直接填入你的 API Key
API_KEY = "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"
BASE_URL = "https://openrouter.ai/api/v1"
MODEL = "openai/gpt-4o-mini"

print("🧪 测试 GPT-4o-mini 连接...")

try:
    client = OpenAI(api_key=API_KEY, base_url=BASE_URL, timeout=30)
    response = client.chat.completions.create(
        model=MODEL,
        messages=[{"role": "user", "content": "Say 'OK' if you receive this."}],
        max_tokens=10
    )
    print(f"\n✅ 成功！响应: {response.choices[0].message.content}")
    print(f"Tokens: {response.usage.total_tokens}")
except Exception as e:
    print(f"\n❌ 失败: {e}")

