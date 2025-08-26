"""Supervisor Agent for validating detection task conversations.

This agent evaluates whether a detection task conversation actually evidences
a real problem, helping to reduce false positives in detection accuracy metrics.
"""

import os
import sys
import json
import glob
from pathlib import Path
from typing import Dict, Any, List, Tuple
from dotenv import load_dotenv

sys.path.append(str(Path(__file__).parent.parent))
from clients.utils.llm import GPTClient
from aiopslab.session import SessionItem

load_dotenv()


class SupervisorAgent:
    """A lightweight GPT-based supervisor to evaluate detection task conversations."""
    
    def __init__(self, model: str = "gpt-4o"):
        """Initialize supervisor agent with specified model."""
        self.llm = GPTClient()
        self.model = model
        
    def evaluate_detection_conversation(self, trace: List[SessionItem]) -> Tuple[bool, str]:
        """Evaluate if a detection conversation evidences an actual problem.
        
        Args:
            trace: List of session items containing agent-environment conversation
            
        Returns:
            Tuple of (is_problem_evidenced: bool, reason: str)
        """
        conversation_text = self._format_conversation(trace)
        
        system_prompt = """You are a supervisor agent evaluating whether a detection task conversation provides sufficient evidence of an actual system problem.

Your task is to analyze the conversation between an agent and a system environment to determine if there is genuine evidence of a problem that warrants marking the detection as positive.

Consider these factors:
1. Are there clear error messages, failures, or anomalous behavior?
2. Are there actual system metrics indicating problems?
3. Is the evidence substantial enough to justify concern in a production environment?
4. Could the observed behavior be normal operational state (e.g., empty namespaces in test environments)?

Common false positives to watch for:
- Empty Kubernetes namespaces in test/dev environments
- Normal maintenance states
- Expected system behavior during deployments
- Lack of concrete error evidence

Respond with:
- "EVIDENCED" if there is clear evidence of an actual problem
- "NOT_EVIDENCED" if there is insufficient evidence or the behavior appears normal
- "INCONCLUSIVE" if the evidence is ambiguous

Follow your decision with a brief explanation (2-3 sentences) of your reasoning."""

        user_prompt = f"""Analyze this detection task conversation:

{conversation_text}

Based on the conversation, does this provide sufficient evidence of an actual system problem that would warrant a positive detection in a production environment?"""

        messages = [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_prompt}
        ]
        
        try:
            response = self.llm.run(messages)
            result_text = response[0].strip()
            
            # Parse response
            if result_text.startswith("EVIDENCED"):
                return True, result_text[len("EVIDENCED"):].strip()
            elif result_text.startswith("NOT_EVIDENCED"):
                return False, result_text[len("NOT_EVIDENCED"):].strip()
            elif result_text.startswith("INCONCLUSIVE"):
                return False, result_text[len("INCONCLUSIVE"):].strip()
            else:
                # Default to not evidenced if parsing fails
                return False, f"Failed to parse supervisor response: {result_text}"
                
        except Exception as e:
            return False, f"Supervisor evaluation failed: {str(e)}"
    
    def _format_conversation(self, trace: List[SessionItem]) -> str:
        """Format conversation trace into readable text."""
        formatted_lines = []
        
        for item in trace:
            role = item.role
            content = item.content
            
            if role == "assistant":
                formatted_lines.append(f"AGENT: {content}")
            elif role == "env":
                formatted_lines.append(f"ENVIRONMENT: {content}")
            elif role == "user":
                formatted_lines.append(f"SYSTEM: {content}")
                
        return "\n".join(formatted_lines)


def evaluate_detection_with_supervisor(trace: List[SessionItem], original_result: str) -> Dict[str, Any]:
    """Evaluate a detection task with supervisor validation.
    
    Args:
        trace: Conversation trace from detection task
        original_result: Original detection result ("Yes"/"No")
        
    Returns:
        Dictionary with supervisor evaluation results
    """
    supervisor = SupervisorAgent()
    is_evidenced, reason = supervisor.evaluate_detection_conversation(trace)
    
    # Determine final result
    if original_result.strip().lower() == "yes":
        if is_evidenced:
            final_result = "Correct"  # True positive
            explanation = "Agent correctly identified evidenced problem"
        else:
            final_result = "False Positive"  # False positive caught by supervisor
            explanation = f"Agent reported problem but supervisor found insufficient evidence: {reason}"
    else:  # original_result == "no"
        if is_evidenced:
            final_result = "False Negative"  # Missed a real problem
            explanation = f"Agent missed evidenced problem: {reason}"
        else:
            final_result = "Correct"  # True negative
            explanation = "Agent correctly identified no problem"
    
    return {
        "supervisor_evidenced": is_evidenced,
        "supervisor_reason": reason,
        "final_detection_accuracy": final_result,
        "supervisor_explanation": explanation,
        "original_detection": original_result
    }

def format_trace(results_dir: str = "results") -> List[SessionItem]:
    """
    Process trace data from results/*.json files, filtering for detection problems only.
    
    Args:
        results_dir: Directory containing the JSON result files
        
    Returns:
        List of SessionItem objects from detection problem traces
    """
    session_items = list()
    trace = list()
    
    # Get all JSON files in the results directory
    json_files = glob.glob(os.path.join(results_dir, "*.json"))
    
    for file_path in json_files:
        try:
            with open(file_path, 'r') as f:
                data = json.load(f)
            
            # Only process files where problem_id contains 'detection'
            problem_id = data.get('problem_id', '')
            if 'detection' not in problem_id.lower():
                continue
                
            # Extract trace items and convert to SessionItem objects
            trace_data = data.get('trace', [])
            for item in trace_data:
                if isinstance(item, dict) and 'role' in item and 'content' in item:
                    trace.append(SessionItem(
                        role=item['role'],
                        content=item['content']
                    ))

            session_items.append(trace)
        except (json.JSONDecodeError, FileNotFoundError, KeyError) as e:
            print(f"Error processing file {file_path}: {e}")
            continue
    
        return session_items



if __name__ == "__main__":
    # Example usage with format_trace function
    print("Loading detection traces from results directory...")
    session_traces = format_trace("results/")
    print(f"Found {len(session_traces)} SessionItem objects from detection problems")
    
    # Example usage with supervisor evaluation
    example_trace = [
        SessionItem(role="assistant", content='exec_shell("kubectl get pods -n docker")'),
        SessionItem(role="env", content="No resources found in docker namespace.\n"),
        SessionItem(role="assistant", content='exec_shell("kubectl get all -n docker")'),
        SessionItem(role="env", content="No resources found in docker namespace.\n"),
        SessionItem(role="assistant", content='submit("Yes")'),
        SessionItem(role="env", content="1")
    ]

    for trace in session_traces:
        result = evaluate_detection_with_supervisor(trace, "Yes")
        print("\nSupervisor Evaluation Results:")
        print(json.dumps(result, indent=4))