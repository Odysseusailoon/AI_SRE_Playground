#!/usr/bin/env python3
import requests

# 两台机器配置
SERVICE_IP = "106.14.183.16"           # work1: service_api (8099端口)
MODEL_ECHO_IP = "14.103.221.215"       # 模型机: vLLM(8080端口) + Echo(8098端口)

payload = {
    "problems": [
        {"problem_id": "container_kill-analysis-1", "runs": 2, "max_steps": 12}
    ],
    "concurrency": 1,
    "chat": {
        "model": "/data0/xj/lunwen/verl/save_model/new_model_save_vllm-GPTQ-Int4-detail",
        "base_url": f"http://{MODEL_ECHO_IP}:18200/v1",  
        "temperature": 0.2,
        "top_p": 1.0,
        "max_tokens": 512
    },
    "echo": {
        "url": f"http://{MODEL_ECHO_IP}:18201"  # Echo通过18201端口转发到内网8081，原本是8098，现在变成8081
    }
}

resp = requests.post(
    f"http://{SERVICE_IP}:8099/echo/jobs",
    json=payload,
    timeout=60,
)
resp.raise_for_status()
print(resp.json())
