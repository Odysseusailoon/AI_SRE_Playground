# AIOpsLab 并行执行分析报告

## 1. 当前系统设计分析

### 1.1 代码执行流程

从 `clients/gpt.py` 看：
```python
for pid in selected:
    agent = Agent()
    orchestrator = Orchestrator()
    orchestrator.register_agent(agent, name="gpt-w-shell")
    problem_desc, instructs, apis = orchestrator.init_problem(pid)
    agent.init_context(problem_desc, instructs, apis)
    asyncio.run(orchestrator.start_problem(max_steps=args.max_steps))
```

**关键发现：**
- 使用 `for` 循环**顺序执行**每个问题
- 每个问题创建新的 `Orchestrator` 实例
- 使用 `asyncio.run()` 运行，但每个问题是**串行**的

### 1.2 资源配置分析

**每个问题执行时：**
1. `prob.app.delete()` - 删除 Helm release（`Helm.uninstall()`）
2. `prob.app.deploy()` - 重新部署 Helm release（`Helm.install()`）
3. 使用固定的 namespace（从 metadata JSON 读取）

**Namespace 分配：**
- `test-social-network` - Social Network 应用
- `test-hotel-reservation` - Hotel Reservation 应用
- `observe` - Prometheus 监控（共享）
- `openebs` - 存储组件（共享）

### 1.3 全局配置问题

**问题点：**
1. `config.yml` 是全局文件，所有实例共享
2. `get_kube_context()` 从全局 `config.yml` 读取
3. `observer/__init__.py` 在模块导入时就加载 kubeconfig
4. `KubeCtl` 和 `Helm` 都使用全局的 `get_kube_context()`

## 2. 并行执行的限制

### 2.1 不支持的情况

❌ **同一应用的不同任务**：
- 两个任务都使用 Social Network → 都使用 `test-social-network` namespace
- 会互相删除对方的部署
- **无法并行**

❌ **全局配置冲突**：
- 所有 `Orchestrator` 实例共享同一个 `config.yml`
- 所有实例使用同一个 `kube_context`
- 无法为不同任务指定不同集群

### 2.2 支持的情况

✅ **不同应用的任务**：
- 任务1：Social Network (`test-social-network`)
- 任务2：Hotel Reservation (`test-hotel-reservation`)
- 使用不同的 namespace，**理论上可以并行**

✅ **不同集群的任务**：
- 如果修改代码支持动态 `kube_context`，可以在不同集群并行

## 3. README 中的说明

**检查结果：**
- README 中**没有明确提到并行执行**
- 没有并行执行的示例或说明
- 所有示例都是单个任务运行

**结论：** 系统设计为**顺序执行**，没有内置并行支持。

## 4. 如何修改以支持并行

### 方案 A：修改代码支持动态 kube_context（推荐）

**需要修改的文件：**

1. **`aiopslab/config.py`**：
   - 修改 `get_kube_context()` 支持传入参数
   - 或支持从环境变量读取

2. **`aiopslab/orchestrator/orchestrator.py`**：
   - `Orchestrator.__init__()` 添加 `kube_context` 参数
   - 传递给 `KubeCtl` 和 `Helm`

3. **`aiopslab/service/kubectl.py`**：
   - `KubeCtl.__init__()` 支持传入 `kube_context`
   - 不使用全局的 `get_kube_context()`

4. **`aiopslab/service/helm.py`**：
   - 所有方法支持传入 `kube_context` 参数

5. **`aiopslab/observer/__init__.py`**：
   - 延迟加载 kubeconfig，而不是在模块导入时加载
   - 支持传入 `kube_context`

### 方案 B：使用不同的工作目录（简单但不够优雅）

- 每个任务使用独立的工作目录
- 每个目录有自己的 `config.yml`
- 修改 `paths.py` 支持动态 BASE_DIR

### 方案 C：使用不同的 namespace（最简单）

- 修改问题定义，为每个任务生成唯一的 namespace
- 例如：`test-social-network-{session_id}`
- 需要修改 metadata 或问题初始化逻辑

## 5. 推荐修改方案

### 最小改动方案（方案 C + 部分 A）

1. **修改 `Orchestrator` 支持动态 namespace**：
   ```python
   def __init__(self, results_dir=None, problem_variant_mode=None, namespace_suffix=None):
       # 如果提供了 suffix，修改应用的 namespace
   ```

2. **修改 `Application` 类支持 namespace 后缀**：
   ```python
   def __init__(self, config_file, namespace_suffix=None):
       # namespace = metadata["Namespace"] + (f"-{namespace_suffix}" if namespace_suffix else "")
   ```

3. **修改 `clients/gpt.py` 支持并行**：
   ```python
   import asyncio
   import concurrent.futures
   
   async def run_problem(pid, max_steps):
       orchestrator = Orchestrator(namespace_suffix=pid)
       # ... 运行任务
   
   # 并行执行
   tasks = [run_problem(pid, args.max_steps) for pid in selected]
   await asyncio.gather(*tasks)
   ```

## 6. 总结

**当前状态：**
- ❌ 系统**不支持**并行执行
- ❌ README 中**没有**并行执行的说明
- ✅ 代码结构**可以修改**以支持并行

**主要障碍：**
1. 全局 `config.yml` 和 `kube_context`
2. `observer` 模块在导入时加载全局 kubeconfig
3. 同一应用的任务使用相同的 namespace

**推荐方案：**
- 短期：使用不同应用的任务在不同集群并行（已实现）
- 长期：修改代码支持动态 namespace 和 kube_context

