# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

"""Helper functions for quantiative evaluation of solutions."""

import tiktoken

from aiopslab.session import SessionItem

# Constants
token_model = "gpt-3.5-turbo"
tokenizer = tiktoken.encoding_for_model(token_model)


def num_steps_taken(trace: list[SessionItem]) -> int:
    """Return the number of steps taken in the trace."""
    return len([item for item in trace if item.role == "assistant"])


def out_tokens(trace: list[SessionItem]) -> int:
    """Return the (approx) total token cost of the agent's output."""
    # NOTE: not dollar value, since depends on Agent's model

    agent_steps = "".join([item.content for item in trace if item.role == "assistant"])
    return len(tokenizer.encode(agent_steps, disallowed_special=()))


def in_tokens(trace: list[SessionItem]) -> int:
    """Return the (approx) total token cost of the env's input."""
    # NOTE: not dollar value, since depends on Agent's model

    user_steps = "".join([item.content for item in trace if item.role != "assistant"])
    return len(tokenizer.encode(user_steps))


def api_tokens_from_trace(trace: list[SessionItem]) -> dict:
    """Extract precise token and timing statistics from API-provided metadata.
    
    Returns dict with:
        - api_prompt_tokens: Total input tokens from API
        - api_completion_tokens: Total output tokens from API  
        - api_total_tokens: Total tokens
        - total_llm_time: Total LLM response time (seconds)
        - avg_llm_time: Average response time per call
        - min_llm_time: Fastest response time
        - max_llm_time: Slowest response time
        - num_llm_calls: Number of LLM API calls
    """
    total_prompt = 0
    total_completion = 0
    total_llm_time = 0.0
    response_times = []
    
    for item in trace:
        if item.role == "assistant" and item.metadata:
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


def is_exact_match(pred: int | str | list, target: int | str | list) -> bool:
    """Return True if the prediction is an exact match to the target."""
    return pred == target


def is_exact_match_lower(pred: str, target: str) -> bool:
    """Return True if the prediction is an exact match to the target."""
    return pred.strip().lower() == target.strip().lower()


def is_in_range(pred: int | float, target: int | float, tolerance: float) -> bool:
    """Return True if the prediction is within the target range."""
    return target - tolerance <= pred <= target + tolerance


def is_subset(pred: list, target: list) -> bool:
    """Return True if the prediction is a subset of the target."""
    return set(pred).issubset(set(target))


def is_superset(pred: list, target: list) -> bool:
    """Return True if the prediction is a superset of the target."""
    return set(pred).issuperset(set(target))


# TODO: once observability is setup, use metrics, traces, logs,
# and wrk2's logs to also observe the (side)-effects of agents' actions
# e.g., latency, throughput, etc.
