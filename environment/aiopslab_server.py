#!/usr/bin/env python3
"""
环境服务器 - 基于AIOpsLab Orchestrator的重构版本
"""
import os
import sys
import subprocess
import time
import tempfile
from pathlib import Path
import argparse


# ========== 提前解析命令行参数 ==========
parser = argparse.ArgumentParser(description='AIOpsLab Environment Server')
parser.add_argument('--port', type=int, default=8002, help='Server port')
parser.add_argument('--host', type=str, default='127.0.0.1', help='Server host')
parser.add_argument('--cluster-name', type=str, default='kind', help='Kind cluster name')
parser.add_argument('--kind-config', type=str, default='/home/yangpei/work/aoi/AIOpsLab/kind/kind-config-x86.yaml', help='Kind config file path')
parser.add_argument('--auto-delete', action='store_true', help='Auto delete cluster on shutdown')

args = parser.parse_args()


# ========== 在导入AIOpsLab之前创建集群和生成kubeconfig ==========
def ensure_kind_cluster_and_kubeconfig(cluster_name: str, config_path: str):
    """确保Kind集群存在并生成kubeconfig"""
    print(f"🔧 Ensuring Kind cluster '{cluster_name}' and kubeconfig...")

    # 1. 检查kind命令是否可用
    try:
        subprocess.run(["kind", "--version"], capture_output=True, check=True)
    except (subprocess.CalledProcessError, FileNotFoundError):
        print("❌ 'kind' command not found. Please install kind first")
        sys.exit(1)

    # 2. 检查集群是否存在，不存在则创建
    try:
        result = subprocess.run(
            ["kind", "get", "clusters"],
            capture_output=True,
            text=True,
            check=False
        )
        existing_clusters = result.stdout.strip().split('\n') if result.stdout else []

        if cluster_name not in existing_clusters:
            print(f"📦 Creating Kind cluster '{cluster_name}' with config: {config_path}")

            # 创建集群
            create_cmd = [
                "kind", "create", "cluster",
                "--name", cluster_name,
                "--config", config_path
            ]

            result = subprocess.run(create_cmd, capture_output=True, text=True, check=False)
            if result.returncode != 0:
                print(f"❌ Failed to create kind cluster: {result.stderr}")
                sys.exit(1)

            print(f"✅ Kind cluster '{cluster_name}' created successfully")
            time.sleep(5)  # 等待集群稳定
        else:
            print(f"ℹ️  Kind cluster '{cluster_name}' already exists")

    except Exception as e:
        print(f"❌ Error checking/creating cluster: {e}")
        sys.exit(1)

    # 3. 导出kubeconfig到~/.kube/config（覆盖模式）
    try:
        # 确保~/.kube目录存在
        home_dir = os.path.expanduser("~")
        kube_dir = os.path.join(home_dir, ".kube")
        os.makedirs(kube_dir, exist_ok=True)

        kubeconfig_path = os.path.join(kube_dir, "config")

        # 导出kubeconfig（会覆盖已有的）
        export_cmd = [
            "kind", "export", "kubeconfig",
            "--name", cluster_name,
            "--kubeconfig", kubeconfig_path
        ]

        result = subprocess.run(export_cmd, capture_output=True, text=True, check=False)
        if result.returncode != 0:
            print(f"⚠️  Warning: Could not export kubeconfig to ~/.kube/config: {result.stderr}")
            # 尝试不指定路径，让kind自动处理
            export_default_cmd = ["kind", "export", "kubeconfig", "--name", cluster_name]
            subprocess.run(export_default_cmd, capture_output=True, text=True, check=False)

        # 设置环境变量
        os.environ['KUBECONFIG'] = kubeconfig_path

        print(f"✅ Kubeconfig exported to: {kubeconfig_path}")

        # 验证连接
        verify_cmd = ["kubectl", "cluster-info", "--kubeconfig", kubeconfig_path]
        result = subprocess.run(verify_cmd, capture_output=True, text=True, check=False)
        if result.returncode == 0:
            print(f"✅ Kubernetes cluster connection verified")
        else:
            print(f"⚠️  Warning: Cannot verify cluster connection")

    except Exception as e:
        print(f"❌ Error exporting kubeconfig: {e}")
        sys.exit(1)

# 立即执行集群创建和kubeconfig生成
ensure_kind_cluster_and_kubeconfig(args.cluster_name, args.kind_config)

# ========== 现在可以安全地导入AIOpsLab模块了 ==========
# 添加端口管理器
from utils.port_manager import PortManager

# 启动时清理所有端口转发
print("🧹 Initial cleanup of port forwards...")
PortManager.cleanup_all_port_forwards()

sys.path.insert(0, os.path.abspath('../AIOpsLab'))

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import Dict, Any, Optional, List, Union
import uvicorn
import inspect
import asyncio
import json
import uuid
from datetime import datetime
from contextlib import asynccontextmanager
import yaml
import shutil
import atexit

# 直接导入Orchestrator和相关模块
from aiopslab.orchestrator import Orchestrator
from aiopslab.session import Session
from aiopslab.utils.status import SubmissionStatus
from aiopslab.service.kubectl import KubeCtl


class ServerConfig:
    """服务器配置"""
    PORT = args.port
    HOST = args.host
    KIND_CLUSTER_NAME = args.cluster_name
    KIND_CONFIG_PATH = args.kind_config
    KUBECONFIG_PATH = os.path.expanduser("~/.kube/config")

    @classmethod
    def set_port(cls, port: int):
        cls.PORT = port

    @classmethod
    def set_host(cls, host: str):
        cls.HOST = host

    @classmethod
    def set_kind_cluster(cls, cluster_name: str):
        cls.KIND_CLUSTER_NAME = cluster_name

    @classmethod
    def set_kind_config(cls, config_path: str):
        cls.KIND_CONFIG_PATH = config_path


def create_kind_cluster():
    """创建与AIOpsLab一致的Kind集群（此时集群应该已经存在）"""
    cluster_name = ServerConfig.KIND_CLUSTER_NAME

    # 由于在导入前已经创建了集群，这里只需要验证
    try:
        result = subprocess.run(
            ["kind", "get", "clusters"],
            capture_output=True,
            text=True,
            check=False
        )
        existing_clusters = result.stdout.strip().split('\n') if result.stdout else []

        if cluster_name in existing_clusters:
            print(f"✅ Kind cluster '{cluster_name}' is ready")
            # 确保kubeconfig是最新的
            update_kubeconfig()
            return True
        else:
            print(f"❌ Kind cluster '{cluster_name}' not found")
            return False

    except FileNotFoundError:
        print("❌ 'kind' command not found")
        return False


# ========== 修改update_kubeconfig函数 ==========
def update_kubeconfig():
    """更新kubeconfig（主要是创建临时文件供内部使用）"""
    cluster_name = ServerConfig.KIND_CLUSTER_NAME

    # 1. 创建临时文件供服务器内部使用（如果需要的话）
    with tempfile.NamedTemporaryFile(mode='w', suffix='.yaml', delete=False) as f:
        kubeconfig_path = f.name
        ServerConfig.KUBECONFIG_PATH = kubeconfig_path

    try:
        # 2. 导出到临时文件
        cmd = [
            "kind", "export", "kubeconfig",
            "--name", cluster_name,
            "--kubeconfig", kubeconfig_path
        ]

        subprocess.run(cmd, capture_output=True, text=True, check=True)
        print(f"✅ Temporary kubeconfig exported to: {kubeconfig_path}")

        # 3. 同时确保~/.kube/config是最新的
        home_config = os.path.expanduser("~/.kube/config")
        if os.path.exists(home_config):
            # 再次导出以确保同步
            cmd_home = [
                "kind", "export", "kubeconfig",
                "--name", cluster_name,
                "--kubeconfig", home_config
            ]
            subprocess.run(cmd_home, capture_output=True, text=True, check=False)
            print(f"✅ Updated ~/.kube/config")

    except subprocess.CalledProcessError as e:
        print(f"❌ Failed to export kubeconfig: {e}")


def delete_kind_cluster():
    """删除Kind集群"""
    cluster_name = ServerConfig.KIND_CLUSTER_NAME

    try:
        print(f"🗑️ Deleting kind cluster '{cluster_name}'...")
        subprocess.run(
            ["kind", "delete", "cluster", "--name", cluster_name],
            capture_output=True,
            text=True,
            check=True
        )
        print(f"✅ Kind cluster '{cluster_name}' deleted")

        if ServerConfig.KUBECONFIG_PATH and os.path.exists(ServerConfig.KUBECONFIG_PATH):
            os.remove(ServerConfig.KUBECONFIG_PATH)
            print(f"✅ Cleaned up kubeconfig file")

    except subprocess.CalledProcessError as e:
        print(f"⚠️ Failed to delete cluster: {e.stderr}")


# Request/Response Models
class ActionRequest(BaseModel):
    """动作请求模型"""
    session_id: str
    action: str


class InitProblemRequest(BaseModel):
    """初始化问题请求"""
    problem_id: str
    reset_if_exists: bool = False


class ConnectSessionRequest(BaseModel):
    """连接会话请求"""
    session_id: str


class CreateCheckpointRequest(BaseModel):
    """创建检查点请求"""
    session_id: str
    checkpoint_name: Optional[str] = None


class RollbackRequest(BaseModel):
    """回滚请求"""
    session_id: str
    checkpoint_name: Optional[str] = None


class SubmitSolutionRequest(BaseModel):
    """提交解决方案请求"""
    session_id: str
    solution: Union[str, List, Dict]


class EnvironmentResponse(BaseModel):
    """环境响应模型"""
    success: bool
    data: Optional[Any] = None
    error: Optional[str] = None
    timestamp: str = datetime.now().isoformat()


class Checkpoint:
    """检查点管理"""
    def __init__(self, name: str, namespace: Optional[str] = None):
        self.name = name
        self.namespace = namespace
        self.created_at = datetime.now()
        self.state_file = None
        self.history_snapshot = []

    def save_state(self, kubectl, history: List):
        """保存集群状态"""
        self.history_snapshot = history.copy()

        if self.namespace:
            state_cmd = f"kubectl get all -o yaml -n {self.namespace}"
        else:
            state_cmd = "kubectl get all -o yaml --all-namespaces"

        try:
            result = kubectl.exec_command(state_cmd)
            if hasattr(result, 'stdout'):
                yaml_content = result.stdout.decode('utf-8') if isinstance(result.stdout, bytes) else result.stdout
            else:
                yaml_content = str(result)

            with tempfile.NamedTemporaryFile(mode='w', suffix='.yaml', delete=False) as f:
                f.write(yaml_content)
                self.state_file = f.name
            print(f"✅ Checkpoint '{self.name}' state saved to: {self.state_file}")
            return True

        except Exception as e:
            print(f"⚠️ Error saving checkpoint state: {e}")
            return False

    def restore_state(self, kubectl) -> bool:
        """恢复集群状态"""
        if not self.state_file or not os.path.exists(self.state_file):
            print(f"⚠️ Checkpoint file not found: {self.state_file}")
            return False

        restore_cmd = f"kubectl apply -f {self.state_file}"

        try:
            result = kubectl.exec_command(restore_cmd)
            print(f"✅ Checkpoint '{self.name}' restored successfully")
            return True

        except Exception as e:
            print(f"⚠️ Error restoring checkpoint state: {e}")
            return False

    def cleanup(self):
        """清理检查点文件"""
        if self.state_file and os.path.exists(self.state_file):
            try:
                os.remove(self.state_file)
                print(f"✅ Cleaned up checkpoint file for '{self.name}'")
            except Exception as e:
                print(f"⚠️ Failed to clean up checkpoint file: {e}")


class RemoteAgent:
    """远程代理 - 用于与Orchestrator交互"""
    def __init__(self, session_id: str):
        self.session_id = session_id
        self.actions_queue = []
        self.current_action = None

    async def get_action(self, env_input):
        """获取下一个动作"""
        if self.actions_queue:
            self.current_action = self.actions_queue.pop(0)
            return self.current_action
        else:
            # 等待新的动作
            await asyncio.sleep(0.1)
            return None

    def add_action(self, action: str):
        """添加动作到队列"""
        self.actions_queue.append(action)


class OrchestratorSession:
    """基于Orchestrator的会话管理"""
    def __init__(self, session_id: str, problem_id: str):
        self.session_id = session_id
        self.problem_id = problem_id
        self.orchestrator = Orchestrator()
        self.agent = RemoteAgent(session_id)
        self.orchestrator.register_agent(self.agent, name="remote")

        self.is_active = False
        self.created_at = datetime.now()
        self.last_action_time = None
        self.solution = None
        self.is_submitted = False
        self.submission_result = None
        self.evaluation_results = None
        self.checkpoints: Dict[str, Checkpoint] = {}
        self.checkpoint_order: List[str] = []

        # 任务信息
        self.task_desc = None
        self.instructions = None
        self.available_actions = None

        # 清理函数注册标志
        self.cleanup_registered = False

    def init_problem(self):
        """初始化问题"""
        print(f"\n🔧 Initializing problem: {self.problem_id}")

        # 使用PortManager清理端口转发
        print("🧹 Cleaning up port forwards before initialization...")
        PortManager.cleanup_prometheus_ports()  # 只清理Prometheus相关的
        time.sleep(1)  # 等待端口释放

        # 使用Orchestrator初始化问题
        self.task_desc, self.instructions, self.available_actions = \
            self.orchestrator.init_problem(self.problem_id)

        self.is_active = True
        self.cleanup_registered = True

        # 创建初始检查点
        try:
            self.create_checkpoint(self.orchestrator.kubectl, "initial")
        except Exception as e:
            print(f"⚠️ Failed to create initial checkpoint: {e}")

        return {
            "task_description": self.task_desc,
            "instructions": self.instructions,
            "available_actions": self.available_actions
        }

    async def execute_action(self, action: str):
        """执行动作"""
        print(f"\n🎯 Executing action in session {self.session_id[:8]}...")
        print(f"📝 Action: {action[:100]}...")

        try:
            # 检查端口状态（特别是对于get_metrics等需要Prometheus的操作）
            if "get_metrics" in action:
                print("📊 Checking Prometheus port availability...")
                # 确保32000端口可用
                if not PortManager.ensure_port_available(32000):
                    print("⚠️ Port 32000 is busy, attempting cleanup...")
                    PortManager.cleanup_prometheus_ports()
                    time.sleep(2)

            # 确保action格式正确
            if "```" not in action:
                formatted_action = f"```\n{action}\n```"
            else:
                formatted_action = action

            # 解析动作
            parsed = self.orchestrator.parser.parse(formatted_action)
            api_name = parsed["api_name"]
            args = parsed["args"]
            kwargs = parsed["kwargs"]

            print(f"🔧 API: {api_name}, Args: {args}, Kwargs: {kwargs}")

            # 记录到会话历史
            self.orchestrator.session.add({"role": "agent", "content": action})

            # 如果是submit，保存解决方案
            if api_name == "submit":
                self.solution = args[0] if len(args) == 1 else args
                self.is_submitted = True
                self.orchestrator.session.set_solution(self.solution)

            # 执行动作
            result = self.orchestrator.session.problem.perform_action(api_name, *args, **kwargs)

            # 处理结果
            if hasattr(result, "error"):
                result = str(result)
                print(f"⚠️ Action returned error: {result[:100]}...")
            else:
                print(f"✅ Action executed successfully")

            # 记录结果
            self.orchestrator.session.add({"role": "env", "content": str(result)})
            self.last_action_time = datetime.now()

            # 检查是否完成
            is_complete = (result == SubmissionStatus.VALID_SUBMISSION)

            if is_complete:
                print(f"🎉 Problem solved! Valid submission received.")
                self.submission_result = "VALID"

                # 执行评估
                try:
                    self.evaluation_results = self.orchestrator.session.problem.eval(
                        self.solution,
                        self.orchestrator.session.history,
                        self.orchestrator.session.get_duration()
                    )
                    print(f"📊 Evaluation results: {self.evaluation_results}")
                except Exception as e:
                    print(f"⚠️ Error during evaluation: {e}")
                    self.evaluation_results = {"error": str(e)}

            elif api_name == "submit" and result == SubmissionStatus.INVALID_SUBMISSION:
                self.submission_result = "INVALID"

            return {
                "result": str(result),
                "is_complete": is_complete,
                "session_id": self.session_id,
                "step_count": len(self.orchestrator.session.history) // 2,
                "is_submission": api_name == "submit",
                "evaluation": self.evaluation_results if is_complete else None
            }

        except Exception as e:
            print(f"❌ Error executing action: {e}")
            import traceback
            traceback.print_exc()

            # 在错误时尝试清理端口
            if "Connection refused" in str(e) or "port" in str(e).lower():
                print("🔧 Attempting to fix port issues...")
                PortManager.cleanup_prometheus_ports()

            error_msg = str(e)
            self.orchestrator.session.add({"role": "env", "content": f"Error: {error_msg}"})

            return {
                "result": f"Error: {error_msg}",
                "is_complete": False,
                "session_id": self.session_id,
                "error": True
            }

    def get_submit_format(self) -> Dict[str, Any]:
        """获取提交解决方案的格式要求"""
        if not self.is_active:
            raise Exception("Session is not active")

        # 获取submit API信息
        submit_api = None
        if self.available_actions:
            for api_name, api_desc in self.available_actions.items():
                if "submit" in api_name.lower():
                    submit_api = {
                        "api_name": api_name,
                        "description": api_desc,
                    }
                    break

        # 解析格式要求
        return {
            "session_id": self.session_id,
            "problem_id": self.problem_id,
            "submit_api": submit_api,
            "instructions": "Please submit your solution using the submit API when you have identified and resolved the problem.",
            "is_already_submitted": self.is_submitted,
            "previous_submission": self.solution if self.is_submitted else None
        }


    async def submit_solution(self, solution: Union[str, List, Dict]) -> Dict[str, Any]:
        """提交解决方案"""
        if not self.is_active:
            raise Exception("Session is not active")

        if self.is_submitted:
            return {
                "session_id": self.session_id,
                "status": "already_submitted",
                "previous_result": self.submission_result,
                "message": "A solution has already been submitted for this session."
            }

        print(f"\n📨 Submitting solution for session {self.session_id[:8]}...")
        print(f"📝 Solution: {solution}")

        try:
            # 保存解决方案
            self.solution = solution
            self.is_submitted = True
            self.orchestrator.session.set_solution(solution)

            # 添加到历史记录
            self.orchestrator.session.add({
                "role": "agent",
                "content": f"submit({json.dumps(solution) if isinstance(solution, (dict, list)) else repr(solution)})"
            })

            # 执行submit动作
            result = self.orchestrator.session.problem.perform_action("submit", solution)

            # 记录结果
            self.orchestrator.session.add({"role": "env", "content": str(result)})
            self.last_action_time = datetime.now()

            # 检查提交状态
            is_valid = (result == SubmissionStatus.VALID_SUBMISSION)

            if is_valid:
                print(f"🎉 Valid submission! Problem solved.")
                self.submission_result = "VALID"

                # 执行评估
                try:
                    eval_results = self.orchestrator.session.problem.eval(
                        self.solution,
                        self.orchestrator.session.history,
                        self.orchestrator.session.get_duration()
                    )
                    self.evaluation_results = eval_results
                    print(f"📊 Evaluation results: {eval_results}")
                except Exception as e:
                    print(f"⚠️ Error during evaluation: {e}")
                    self.evaluation_results = {"error": str(e)}

            else:
                print(f"❌ Invalid submission.")
                self.submission_result = "INVALID"

            return {
                "session_id": self.session_id,
                "status": "submitted",
                "is_valid": is_valid,
                "submission_result": self.submission_result,
                "solution": solution,
                "evaluation": self.evaluation_results,
                "message": str(result),
                "timestamp": self.last_action_time.isoformat()
            }

        except Exception as e:
            print(f"❌ Error submitting solution: {e}")
            import traceback
            traceback.print_exc()

            self.is_submitted = False
            self.submission_result = None

            return {
                "session_id": self.session_id,
                "status": "error",
                "error": str(e),
                "message": f"Failed to submit solution: {e}"
            }

    def create_checkpoint(self, kubectl=None, name: Optional[str] = None) -> str:
        """创建检查点"""
        if not kubectl:
            kubectl = self.orchestrator.kubectl

        if not name:
            name = f"checkpoint_{len(self.checkpoints) + 1}"

        if name in self.checkpoints:
            print(f"⚠️ Checkpoint '{name}' already exists, overwriting...")
            self.checkpoints[name].cleanup()
            self.checkpoint_order.remove(name)

        checkpoint = Checkpoint(name, getattr(self.orchestrator.session.problem, 'namespace', None))
        if checkpoint.save_state(kubectl, self.orchestrator.session.history):
            self.checkpoints[name] = checkpoint
            self.checkpoint_order.append(name)
            return name
        else:
            raise Exception(f"Failed to save checkpoint state for '{name}'")

    def rollback_to_checkpoint(self, kubectl=None, name: Optional[str] = None) -> bool:
        """回滚到指定检查点"""
        if not kubectl:
            kubectl = self.orchestrator.kubectl

        if not self.checkpoints:
            print(f"⚠️ No checkpoints available for rollback")
            return False

        if name is None:
            if self.checkpoint_order:
                name = self.checkpoint_order[-1]
            else:
                return False

        if name not in self.checkpoints:
            print(f"⚠️ Checkpoint '{name}' not found")
            return False

        checkpoint = self.checkpoints[name]
        success = checkpoint.restore_state(kubectl)

        if success:
            # 恢复历史记录
            self.orchestrator.session.history = checkpoint.history_snapshot.copy()

            # 移除后续检查点
            idx = self.checkpoint_order.index(name)
            for cp_name in self.checkpoint_order[idx + 1:]:
                self.checkpoints[cp_name].cleanup()
                del self.checkpoints[cp_name]
            self.checkpoint_order = self.checkpoint_order[:idx + 1]

            # 重置提交状态
            self.is_submitted = False
            self.submission_result = None
            self.solution = None

        return success

    def cleanup(self):
        """清理会话"""
        print(f"\n🧹 Cleaning up session {self.session_id[:8]}...")

        # 清理端口转发
        print("🔧 Cleaning up port forwards...")
        PortManager.cleanup_prometheus_ports()

        # 清理检查点
        for checkpoint in self.checkpoints.values():
            checkpoint.cleanup()
        self.checkpoints.clear()
        self.checkpoint_order.clear()

        # 使用Orchestrator的清理逻辑
        if self.cleanup_registered and self.orchestrator.session and self.orchestrator.session.problem:
            try:
                # 恢复故障
                self.orchestrator.session.problem.recover_fault()
                # 清理应用
                self.orchestrator.session.problem.app.cleanup()

                # 如果不是docker环境，清理Prometheus和OpenEBS
                if hasattr(self.orchestrator.session.problem, 'namespace') and \
                   self.orchestrator.session.problem.namespace != "docker":
                    if hasattr(self.orchestrator, 'prometheus'):
                        self.orchestrator.prometheus.teardown()

                    print("Uninstalling OpenEBS...")
                    self.orchestrator.kubectl.exec_command(
                        "kubectl delete sc openebs-hostpath openebs-device --ignore-not-found"
                    )
                    self.orchestrator.kubectl.exec_command(
                        "kubectl delete -f https://openebs.github.io/charts/openebs-operator.yaml"
                    )

            except Exception as e:
                print(f"⚠️ Error during cleanup: {e}")

        self.is_active = False
        print(f"✅ Session {self.session_id[:8]} cleaned")


class EnvironmentServer:
    """环境服务器主类 - 基于Orchestrator的重构版本"""

    def __init__(self):
        self.sessions: Dict[str, OrchestratorSession] = {}
        self.is_initialized = False

    async def startup(self):
        """服务器启动初始化"""
        print("🚀 Environment Server starting...")

        # 清理所有端口转发
        print("🧹 Cleaning up all port forwards...")
        PortManager.cleanup_all_port_forwards()

        # 创建或连接Kind集群
        if not create_kind_cluster():
            print("❌ Failed to setup Kind cluster, exiting...")
            sys.exit(1)

        self.is_initialized = True
        print(f"✅ Environment Server ready at http://{ServerConfig.HOST}:{ServerConfig.PORT}")
        print(f"📖 API Docs available at http://{ServerConfig.HOST}:{ServerConfig.PORT}/docs")

    async def shutdown(self):
        """服务器关闭清理"""
        print("🛑 Environment Server shutting down...")

        # 清理所有活动会话
        for session_id in list(self.sessions.keys()):
            try:
                await self.cleanup_session(session_id)
            except Exception as e:
                print(f"⚠️ Error cleaning session {session_id}: {e}")

        # 最终清理所有端口转发
        print("🧹 Final cleanup of port forwards...")
        PortManager.cleanup_all_port_forwards()

        # 询问是否删除集群
        if os.environ.get("AUTO_DELETE_CLUSTER", "false").lower() == "true":
            delete_kind_cluster()
        else:
            print(f"ℹ️ Kind cluster '{ServerConfig.KIND_CLUSTER_NAME}' kept running")

        # 清理临时kubeconfig
        if ServerConfig.KUBECONFIG_PATH and os.path.exists(ServerConfig.KUBECONFIG_PATH):
            try:
                os.remove(ServerConfig.KUBECONFIG_PATH)
            except:
                pass

        print("✅ Environment Server stopped")

    async def init_problem(self, problem_id: str, reset_if_exists: bool = False) -> Dict[str, Any]:
        """初始化问题实例"""
        print(f"\n🔧 Initializing problem: {problem_id}")

        # 检查是否已有该问题的会话
        existing_session = None
        for session in self.sessions.values():
            if session.problem_id == problem_id and session.is_active:
                existing_session = session
                break

        if existing_session and not reset_if_exists:
            print(f"ℹ️ Using existing session: {existing_session.session_id}")
            return {
                "session_id": existing_session.session_id,
                "problem_id": problem_id,
                "status": "existing",
                "message": "Using existing session",
                "is_submitted": existing_session.is_submitted,
                "task_description": existing_session.task_desc,
                "instructions": existing_session.instructions,
                "available_actions": existing_session.available_actions,
                "checkpoints": list(existing_session.checkpoints.keys())
            }

        # 如果需要重置，先清理旧会话
        if existing_session and reset_if_exists:
            print(f"🔄 Resetting existing session: {existing_session.session_id}")
            await self.cleanup_session(existing_session.session_id)

        # 创建新会话
        session_id = str(uuid.uuid4())
        session = OrchestratorSession(session_id, problem_id)

        try:
            # 初始化问题
            result = session.init_problem()

            self.sessions[session_id] = session

            print(f"✅ Problem {problem_id} initialized successfully!")
            print(f"📌 Session ID: {session_id}")

            return {
                "session_id": session_id,
                "problem_id": problem_id,
                "status": "initialized",
                "task_description": result["task_description"],
                "instructions": result["instructions"],
                "available_actions": result["available_actions"],
                "checkpoints": list(session.checkpoints.keys())
            }

        except Exception as e:
            print(f"❌ Error initializing problem: {e}")
            import traceback
            traceback.print_exc()

            if session_id in self.sessions:
                del self.sessions[session_id]

            raise HTTPException(status_code=500, detail=str(e))

    async def execute_action(self, session_id: str, action: str) -> Dict[str, Any]:
        """执行动作"""
        if session_id not in self.sessions:
            raise HTTPException(status_code=404, detail="Session not found")

        session = self.sessions[session_id]

        if not session.is_active:
            raise HTTPException(status_code=400, detail="Session is not active")

        return await session.execute_action(action)

    async def create_checkpoint(self, session_id: str, checkpoint_name: Optional[str] = None) -> Dict[str, Any]:
        """创建检查点"""
        if session_id not in self.sessions:
            raise HTTPException(status_code=404, detail="Session not found")

        session = self.sessions[session_id]

        if not session.is_active:
            raise HTTPException(status_code=400, detail="Session is not active")

        try:
            name = session.create_checkpoint(name=checkpoint_name)
            return {
                "checkpoint_name": name,
                "session_id": session_id,
                "total_checkpoints": len(session.checkpoints),
                "checkpoints": list(session.checkpoints.keys())
            }
        except Exception as e:
            raise HTTPException(status_code=500, detail=str(e))

    async def rollback(self, session_id: str, checkpoint_name: Optional[str] = None) -> Dict[str, Any]:
        """回滚到检查点"""
        if session_id not in self.sessions:
            raise HTTPException(status_code=404, detail="Session not found")

        session = self.sessions[session_id]

        if not session.is_active:
            raise HTTPException(status_code=400, detail="Session is not active")

        success = session.rollback_to_checkpoint(name=checkpoint_name)

        if success:
            return {
                "success": True,
                "session_id": session_id,
                "checkpoint_name": checkpoint_name or session.checkpoint_order[-1] if session.checkpoint_order else None,
                "history_length": len(session.orchestrator.session.history),
                "remaining_checkpoints": list(session.checkpoints.keys())
            }
        else:
            raise HTTPException(status_code=500, detail="Rollback failed")

    async def get_session_status(self, session_id: str) -> Dict[str, Any]:
        """获取会话状态"""
        if session_id not in self.sessions:
            raise HTTPException(status_code=404, detail="Session not found")

        session = self.sessions[session_id]

        return {
            "session_id": session_id,
            "problem_id": session.problem_id,
            "is_active": session.is_active,
            "created_at": session.created_at.isoformat(),
            "last_action": session.last_action_time.isoformat() if session.last_action_time else None,
            "history_length": len(session.orchestrator.session.history) if session.orchestrator.session else 0,
            "solution": session.solution,
            "is_submitted": session.is_submitted,
            "submission_result": session.submission_result,
            "evaluation_results": session.evaluation_results,
            "checkpoints": list(session.checkpoints.keys()),
            "task_description": session.task_desc,
            "instructions": session.instructions,
            "available_actions": session.available_actions
        }

    async def cleanup_session(self, session_id: str) -> Dict[str, str]:
        """清理会话"""
        if session_id not in self.sessions:
            raise HTTPException(status_code=404, detail="Session not found")

        session = self.sessions[session_id]

        try:
            session.cleanup()
            del self.sessions[session_id]
            return {"status": "cleaned", "session_id": session_id}
        except Exception as e:
            print(f"⚠️ Error during cleanup: {e}")
            return {"status": "error", "session_id": session_id, "error": str(e)}

    async def get_submit_format(self, session_id: str) -> Dict[str, Any]:
        """获取提交解决方案的格式要求"""
        if session_id not in self.sessions:
            raise HTTPException(status_code=404, detail="Session not found")

        session = self.sessions[session_id]
        return session.get_submit_format()

    async def submit_solution(self, session_id: str, solution: Union[str, List, Dict]) -> Dict[str, Any]:
        """提交解决方案"""
        if session_id not in self.sessions:
            raise HTTPException(status_code=404, detail="Session not found")

        session = self.sessions[session_id]
        return await session.submit_solution(solution)

# 创建服务器实例
env_server = EnvironmentServer()


# 创建FastAPI应用
@asynccontextmanager
async def lifespan(app: FastAPI):
    await env_server.startup()
    yield
    await env_server.shutdown()


app = FastAPI(
    title="AIOpsLab Environment Server",
    version="2.0.0",
    description="Orchestrator-based environment server for AIOpsLab",
    lifespan=lifespan
)

# 添加CORS支持
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# ===== API路由 =====

@app.get("/", tags=["Info"])
async def root():
    """获取服务器信息"""
    return {
        "service": "AIOpsLab Environment Server",
        "version": "2.0.0",
        "status": "running",
        "active_sessions": len(env_server.sessions),
        "cluster_name": ServerConfig.KIND_CLUSTER_NAME,
        "sessions": [
            {
                "session_id": sid[:8] + "...",
                "problem_id": s.problem_id,
                "is_active": s.is_active,
                "checkpoints": len(s.checkpoints),
                "is_submitted": s.is_submitted,
                "submission_result": s.submission_result
            }
            for sid, s in env_server.sessions.items()
        ]
    }


@app.post("/init_problem", tags=["Session"])
async def init_problem(request: InitProblemRequest):
    """初始化问题实例"""
    try:
        result = await env_server.init_problem(
            request.problem_id,
            request.reset_if_exists
        )
        return EnvironmentResponse(success=True, data=result)
    except HTTPException as e:
        raise e
    except Exception as e:
        return EnvironmentResponse(success=False, error=str(e))


@app.post("/execute_action", tags=["Session"])
async def execute_action(request: ActionRequest):
    """执行动作"""
    try:
        result = await env_server.execute_action(
            request.session_id,
            request.action
        )
        return EnvironmentResponse(success=True, data=result)
    except HTTPException as e:
        raise e
    except Exception as e:
        return EnvironmentResponse(success=False, error=str(e))


@app.post("/checkpoint", tags=["Rollback"])
async def create_checkpoint(request: CreateCheckpointRequest):
    """创建检查点"""
    try:
        result = await env_server.create_checkpoint(
            request.session_id,
            request.checkpoint_name
        )
        return EnvironmentResponse(success=True, data=result)
    except HTTPException as e:
        raise e
    except Exception as e:
        return EnvironmentResponse(success=False, error=str(e))


@app.post("/rollback", tags=["Rollback"])
async def rollback(request: RollbackRequest):
    """回滚到检查点"""
    try:
        result = await env_server.rollback(
            request.session_id,
            request.checkpoint_name
        )
        return EnvironmentResponse(success=True, data=result)
    except HTTPException as e:
        raise e
    except Exception as e:
        return EnvironmentResponse(success=False, error=str(e))


@app.get("/session/{session_id}/status", tags=["Session"])
async def get_session_status(session_id: str):
    """获取会话状态"""
    try:
        status = await env_server.get_session_status(session_id)
        return EnvironmentResponse(success=True, data=status)
    except HTTPException as e:
        raise e
    except Exception as e:
        return EnvironmentResponse(success=False, error=str(e))


@app.delete("/session/{session_id}", tags=["Session"])
async def cleanup_session(session_id: str):
    """清理会话"""
    try:
        result = await env_server.cleanup_session(session_id)
        return EnvironmentResponse(success=True, data=result)
    except HTTPException as e:
        raise e
    except Exception as e:
        return EnvironmentResponse(success=False, error=str(e))


@app.get("/health", tags=["Info"])
async def health_check():
    """健康检查"""
    return {
        "status": "healthy",
        "server_initialized": env_server.is_initialized,
        "active_sessions": len(env_server.sessions),
        "cluster_name": ServerConfig.KIND_CLUSTER_NAME
    }


@app.post("/port/cleanup", tags=["Maintenance"])
async def cleanup_ports():
    """手动清理端口转发"""
    try:
        PortManager.cleanup_all_port_forwards()
        return EnvironmentResponse(
            success=True,
            data={"message": "All port forwards cleaned"}
        )
    except Exception as e:
        return EnvironmentResponse(success=False, error=str(e))


@app.get("/port/status", tags=["Maintenance"])
async def port_status():
    """获取端口状态"""
    port_info = []
    for port in range(32000, 32010):
        available = PortManager.is_port_available(port)
        port_info.append({
            "port": port,
            "available": available,
            "in_use": port in PortManager._used_ports
        })

    return {
        "ports": port_info,
        "used_ports": list(PortManager._used_ports)
    }


@app.get("/session/{session_id}/submit_format", tags=["Submission"])
async def get_submit_format(session_id: str):
    """获取提交解决方案的格式要求"""
    try:
        result = await env_server.get_submit_format(session_id)
        return EnvironmentResponse(success=True, data=result)
    except HTTPException as e:
        raise e
    except Exception as e:
        return EnvironmentResponse(success=False, error=str(e))


@app.post("/submit", tags=["Submission"])
async def submit_solution(request: SubmitSolutionRequest):
    """提交解决方案"""
    try:
        result = await env_server.submit_solution(
            request.session_id,
            request.solution
        )
        return EnvironmentResponse(success=True, data=result)
    except HTTPException as e:
        raise e
    except Exception as e:
        return EnvironmentResponse(success=False, error=str(e))

# 主程序入口
if __name__ == "__main__":
    # 参数已经在文件开头解析了，这里只需要设置环境变量
    if args.auto_delete:
        os.environ["AUTO_DELETE_CLUSTER"] = "true"

    print("\n" + "=" * 60)
    print("🚀 AIOpsLab Environment Server (Orchestrator Mode)")
    print(f"📌 Port: {ServerConfig.PORT}")
    print(f"📌 Host: {ServerConfig.HOST}")
    print(f"📌 Kind Cluster: {ServerConfig.KIND_CLUSTER_NAME}")
    print(f"📌 Kind Config: {ServerConfig.KIND_CONFIG_PATH}")
    print(f"📌 Auto Delete: {args.auto_delete}")
    print(f"📌 KUBECONFIG: {os.environ.get('KUBECONFIG', '~/.kube/config')}")
    print("=" * 60 + "\n")

    # 注册退出清理
    def cleanup_on_exit():
        print("\n🧹 Cleaning up before exit...")
        PortManager.cleanup_all_port_forwards()

    atexit.register(cleanup_on_exit)

    uvicorn.run(
        app,
        host=ServerConfig.HOST,
        port=ServerConfig.PORT,
        log_level="info"
    )