# kind1 测试卡住问题分析

**时间**: 2025-11-12  
**问题**: kind1 测试在 "All pods ready" 后停止输出，进程挂起

---

## 📊 问题现象

### 1. 测试状态
- ✅ 测试进程正在运行 (PID: 65221)
- ✅ 进程已运行 13+ 分钟
- ✅ CPU 使用率: 2.2% (进程活动中)
- ❌ 日志停在 `[15:04:40] All pods in namespace 'test-social-network' are ready.`
- ❌ 之后没有任何新输出

### 2. 预期行为
根据正常日志，在 "All pods ready" 之后应该：
```
== Fault Injection ==
== Start Workload ==
===== Agent (GPT-4o-mini) ====
```

### 3. 实际日志
```
[15:04:40] All pods in namespace 'test-social-network' are ready.


(卡住，无新输出)
```

---

## 🔍 根本原因分析

### 问题定位

通过代码追踪，发现程序在 `Orchestrator.start_problem()` 的第一步卡住了：

**代码流程**:
1. `clients/gpt.py` → `orchestrator.start_problem(max_steps=5)`
2. `orchestrator.py` → `action = await self.ask_agent(action_instr)`  
3. `gpt.py` → `response = self.llm.run(trimmed_history)`
4. `llm.py` (GPTClient) → **在这里卡住！**

### 配置问题

**`clients/utils/llm.py` 第 81-83 行：**
```python
api_key = os.getenv("OPENROUTER_API_KEY") or os.getenv("OPENAI_API_KEY")
base_url = os.getenv("OPENROUTER_BASE_URL", "https://api.openai.com/v1")
model = os.getenv("OPENROUTER_MODEL", "gpt-4-turbo-2024-04-09")
```

**当前 `.env` 配置：**
```bash
OPENROUTER_API_KEY=sk-or-v1-xxx...  # ✅ 已设置
OPENROUTER_MODEL=openai/gpt-4o-mini  # ✅ 已设置
# OPENROUTER_BASE_URL=???             # ❌ 未设置！
```

**问题**:
- `OPENROUTER_BASE_URL` **未设置**
- 程序使用默认值 `https://api.openai.com/v1`
- 用 OpenRouter 的 API key 访问 OpenAI 的服务
- OpenAI API 拒绝无效的 key，导致请求挂起或超时

### 为什么会挂起这么久？

虽然代码中设置了 `timeout=60` 秒，但：
1. **TCP 连接超时** 可能比 API timeout 更长
2. **代理设置** 可能导致连接挂起而不是快速失败
3. **OpenAI 的防护机制** 可能对无效请求进行延迟响应

---

## ✅ 解决方案

### 方案 1: 修复 OpenRouter 配置（推荐）

在 `.env` 文件中添加正确的 BASE_URL：

```bash
# 添加这一行
OPENROUTER_BASE_URL=https://openrouter.ai/api/v1
```

**操作步骤**:
```bash
cd /home/ecs-user/projects/AI_SRE_Playground-echo

# 添加正确的 BASE_URL
echo 'OPENROUTER_BASE_URL=https://openrouter.ai/api/v1' >> .env

# 终止当前测试
kill $(cat logs/kind1_test/gpt_eval_kind1.pid)

# 重新运行测试
./test_kind1_single.sh
```

---

### 方案 2: 使用国内 API (阿里云 DashScope)

修改 `.env` 文件，启用阿里云配置：

```bash
# 注释掉 OpenRouter
# OPENROUTER_API_KEY=xxx
# OPENROUTER_MODEL=xxx

# 启用阿里云 DashScope
API_SOURCE=dashscope
API_KEY=<你的DashScope API Key>
API_BASE=https://dashscope.aliyuncs.com/compatible-mode/v1
MODEL=qwen-plus
```

**优点**:
- 国内访问速度快
- 不需要代理
- 响应更稳定

---

### 方案 3: 修改代码使用 OpenRouterClient

如果不想修改 `.env`，可以修改 `clients/gpt.py`：

**修改前** (第 61 行):
```python
self.llm = GPTClient()
```

**修改后**:
```python
from clients.utils.llm import OpenRouterClient
self.llm = OpenRouterClient(model="openai/gpt-4o-mini")
```

`OpenRouterClient` 默认就配置了正确的 BASE_URL：
```python
base_url="https://openrouter.ai/api/v1"
```

---

## 🧪 验证步骤

### 1. 快速测试 API 连接

```python
# 测试脚本
cd /home/ecs-user/projects/AI_SRE_Playground-echo
python3 << 'EOF'
from dotenv import load_dotenv
load_dotenv()

from clients.utils.llm import GPTClient, OpenRouterClient
import os

print("配置信息:")
print(f"  OPENROUTER_API_KEY: {'已设置' if os.getenv('OPENROUTER_API_KEY') else '未设置'}")
print(f"  OPENROUTER_BASE_URL: {os.getenv('OPENROUTER_BASE_URL', '未设置（默认 api.openai.com）')}")
print(f"  OPENROUTER_MODEL: {os.getenv('OPENROUTER_MODEL', '未设置')}")

# 测试 API 调用
try:
    client = GPTClient()
    response = client.run([{"role": "user", "content": "Hello, say hi"}])
    print(f"\n✅ API 调用成功: {response}")
except Exception as e:
    print(f"\n❌ API 调用失败: {e}")
EOF
```

### 2. 完整测试流程

```bash
# 1. 修复配置
echo 'OPENROUTER_BASE_URL=https://openrouter.ai/api/v1' >> .env

# 2. 终止旧进程
kill $(cat logs/kind1_test/gpt_eval_kind1.pid)

# 3. 重新运行测试
./test_kind1_single.sh

# 4. 实时监控日志
tail -f logs/kind1_test/gpt_eval_kind1.log
```

---

## 📋 检查清单

在运行测试前，确保：

- [ ] `.env` 文件中设置了正确的 API 配置
- [ ] 如果使用 OpenRouter，设置了 `OPENROUTER_BASE_URL`
- [ ] 如果使用国内 API，设置了正确的 `API_SOURCE`
- [ ] kind1 集群健康（所有 pods Running）
- [ ] 网络代理配置正确（如果需要）

---

## 🔗 相关文件

- **LLM 客户端**: `clients/utils/llm.py`
- **Agent 实现**: `clients/gpt.py`
- **Orchestrator**: `aiopslab/orchestrator/orchestrator.py`
- **配置文件**: `.env`

---

## 📝 总结

**核心问题**: API 配置错误导致 LLM 调用挂起

**快速修复**: 
```bash
echo 'OPENROUTER_BASE_URL=https://openrouter.ai/api/v1' >> .env
kill $(cat logs/kind1_test/gpt_eval_kind1.pid)
./test_kind1_single.sh
```

**推荐方案**: 使用国内 API (DashScope/Qwen) 获得更好的性能和稳定性

---

**创建时间**: 2025-11-12 15:20  
**状态**: 已确认问题根因  
**优先级**: 🔴 高 (阻塞测试运行)

