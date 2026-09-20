"""DB 접속 없이 모델 Jinja와 설치된 dbt의 교체 조건을 검사한다.

dbt-bigquery 환경에서 실행:
    python -m unittest discover -s scripts/tests -v
SQLite 검사는 생성된 삭제 조건의 경계/빈 결과 동작을 확인하며 BigQuery 통합 검사를 대체하지 않는다.
"""

import datetime
from importlib.metadata import distribution
from pathlib import Path
import re
import sqlite3
from types import SimpleNamespace
import unittest

from jinja2 import Environment, StrictUndefined


ROOT = Path(__file__).resolve().parents[2]
MODEL = ROOT / "dbt/models/silver/silver_events_v2.sql"
ENV = Environment(undefined=StrictUndefined, extensions=["jinja2.ext.do"])


def compiler_error(message):
    raise ValueError(message)


def render_model(variables=None, execute=False):
    settings = {}

    def config(**kwargs):
        settings.update(kwargs)
        return ""

    sql = ENV.from_string(MODEL.read_text(encoding="utf-8")).render(
        var=lambda name, default=None: (variables or {}).get(name, default),
        config=config,
        execute=execute,
        modules=SimpleNamespace(re=re, datetime=datetime),
        exceptions=SimpleNamespace(raise_compiler_error=compiler_error),
        source=lambda *args: "`test_project.ga4.events_*`",
    )
    return settings, sql


def render_merge(settings):
    """설치된 어댑터의 실제 static/dynamic 분기와 MERGE를 렌더링한다."""
    core_file = distribution("dbt-core").locate_file(
        "dbt/include/global_project/macros/materializations/models/incremental/merge.sql"
    )
    core = ENV.from_string(core_file.read_text(encoding="utf-8")).make_module({
        "config": {},
        "get_quoted_csv": lambda names: ", ".join(names),
    })
    adapter_file = distribution("dbt-bigquery").locate_file(
        "dbt/include/bigquery/macros/materializations/incremental_strategy/insert_overwrite.sql"
    )
    adapter = ENV.from_string(adapter_file.read_text(encoding="utf-8")).make_module({
        "get_insert_overwrite_merge_sql": core.default__get_insert_overwrite_merge_sql,
    })
    partition_by = SimpleNamespace(
        time_ingestion_partitioning=False,
        render_wrapped=lambda alias=None: f"{alias}.event_dt" if alias else "event_dt",
    )
    return adapter.bq_insert_overwrite_sql(
        "staged_events", "existing_events", "select * from staged_events", None,
        partition_by, settings["partitions"],
        [SimpleNamespace(name="event_dt"), SimpleNamespace(name="value")], True, False,
    )


class PartitionTests(unittest.TestCase):
    def test_explicit_ranges_at_parse_and_execution(self):
        cases = [
            ("20260915", "20260917", ["2026-09-15", "2026-09-16", "2026-09-17"]),
            (20260915, 20260915, ["2026-09-15"]),
            ("20240228", "20240301", ["2024-02-28", "2024-02-29", "2024-03-01"]),
            ("20261231", "20270101", ["2026-12-31", "2027-01-01"]),
        ]
        for start, end, expected in cases:
            for execute in (False, True):
                with self.subTest(start=start, end=end, execute=execute):
                    config, sql = render_model({"start_date": start, "end_date": end}, execute)
                    self.assertEqual(config["partitions"], [f"date '{day}'" for day in expected])
                    self.assertIn(f"parse_date('%Y%m%d', '{start}') as target_start_dt", sql)
                    self.assertIn(f"parse_date('%Y%m%d', '{end}') as target_end_dt", sql)
                    self.assertIn("event_dt between date_window.target_start_dt and date_window.target_end_dt", sql)

    def test_monthly_and_initial_load_ranges(self):
        for start, end in [("20260802", "20260831"), ("20240711", "20260917")]:
            config, _ = render_model({"start_date": start, "end_date": end})
            start_day = datetime.datetime.strptime(start, "%Y%m%d").date()
            end_day = datetime.datetime.strptime(end, "%Y%m%d").date()
            self.assertEqual(len(config["partitions"]), (end_day - start_day).days + 1)
            self.assertEqual(config["partitions"][0], f"date '{start_day}'")
            self.assertEqual(config["partitions"][-1], f"date '{end_day}'")

    def test_no_vars_keeps_three_day_default_during_parsing(self):
        for execute in (False, True):
            config, sql = render_model(execute=execute)
            self.assertEqual(config["partitions"], [
                f"date_sub(current_date('Asia/Seoul'), interval {day} day)"
                for day in (1, 2, 3)
            ])
            self.assertIn(config["partitions"][-1] + " as target_start_dt", sql)
            self.assertIn(config["partitions"][0] + " as target_end_dt", sql)

    def test_bad_dates_fail_before_a_partition_config_is_created(self):
        cases = [
            {"start_date": "20260915"}, {"end_date": "20260917"},
            {"start_date": "", "end_date": ""},
            {"start_date": "20260915", "end_date": ""},
            {"start_date": "20260918", "end_date": "20260917"},
            {"start_date": "20260230", "end_date": "20260301"},
            {"start_date": "20260915", "end_date": "20260931"},
            {"start_date": "20260915\n", "end_date": "20260917"},
            {"start_date": "1' or '1", "end_date": "20260917"},
        ]
        for variables in cases:
            with self.subTest(variables=variables), self.assertRaises(ValueError):
                render_model(variables)

    def test_generated_delete_condition_covers_empty_dates_and_preserves_outside(self):
        config, _ = render_model({"start_date": "20260915", "end_date": "20260917"})
        merge = render_merge(config)
        self.assertIn("on FALSE", merge)
        self.assertNotIn("dbt_partitions_for_replacement", merge)
        self.assertIn("when not matched then insert", merge)
        predicate = re.search(r"when not matched by source\s+and (.*?)\s+then delete", merge, re.S)
        self.assertIsNotNone(predicate)
        # SQLite stores fixture dates as ISO strings; strip only BigQuery's DATE literal prefix.
        condition = re.sub(r"\bdate ('\d{4}-\d{2}-\d{2}')", r"\1", predicate.group(1))
        old = [(f"2026-09-{day}", "old") for day in range(14, 19)]
        outside = [old[0], old[-1]]
        fixtures = {
            "all_empty": [],
            "missing_middle_date": [("2026-09-15", "new"), ("2026-09-17", "new")],
            "unchanged": old[1:-1],
        }
        for name, fresh in fixtures.items():
            with self.subTest(name=name), sqlite3.connect(":memory:") as db:
                db.execute("create table existing_events (event_dt text, value text)")
                db.executemany("insert into existing_events values (?, ?)", old)
                for _ in range(2):  # Re-running must produce the same result.
                    db.execute(f"delete from existing_events as DBT_INTERNAL_DEST where {condition}")
                    db.executemany("insert into existing_events values (?, ?)", fresh)
                    actual = db.execute("select * from existing_events order by event_dt").fetchall()
                    self.assertEqual(actual, sorted(outside + fresh))


if __name__ == "__main__":
    unittest.main()
