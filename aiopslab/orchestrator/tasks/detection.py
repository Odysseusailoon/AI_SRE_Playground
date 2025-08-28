# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

"""Define and query information about an AIOps Detection task."""

import textwrap
from typing import Any


from aiopslab.orchestrator.tasks.base import Task
from aiopslab.orchestrator.actions.detection import DetectionActions
from aiopslab.service.apps.base import Application
from aiopslab.session import SessionItem
from aiopslab.utils.actions import get_actions
from aiopslab.utils.status import InvalidActionError


class DetectionTask(Task):
    """An AIOps anomaly detection task."""

    def __init__(self, app: Application):
        super().__init__()
        self.app = app
        self.helm_configs = self.app.helm_configs
        self.app_summary = self.app.get_app_summary()
        self.actions = DetectionActions()

        self.task_desc = """\
            You are an expert DevOps engineer assigned to detect anomalies in a deployed service.
            
            Service Details:
            {app_summary}

            You will begin by analyzing the service's state and telemetry, and then submit your solution:
            1. str: "Yes" or "No" to indicate whether there are anomalies detected
            """

        self.instructions = """\
            You will respond with one of the above APIs as your next action.
            Please respond in the following format in a markdown code block:
            ```\n<API_NAME>(<API_PARAM1>, <API_PARAM2> ...)\n```

            For instance, if you want to list files in current directory, your response must be exactly:
            
            ```\nexec_shell("ls -l")\n```

            If you decide that there are no anomalies:

            ```\nsubmit(\"No\")\n```

            Or, if anomalies are found:

            ```\nsubmit(\"Yes\")\n```

            Please respond with only a single API call (a.k.a., action) per turn without any additional words, labels, or prefixes.
            """

    def get_task_description(self):
        return textwrap.dedent(self.task_desc).format(app_summary=self.app_summary)

    def get_instructions(self):
        return textwrap.dedent(self.instructions)

    def get_available_actions(self):
        return get_actions(task="detection")

    def perform_action(self, action_name, *args, **kwargs):
        action_method = getattr(self.actions, action_name, None)

        if action_method is not None and callable(action_method):
            return action_method(*args, **kwargs)
        else:
            raise InvalidActionError(action_name)

    def eval(self, soln: Any, trace: list[SessionItem], duration: float):
        self.add_result("TTD", duration)
        self.common_eval(trace)
        
        from aiopslab.config import Config
        from aiopslab.paths import BASE_DIR
        config = Config(BASE_DIR / "config.yml")
        print("here")
        if config.get("supervisor_eval", False):
            try:
                print("here")
                from clients.supervisor import evaluate_detection_with_supervisor
                supervisor_results = evaluate_detection_with_supervisor(trace, str(soln))
                
                for key, value in supervisor_results.items():
                    self.add_result(f"supervisor_{key}", value)
                print(supervisor_results.get("final_detection_accuracy"))
                if supervisor_results.get("final_detection_accuracy") == "False Positive":
                    self.add_result("Detection Accuracy", "False Positive (Supervisor)")
                    self.add_result("supervisor_explanation", supervisor_results.get("supervisor_explanation"))
                    
            except ImportError:
                print("Warning: Supervisor evaluation requested but supervisor module not found")
            except Exception as e:
                print(f"Warning: Supervisor evaluation failed: {e}")
        
        return self.results
