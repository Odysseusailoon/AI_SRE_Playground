"""
环境客户端 - 多智能体系统与环境服务器的接口
"""

import requests
from typing import Dict, Any, Optional, List, Union
import json
from datetime import datetime


class EnvironmentClient:
    """环境客户端 - 与环境服务器通信"""

    # 默认配置
    DEFAULT_HOST = "127.0.0.1"
    DEFAULT_PORT = 8000

    @classmethod
    def set_default_server(cls, host: str = "127.0.0.1", port: int = 8000):
        """设置默认服务器地址"""
        cls.DEFAULT_HOST = host
        cls.DEFAULT_PORT = port

    def __init__(self, server_url: Optional[str] = None, host: Optional[str] = None,
                 port: Optional[int] = None, session_id: Optional[str] = None):
        """
        初始化客户端
        Args:
            server_url: 完整的服务器URL（优先级最高）
            host: 服务器主机地址
            port: 服务器端口号
            session_id: 会话ID
        """
        if server_url:
            self.server_url = server_url
        else:
            # 使用提供的host和port，或使用默认值
            host = host or self.DEFAULT_HOST
            port = port or self.DEFAULT_PORT
            self.server_url = f"http://{host}:{port}"

        print(f"📡 Connecting to server: {self.server_url}")

        self.session_id: Optional[str] = session_id
        self.problem_id: Optional[str] = None
        self.task_description: Optional[str] = None
        self.instructions: Optional[str] = None
        self.available_actions: Optional[Dict] = None
        self.checkpoints: List[str] = []
        self.submit_api_info: Optional[Dict] = None
        self.is_submitted: bool = False
        self.submission_result: Optional[str] = None

        # 如果提供了session_id，尝试连接到现有会话
        if session_id:
            self.connect_session(session_id)

    def check_connection(self) -> bool:
        """检查与服务器的连接"""
        try:
            response = requests.get(f"{self.server_url}/")
            return response.status_code == 200
        except:
            return False

    def init_problem(self, problem_id: str, reset_if_exists: bool = False) -> Dict[str, Any]:
        """初始化问题实例"""

        try:
            response = requests.post(
                f"{self.server_url}/init_problem",
                json={
                    "problem_id": problem_id,
                    "reset_if_exists": reset_if_exists
                }
            )

            if response.status_code == 200:
                result = response.json()

                if result["success"]:
                    data = result["data"]
                    self.session_id = data["session_id"]
                    self.problem_id = data["problem_id"]
                    self.task_description = data.get("task_description")
                    self.instructions = data.get("instructions")
                    self.available_actions = data.get("available_actions")
                    self.checkpoints = data.get("checkpoints", [])
                    self.submit_api_info = data.get("submit_api")
                    self.is_submitted = data.get("is_submitted", False)
                    self.submission_result = data.get("submission_result")

                    print(f"✅ Problem initialized: {problem_id}")
                    print(f"📝 Session ID: {self.session_id}")

                    if self.submit_api_info:
                        print(f"📨 Submit API: {self.submit_api_info.get('name')}")

                    return data
                else:
                    print(f"❌ Failed to initialize problem: {result.get('error')}")
                    return None
            else:
                print(f"❌ Server error: {response.status_code}")
                return None

        except Exception as e:
            print(f"❌ Connection error: {e}")
            return None

    def connect_session(self, session_id: str) -> Dict[str, Any]:
        """连接到已存在的会话"""

        try:
            response = requests.post(
                f"{self.server_url}/connect_session",
                json={"session_id": session_id}
            )

            if response.status_code == 200:
                result = response.json()

                if result["success"]:
                    data = result["data"]
                    self.session_id = data["session_id"]
                    self.problem_id = data["problem_id"]
                    self.task_description = data.get("task_description")
                    self.instructions = data.get("instructions")
                    self.available_actions = data.get("available_actions")
                    self.checkpoints = data.get("checkpoints", [])
                    self.is_submitted = data.get("is_submitted", False)
                    self.submission_result = data.get("submission_result")

                    print(f"✅ Connected to session: {session_id[:8]}...")
                    print(f"📝 Problem ID: {self.problem_id}")
                    print(f"📊 History length: {data.get('history_length', 0)}")
                    print(f"💾 Checkpoints: {len(self.checkpoints)}")

                    if self.is_submitted:
                        print(f"📨 Solution already submitted: {self.submission_result}")

                    return data
                else:
                    print(f"❌ Failed to connect to session: {result.get('error')}")
                    return None
            else:
                print(f"❌ Session not found or server error: {response.status_code}")
                return None

        except Exception as e:
            print(f"❌ Connection error: {e}")
            return None

    def get_submit_format(self) -> Dict[str, Any]:
        """获取提交解决方案的格式要求"""

        if not self.session_id:
            raise ValueError("No active session. Please initialize a problem or connect to a session first.")

        try:
            response = requests.get(
                f"{self.server_url}/session/{self.session_id}/submit_format"
            )

            if response.status_code == 200:
                result = response.json()

                if result["success"]:
                    data = result["data"]
                    self.submit_api_info = data.get("submit_api")

                    print(f"📨 Submit Format Information:")
                    print(f"  API: {data['submit_api']['api_name']}")
                    print(f"  Description: {data['submit_api']['description']}")

                    if data.get("format_examples"):
                        print(f"  Examples: {json.dumps(data['format_examples'], indent=2)}")

                    if data.get("is_already_submitted"):
                        print(f"⚠️ Solution already submitted: {data.get('previous_submission')}")

                    return data
                else:
                    print(f"❌ Failed to get submit format: {result.get('error')}")
                    return None
            else:
                print(f"❌ Server error: {response.status_code}")
                return None

        except Exception as e:
            print(f"❌ Connection error: {e}")
            return None

    def submit_solution(self, solution: Union[str, List, Dict]) -> Dict[str, Any]:
        """提交解决方案"""

        if not self.session_id:
            raise ValueError("No active session. Please initialize a problem or connect to a session first.")

        try:
            response = requests.post(
                f"{self.server_url}/submit",
                json={
                    "session_id": self.session_id,
                    "solution": solution
                }
            )

            if response.status_code == 200:
                result = response.json()

                if result["success"]:
                    data = result["data"]
                    self.is_submitted = True
                    self.submission_result = data.get("submission_result")

                    if data.get("is_valid"):
                        print(f"🎉 Valid submission! Problem solved.")
                        if data.get("evaluation"):
                            print(f"📊 Evaluation results: {json.dumps(data['evaluation'], indent=2)}")
                    else:
                        print(f"❌ Invalid submission. Please try again.")

                    return data
                else:
                    print(f"❌ Failed to submit solution: {result.get('error')}")
                    return None
            else:
                print(f"❌ Server error: {response.status_code}")
                return None

        except Exception as e:
            print(f"❌ Connection error: {e}")
            return None

    def create_checkpoint(self, checkpoint_name: Optional[str] = None) -> Dict[str, Any]:
        """创建检查点"""

        if not self.session_id:
            raise ValueError("No active session. Please initialize a problem or connect to a session first.")

        try:
            response = requests.post(
                f"{self.server_url}/checkpoint",
                json={
                    "session_id": self.session_id,
                    "checkpoint_name": checkpoint_name
                }
            )

            if response.status_code == 200:
                result = response.json()

                if result["success"]:
                    data = result["data"]
                    self.checkpoints = data.get("checkpoints", [])
                    print(f"✅ Checkpoint created: {data['checkpoint_name']}")
                    return data
                else:
                    print(f"❌ Failed to create checkpoint: {result.get('error')}")
                    return None
            else:
                print(f"❌ Server error: {response.status_code}")
                return None

        except Exception as e:
            print(f"❌ Connection error: {e}")
            return None

    def rollback(self, checkpoint_name: Optional[str] = None) -> Dict[str, Any]:
        """回滚到检查点"""

        if not self.session_id:
            raise ValueError("No active session. Please initialize a problem or connect to a session first.")

        try:
            response = requests.post(
                f"{self.server_url}/rollback",
                json={
                    "session_id": self.session_id,
                    "checkpoint_name": checkpoint_name
                }
            )

            if response.status_code == 200:
                result = response.json()

                if result["success"]:
                    data = result["data"]
                    if data["success"]:
                        self.checkpoints = data.get("remaining_checkpoints", [])
                        # 重置提交状态
                        if data.get("submission_reset"):
                            self.is_submitted = False
                            self.submission_result = None
                        print(f"✅ Rolled back to checkpoint: {data.get('checkpoint_name', 'latest')}")
                        return data
                    else:
                        print(f"❌ Rollback failed")
                        return None
                else:
                    print(f"❌ Failed to rollback: {result.get('error')}")
                    return None
            else:
                print(f"❌ Server error: {response.status_code}")
                return None

        except Exception as e:
            print(f"❌ Connection error: {e}")
            return None

    def execute_action(self, action: str) -> Dict[str, Any]:
        """执行动作"""

        if not self.session_id:
            raise ValueError("No active session. Please initialize a problem or connect to a session first.")

        try:
            response = requests.post(
                f"{self.server_url}/execute_action",
                json={
                    "session_id": self.session_id,
                    "action": action
                }
            )

            if response.status_code == 200:
                result = response.json()

                if result["success"]:
                    data = result["data"]

                    # 如果是提交动作
                    if data.get("is_submission"):
                        self.is_submitted = True

                        # 检查提交结果 - 需要查看返回的result内容
                        result_str = str(data.get("result", ""))

                        # 根据返回内容判断提交状态
                        if "VALID_SUBMISSION" in result_str or data.get("is_complete"):
                            self.submission_result = "VALID"
                            print(f"🎉 Problem solved! Valid submission received.")
                            if data.get("evaluation"):
                                print(f"📊 Evaluation: {json.dumps(data['evaluation'], indent=2)}")
                        elif "INVALID_SUBMISSION" in result_str:
                            self.submission_result = "INVALID"
                            print(f"❌ Invalid submission - the solution does not meet requirements")
                        else:
                            # 提交已接受但还在处理中，或者是其他状态
                            self.submission_result = "SUBMITTED"
                            print(f"📨 Submission received: {result_str[:200]}")
                            # 不要过早判定为INVALID，可能只是需要继续迭代

                    return data
                else:
                    print(f"⚠️ Action failed: {result.get('error')}")
                    return {"result": result.get('error'), "error": True}
            else:
                print(f"❌ Server error: {response.status_code}")
                return {"result": f"Server error: {response.status_code}", "error": True}

        except Exception as e:
            print(f"❌ Connection error: {e}")
            return {"result": str(e), "error": True}


    def get_session_status(self) -> Dict[str, Any]:
        """获取当前会话状态"""

        if not self.session_id:
            return {"error": "No active session"}

        try:
            response = requests.get(
                f"{self.server_url}/session/{self.session_id}/status"
            )

            if response.status_code == 200:
                result = response.json()
                if result["success"]:
                    data = result["data"]
                    self.checkpoints = data.get("checkpoints", [])
                    self.is_submitted = data.get("is_submitted", False)
                    self.submission_result = data.get("submission_result")
                    return data
                return None
            else:
                return None

        except Exception as e:
            print(f"❌ Error getting session status: {e}")
            return None

    def get_history(self, last_n: Optional[int] = None) -> List[Dict]:
        """获取会话历史"""

        if not self.session_id:
            return []

        try:
            params = {"last_n": last_n} if last_n else {}
            response = requests.get(
                f"{self.server_url}/session/{self.session_id}/history",
                params=params
            )

            if response.status_code == 200:
                result = response.json()
                return result["data"] if result["success"] else []
            else:
                return []

        except Exception as e:
            print(f"❌ Error getting history: {e}")
            return []

    def cleanup_session(self) -> bool:
        """清理当前会话"""

        if not self.session_id:
            return True

        try:
            response = requests.delete(
                f"{self.server_url}/session/{self.session_id}"
            )

            if response.status_code == 200:
                print(f"✅ Session {self.session_id} cleaned up")
                self.session_id = None
                self.problem_id = None
                self.checkpoints = []
                self.is_submitted = False
                self.submission_result = None
                return True
            else:
                print(f"⚠️ Failed to cleanup session")
                return False

        except Exception as e:
            print(f"❌ Error cleaning up session: {e}")
            return False

    def reset_environment(self) -> bool:
        """重置整个环境"""

        try:
            response = requests.post(f"{self.server_url}/reset")

            if response.status_code == 200:
                print("✅ Environment reset successfully")
                self.session_id = None
                self.problem_id = None
                self.checkpoints = []
                self.is_submitted = False
                self.submission_result = None
                return True
            else:
                print("⚠️ Failed to reset environment")
                return False

        except Exception as e:
            print(f"❌ Error resetting environment: {e}")
            return False

    def list_sessions(self) -> List[Dict]:
        """列出所有活动会话"""

        try:
            response = requests.get(f"{self.server_url}/sessions")

            if response.status_code == 200:
                result = response.json()
                return result["data"] if result["success"] else []
            else:
                return []

        except Exception as e:
            print(f"❌ Error listing sessions: {e}")
            return []

    def get_session_id(self) -> Optional[str]:
        """获取当前会话ID"""
        return self.session_id

    def is_problem_solved(self) -> bool:
        """检查问题是否已解决"""
        return self.is_submitted and self.submission_result == "VALID"


if __name__ == "__main__":
    # 示例1: 完整的问题解决流程
    EnvironmentClient.set_default_server(host="127.0.0.1", port=8002)
    print("=" * 60)
    print("示例1: 完整的问题解决流程")
    print("=" * 60)

    client = EnvironmentClient()

    # 初始化问题
    result = client.init_problem("k8s_target_port-misconfig-detection-1")
    # session_id = "e3dd22b0-af93-402e-a581-06441763a80b"
    # result = client.connect_session(session_id)

    if result:
        print(f"\nSession ID: {client.get_session_id()}")

        # 获取提交格式要求
        submit_format = client.get_submit_format()
        print(f"\nSubmit format received: {submit_format}")

        # 执行一些诊断动作
        print("\n执行诊断动作...")
        response = client.execute_action('exec_shell("kubectl get pods")')
        print(f"Pods列表: {response.get('result', '')[:200]}...")

        response = client.execute_action('exec_shell("kubectl get services")')
        print(f"Services列表: {response.get('result', '')[:200]}...")

        # 创建检查点
        client.create_checkpoint("after_diagnosis")

        # 尝试修复问题
        print("\n尝试修复问题...")
        response = client.execute_action('exec_shell("kubectl get svc -o yaml")')

        # 提交解决方案
        print("\n提交解决方案...")
        solution = {
            "problem": "Service target port mismatch",
            "fix": "Changed targetPort from 8080 to 80",
            "service": "example-service",
            "namespace": "default"
        }

        submit_result = client.submit_solution(solution)

        if client.is_problem_solved():
            print("\n✅ 问题已成功解决!")
        else:
            print("\n❌ 解决方案无效，请重试")

            # 可以回滚到之前的检查点重试
            client.rollback("after_diagnosis")
            print("已回滚到诊断后的状态")

        # 查看最终状态
        status = client.get_session_status()
        print(f"\n最终状态: {json.dumps(status, indent=2)}")

        # 清理
        client.cleanup_session()

    print("\n" + "=" * 60)
    print("示例2: 使用execute_action执行submit")
    print("=" * 60)

    client2 = EnvironmentClient()
    result = client2.init_problem("k8s_target_port-misconfig-detection-1")

    if result:
        # 直接使用execute_action执行submit
        print("\n使用execute_action执行submit...")
        response = client2.execute_action('submit("Fixed service targetPort mismatch")')

        if response.get("is_complete"):
            print("✅ 通过execute_action成功解决问题!")
        else:
            print("❌ 提交失败")

        # 清理
        client2.cleanup_session()