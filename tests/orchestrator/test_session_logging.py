import sys
from pathlib import Path

sys.path.append(str(Path(__file__).resolve().parents[2]))

import atexit

CONFIG_PATH = Path(__file__).resolve().parents[2] / "aiopslab" / "config.yml"
if not CONFIG_PATH.exists():
    example = CONFIG_PATH.with_suffix('.yml.example')
    if example.exists():
        CONFIG_PATH.write_text(example.read_text())
    else:
        CONFIG_PATH.write_text('data_dir: data\nprint_session: false\n')
    atexit.register(lambda path=CONFIG_PATH: path.unlink(missing_ok=True))

from aiopslab.session import Session


class DummyProblem:
    def __init__(self, summary="Variant: foo=bar"):
        self._summary = summary

    def get_variant_summary(self):
        return self._summary


def test_session_records_variant_metadata():
    session = Session()
    session.set_problem(DummyProblem(), pid="dummy")
    session.set_agent("agent")
    session.retry_count = 2

    session.set_results({"success": True})

    assert session.variant_summary == "Variant: foo=bar"
    assert session.agent_outcome == "success"
    assert session.retry_count == 2

    summary = session.to_dict()
    assert summary["variant_summary"] == "Variant: foo=bar"
    assert summary["agent_outcome"] == "success"
    assert summary["retry_count"] == 2


def test_session_set_results_allows_overrides():
    session = Session()
    session.set_problem(DummyProblem("Base configuration"), pid="dummy")

    session.set_results({}, variant_summary="custom summary", agent_outcome="failure", retry_count=5)

    assert session.variant_summary == "custom summary"
    assert session.agent_outcome == "failure"
    assert session.retry_count == 5
