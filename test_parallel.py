#!/usr/bin/env python3
"""测试并行执行功能"""
import requests

# 两台机器配置
SERVICE_IP = "106.14.183.16"           # work1: service_api (8099端口)
MODEL_ECHO_IP = "14.103.221.215"       # 模型机: vLLM(8080端口) + Echo(8089端口)

# 并行测试配置：2个不同任务，2个并发
payload = {
    "problems": [
        {"problem_id": "container_kill-analysis-1", "runs": 2, "max_steps": 12},
        {"problem_id": "container_kill-detection-1", "runs": 2, "max_steps": 12},
    ],
    "concurrency": 2,  # ← 2个任务并行，但每个任务的runs串行执行
    "chat": {
        "model": "/data0/xj/lunwen/verl/save_model/new_model_save_vllm-GPTQ-Int4-detail",
        "base_url": f"http://{MODEL_ECHO_IP}:18200/v1",  
        "temperature": 0.2,
        "top_p": 1.0,
        "max_tokens": 512
    },
    "echo": {
        "url": f"http://{MODEL_ECHO_IP}:18209"  # Echo通过18209端口转发到内网8089
    }
}

print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
print("🚀 提交并行测试任务")
print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
print(f"\n任务配置:")
print(f"  - 任务1: {payload['problems'][0]['problem_id']} (runs={payload['problems'][0]['runs']})")
print(f"  - 任务2: {payload['problems'][1]['problem_id']} (runs={payload['problems'][1]['runs']})")
print(f"  - 并发数: {payload['concurrency']}")
print(f"  - 预期行为: 使用 kind 和 kind1 两个集群并行执行\n")

try:
    resp = requests.post(
        f"http://{SERVICE_IP}:8099/echo/jobs",
        json=payload,
        timeout=60,
    )
    resp.raise_for_status()
    result = resp.json()
    
    print(f"✅ 任务已提交！Job ID: {result['job_id']}")
    print(f"\n查询状态命令:")
    print(f"  curl -s http://{SERVICE_IP}:8099/echo/jobs/{result['job_id']} | python3 -m json.tool")
    print(f"\n查看日志（机器A）:")
    print(f"  journalctl -u aiopslab-service -f | grep -E 'cluster|Acquired|Released'")
    print("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    
except requests.exceptions.RequestException as e:
    print(f"❌ 请求失败: {e}")
    if hasattr(e, 'response') and e.response is not None:
        print(f"响应内容: {e.response.text}")

