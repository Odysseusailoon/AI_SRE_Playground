#!/usr/bin/env python3.11
"""Export task execution data from the Task Executor API."""

from __future__ import annotations

import argparse
import json
from dataclasses import dataclass, asdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional

import requests


@dataclass
class ExportOptions:
    base_url: str
    output: Path
    page_size: int
    max_tasks: Optional[int]
    include_logs: bool
    include_conversations: bool
    timeout: int


class TaskExporter:
    """Helper for exporting task data via REST API."""

    def __init__(self, opts: ExportOptions) -> None:
        self.opts = opts
        self.session = requests.Session()
        self.session.headers.update({"Accept": "application/json"})

    def export(self) -> Dict[str, Any]:
        """Fetch tasks (and related data) then return a JSON-serialisable dict."""
        tasks: List[Dict[str, Any]] = []
        total_fetched = 0
        page = 1

        while True:
            remaining = None if self.opts.max_tasks is None else self.opts.max_tasks - total_fetched
            if remaining is not None and remaining <= 0:
                break

            page_size = self.opts.page_size if remaining is None else min(self.opts.page_size, remaining)
            payload = self._fetch_page(page=page, page_size=page_size)
            page_tasks = payload.get("tasks", [])
            total = payload.get("total", len(page_tasks))

            for task in page_tasks:
                task_bundle = {"task": task}

                if self.opts.include_logs:
                    task_bundle["logs"] = self._fetch_task_logs(task["id"])

                if self.opts.include_conversations:
                    task_bundle["conversations"] = self._fetch_task_conversations(task["id"])

                tasks.append(task_bundle)
                total_fetched += 1

            if total_fetched >= total or not page_tasks:
                break
            page += 1

        return {
            "exported_at": datetime.now(timezone.utc).isoformat(),
            "base_url": self.opts.base_url,
            "task_count": len(tasks),
            "tasks": tasks,
        }

    def _fetch_page(self, *, page: int, page_size: int) -> Dict[str, Any]:
        resp = self.session.get(
            f"{self.opts.base_url}/api/v1/tasks",
            params={"page": page, "page_size": page_size, "sort": "created_at"},
            timeout=self.opts.timeout,
        )
        resp.raise_for_status()
        return resp.json()

    def _fetch_task_logs(self, task_id: str) -> List[Dict[str, Any]]:
        resp = self.session.get(
            f"{self.opts.base_url}/api/v1/tasks/{task_id}/logs",
            params={"limit": 1000},
            timeout=self.opts.timeout,
        )
        resp.raise_for_status()
        payload = resp.json()
        return payload.get("logs", [])

    def _fetch_task_conversations(self, task_id: str) -> List[Dict[str, Any]]:
        conversations: List[Dict[str, Any]] = []
        page = 1
        while True:
            resp = self.session.get(
                f"{self.opts.base_url}/api/v1/llm-conversations",
                params={"task_id": task_id, "page": page, "page_size": 50},
                timeout=self.opts.timeout,
            )
            resp.raise_for_status()
            payload = resp.json()
            items = payload.get("conversations", [])
            if not items:
                break

            for conv in items:
                conv_id = conv["id"]
                conv_details = self.session.get(
                    f"{self.opts.base_url}/api/v1/llm-conversations/{conv_id}/messages",
                    timeout=self.opts.timeout,
                )
                conv_details.raise_for_status()
                conversations.append(conv_details.json())

            total = payload.get("total")
            if total is not None and len(conversations) >= total:
                break
            page += 1
        return conversations


def parse_args() -> ExportOptions:
    parser = argparse.ArgumentParser(description="Export data from Task Executor API")
    parser.add_argument("base_url", nargs="?", default="http://localhost:8000", help="Task Executor base URL")
    parser.add_argument("--output", "-o", default="task_export.json", help="Path to export JSON file")
    parser.add_argument("--page-size", type=int, default=50, help="Tasks per request")
    parser.add_argument("--max-tasks", type=int, help="Maximum tasks to export")
    parser.add_argument("--skip-logs", action="store_true", help="Do not fetch task logs")
    parser.add_argument("--skip-conversations", action="store_true", help="Do not fetch LLM conversations")
    parser.add_argument("--timeout", type=int, default=30, help="Request timeout in seconds")
    args = parser.parse_args()

    return ExportOptions(
        base_url=args.base_url.rstrip("/"),
        output=Path(args.output),
        page_size=args.page_size,
        max_tasks=args.max_tasks,
        include_logs=not args.skip_logs,
        include_conversations=not args.skip_conversations,
        timeout=args.timeout,
    )


def main() -> None:
    opts = parse_args()
    exporter = TaskExporter(opts)
    data = exporter.export()

    opts.output.parent.mkdir(parents=True, exist_ok=True)
    with opts.output.open("w", encoding="utf-8") as fp:
        json.dump(data, fp, indent=2, ensure_ascii=False)

    print(f"Exported {data['task_count']} tasks to {opts.output}")


if __name__ == "__main__":
    main()
