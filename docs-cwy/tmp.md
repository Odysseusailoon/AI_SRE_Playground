# LLM 调用统计增强设计文档

## 1. 背景与问题

### 当前实现的不足：
1. **Token 统计不准确**：使用 tiktoken 本地估算，而非 API 返回的精确值
2. **缺少响应时间**：无法知道每次 LLM 调用花费多长时间
3. **性能分析困难**：无法区分 LLM 调用时间 vs 环境执行时间
4. **统计信息缺失**：没有平均响应时间、最快/最慢调用等统计

### 目标：
实现与示例代码类似的精确统计，记录每次 LLM 调用的：
- 响应时间（秒）
- 精确的 token 使用（从 API 返回）
- 模型名称
- 时间戳

## 2. 设计方案

### 2.1 数据结构变更

**在 trace 中为 assistant 消息增加 metadata：**

```json
{
    "trace": [
        {
            "role": "assistant",
            "content": "LLM 的回复内容",
            "metadata": {
                "response_time": 1.234,           // LLM 响应时间（秒）
                "prompt_tokens": 150,              // 输入 token（API 返回）
                "completion_tokens": 200,          // 输出 token（API 返回）
                "total_tokens": 350,               // 总 token
                "model": "anthropic/claude-3.5-sonnet",  // 模型名称
                "timestamp": "2025-10-31T16:00:00Z"  // 时间戳
            }
        },
        {
            "role": "env",
            "content": "环境响应"
        }
    ]
}
```

**在 results 中增加汇总统计：**

```json
{
    "results": {
        "success": false,
        "TTA": 4.417,                    // 总任务时间
        "steps": 5,
        
        // 当前的估算值（保留兼容性）
        "in_tokens": 42,                 
        "out_tokens": 655,
        
        // 新增：精确值
        "api_prompt_tokens": 150,        // API 返回的输入 token
        "api_completion_tokens": 200,    // API 返回的输出 token
        "api_total_tokens": 350,         // API 返回的总 token
        
        // 新增：时间统计
        "total_llm_time": 6.5,           // 所有 LLM 调用总耗时
        "avg_llm_time": 1.3,             // 平均每次 LLM 调用耗时
        "min_llm_time": 0.8,             // 最快的 LLM 调用
        "max_llm_time": 2.1,             // 最慢的 LLM 调用
        "env_execution_time": 0.9        // TTA - total_llm_time = 环境执行时间
    }
}
```

### 2.2 需要修改的文件

#### 文件 1: `clients/utils/llm.py` 
**修改 OpenRouterClient.inference() 方法**

```python
def inference(self, payload: list[dict[str, str]]) -> tuple[list[str], dict]:
    """
    Returns:
        (responses, usage_info)
        - responses: list[str] - LLM 的回复内容
        - usage_info: dict - 包含 response_time, tokens, model 等
    """
    import time
    
    # ... 缓存检查 ...
    
    start_time = time.time()
    
    response = client.chat.completions.create(...)
    
    elapsed = time.time() - start_time
    
    # 提取 usage 信息
    usage_info = {
        "response_time": elapsed,
        "prompt_tokens": response.usage.prompt_tokens if response.usage else 0,
        "completion_tokens": response.usage.completion_tokens if response.usage else 0,
        "total_tokens": response.usage.total_tokens if response.usage else 0,
        "model": self.model,
        "timestamp": time.time()
    }
    
    contents = [c.message.content for c in response.choices]
    return contents, usage_info
```

**同步修改 run() 方法：**
```python
def run(self, payload: list[dict[str, str]]) -> tuple[list[str], dict]:
    response, usage_info = self.inference(payload)
    if self.cache is not None:
        self.cache.add_to_cache(payload, response)
        self.cache.save_cache()
    return response, usage_info
```

#### 文件 2: `clients/openrouter.py`
**修改 OpenRouterAgent.get_action() 方法**

```python
async def get_action(self, input) -> str:
    self.history.append({"role": "user", "content": input})
    
    try:
        trimmed_history = trim_history_to_token_limit(self.history)
        response, usage_info = self.llm.run(trimmed_history)  # ← 接收两个值
        
        print(f"===== Agent (OpenRouter - {self.model}) ====\n{response[0]}")
        print(f"⏱️  响应时间: {usage_info['response_time']:.3f}s | Tokens: {usage_info['total_tokens']}")
        
        # 保存到 history 并附加 metadata
        self.history.append({
            "role": "assistant", 
            "content": response[0],
            "metadata": usage_info  # ← 新增元数据
        })
        
        return response[0]
    except Exception as e:
        # ... 错误处理 ...
```

#### 文件 3: `aiopslab/session.py`
**修改 SessionItem 数据模型（如果使用 Pydantic）：**

```python
class SessionItem(BaseModel):
    role: str
    content: str
    metadata: Optional[dict] = None  # ← 新增可选字段
```

#### 文件 4: `aiopslab/orchestrator/evaluators/quantitative.py`
**新增函数提取 API token 统计：**

```python
def api_tokens_from_trace(trace: list[SessionItem]) -> dict:
    """从 trace 的 metadata 中提取 API 返回的精确 token 统计"""
    total_prompt = 0
    total_completion = 0
    total_llm_time = 0.0
    response_times = []
    
    for item in trace:
        if item.role == "assistant" and hasattr(item, 'metadata') and item.metadata:
            meta = item.metadata
            total_prompt += meta.get('prompt_tokens', 0)
            total_completion += meta.get('completion_tokens', 0)
            
            if 'response_time' in meta:
                rt = meta['response_time']
                total_llm_time += rt
                response_times.append(rt)
    
    return {
        "api_prompt_tokens": total_prompt,
        "api_completion_tokens": total_completion,
        "api_total_tokens": total_prompt + total_completion,
        "total_llm_time": round(total_llm_time, 3),
        "avg_llm_time": round(total_llm_time / len(response_times), 3) if response_times else 0,
        "min_llm_time": round(min(response_times), 3) if response_times else 0,
        "max_llm_time": round(max(response_times), 3) if response_times else 0,
        "num_llm_calls": len(response_times)
    }
```

#### 文件 5: `aiopslab/orchestrator/tasks/base.py`
**在 evaluate() 中添加新统计：**

```python
def evaluate(self, trace: list[SessionItem]):
    self.add_result("steps", num_steps_taken(trace))
    
    # 保留原有的估算值（兼容性）
    self.add_result("in_tokens", in_tokens(trace))
    self.add_result("out_tokens", out_tokens(trace))
    
    # 新增：API 精确值
    api_stats = api_tokens_from_trace(trace)
    for key, value in api_stats.items():
        self.add_result(key, value)
    
    # 计算环境执行时间
    if api_stats['total_llm_time'] > 0:
        tta = self.session.end_time - self.session.start_time
        self.add_result("env_execution_time", round(tta - api_stats['total_llm_time'], 3))
```

### 2.3 向后兼容性

**保留原有的 tiktoken 估算：**
- `in_tokens` / `out_tokens` 继续存在
- 新增 `api_*` 前缀的精确值
- 如果 API 没有返回 usage（某些模型），metadata 为 None，使用估算值

## 3. 预期效果

### 修改前：
```json
"results": {
    "TTA": 4.417,
    "steps": 5,
    "in_tokens": 42,    // tiktoken 估算
    "out_tokens": 655   // tiktoken 估算
}
```

### 修改后：
```json
"results": {
    "TTA": 4.417,
    "steps": 5,
    
    // 保留估算值（兼容）
    "in_tokens": 42,
    "out_tokens": 655,
    
    // API 精确值
    "api_prompt_tokens": 150,
    "api_completion_tokens": 200,
    "api_total_tokens": 350,
    
    // 时间分析
    "total_llm_time": 3.5,        // LLM 调用总耗时
    "avg_llm_time": 0.7,          // 平均每次 0.7 秒
    "min_llm_time": 0.5,
    "max_llm_time": 1.2,
    "env_execution_time": 0.917   // 环境执行耗时
}
```

### trace 中的详细记录：
```json
"trace": [
    {
        "role": "assistant",
        "content": "...",
        "metadata": {
            "response_time": 1.234,
            "prompt_tokens": 150,
            "completion_tokens": 200,
            "total_tokens": 350,
            "model": "anthropic/claude-3.5-sonnet",
            "timestamp": 1761898426.5
        }
    }
]
```

## 4. 实现步骤

1. ✅ 写设计文档
2. ✅ 修改 `clients/utils/llm.py` - OpenRouterClient.inference() 返回 (response, usage_info)
3. ✅ 修改 `clients/openrouter.py` - OpenRouterAgent.get_action() 接收并保存 metadata
4. ✅ 修改 `aiopslab/session.py` - SessionItem 添加 metadata 字段
5. ✅ 修改 `aiopslab/orchestrator/evaluators/quantitative.py` - 新增 api_tokens_from_trace()
6. ✅ 修改 `aiopslab/orchestrator/tasks/base.py` - 在 evaluate() 中调用新统计
7. ⏳ 测试验证

## 4.1 代码修改摘要

### 修改的文件：
- `clients/utils/llm.py` (OpenRouterClient)
- `clients/openrouter.py` (OpenRouterAgent)
- `aiopslab/session.py` (SessionItem 数据模型)
- `aiopslab/orchestrator/evaluators/quantitative.py` (新增统计函数)
- `aiopslab/orchestrator/tasks/base.py` (调用新统计)

### 关键改动：
1. OpenRouterClient.inference() 现在返回 `tuple[list[str], dict | None]`
2. metadata 包含: response_time, prompt_tokens, completion_tokens, total_tokens, model, timestamp
3. 缓存命中时 metadata 为 None（没有 API 调用）
4. results 中新增 8 个字段：api_*_tokens, *_llm_time, num_llm_calls, env_execution_time

## 5. 测试验证

**测试命令：**
```bash
cd /home/ecs-user/projects/AI_SRE_Playground-echo
export PYTHONPATH=$PWD:$PYTHONPATH
python clients/openrouter.py --problem-ids container_kill-analysis-1 --max-steps 5
```

**验证点：**
1. JSON 结果文件包含 `api_prompt_tokens` 等新字段
2. trace 中 assistant 消息有 `metadata` 字段
3. 统计值合理（response_time > 0, tokens > 0）
4. 向后兼容（原有的 `in_tokens`/`out_tokens` 仍存在）

## 6. 注意事项

1. **缓存处理**：从缓存读取的响应没有 usage 信息，metadata 设为 None
2. **错误处理**：API 调用失败时，metadata 也应该记录（response_time 仍有效）
3. **多模型支持**：其他 Client（DeepSeek, Qwen 等）也需要同步修改
4. **性能影响**：time.time() 调用开销极小，可忽略

---

**文档编写完成，开始实施修改。**

