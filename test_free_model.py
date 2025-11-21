#!/usr/bin/env python3
"""
测试免费模型 qwen/qwen3-4b:free 是否能正常工作
"""

import os
from openai import OpenAI
from dotenv import load_dotenv

# 加载环境变量
load_dotenv()

def test_free_model():
    """测试免费模型"""
    
    api_key = os.getenv("OPENROUTER_API_KEY")
    base_url = os.getenv("OPENROUTER_BASE_URL", "https://openrouter.ai/api/v1")
    model = os.getenv("OPENROUTER_MODEL", "qwen/qwen3-4b:free")
    
    print("=" * 60)
    print("测试免费模型配置")
    print("=" * 60)
    print(f"API Key: {api_key[:20]}...{api_key[-10:]}" if api_key else "未配置")
    print(f"Base URL: {base_url}")
    print(f"Model: {model}")
    print("=" * 60)
    print()
    
    if not api_key:
        print("❌ 错误: OPENROUTER_API_KEY 未配置")
        return False
    
    try:
        # 创建客户端
        client = OpenAI(
            api_key=api_key,
            base_url=base_url
        )
        
        # 测试简单问答
        print("📤 发送测试请求...")
        messages = [
            {"role": "system", "content": "You are a helpful assistant."},
            {"role": "user", "content": "Please respond with exactly: 'Hello, I am working!'"}
        ]
        
        print(f"请求消息: {messages[-1]['content']}")
        print()
        
        response = client.chat.completions.create(
            model=model,
            messages=messages,
            max_tokens=100,
            temperature=0.1
        )
        
        # 输出结果
        result = response.choices[0].message.content
        print("=" * 60)
        print("✅ 测试成功！模型响应:")
        print("=" * 60)
        print(result)
        print("=" * 60)
        print()
        
        # 显示使用信息
        if hasattr(response, 'usage'):
            print(f"Token 使用: {response.usage.total_tokens} tokens")
            print(f"  - 输入: {response.usage.prompt_tokens}")
            print(f"  - 输出: {response.usage.completion_tokens}")
        
        print()
        print("🎉 免费模型工作正常！可以用于测试流程。")
        return True
        
    except Exception as e:
        print("=" * 60)
        print("❌ 测试失败！")
        print("=" * 60)
        print(f"错误类型: {type(e).__name__}")
        print(f"错误信息: {str(e)}")
        print()
        return False

if __name__ == "__main__":
    success = test_free_model()
    exit(0 if success else 1)

