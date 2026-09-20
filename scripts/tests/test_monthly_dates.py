"""monthly의 날짜 확장, 수동 제한, daily 대기 및 날짜 경과 검증."""

import ast
from datetime import date, datetime, timezone
from importlib.util import module_from_spec, spec_from_file_location
from pathlib import Path
from types import SimpleNamespace
import unittest
from unittest.mock import patch

from jinja2 import Environment, StrictUndefined


DAGS = Path(__file__).resolve().parents[2] / "airflow/dags"
SPEC = spec_from_file_location("monthly_dates", DAGS / "dbt_ga4_monthly_dates.py")
DATES = module_from_spec(SPEC)
SPEC.loader.exec_module(DATES)


class MonthlyDatesTests(unittest.TestCase):
    def prepare(self, today, conf=None, run_type="scheduled", scheduled=None):
        scheduled = scheduled or datetime(2026, 9, 1, 3, tzinfo=timezone.utc)
        with patch.object(DATES, "execution_day", return_value=today):
            return DATES.prepare_monthly_window(
                dag_run=SimpleNamespace(conf=conf, run_type=run_type),
                data_interval_start=scheduled,
            )

    def test_on_time_and_delayed_keep_the_same_start(self):
        normal = self.prepare(date(2026, 9, 1))
        delayed = self.prepare(date(2026, 9, 5))
        self.assertEqual(normal["start_date"], "20260802")
        self.assertEqual(delayed["start_date"], "20260802")
        self.assertEqual(normal["end_date"], "20260831")
        self.assertEqual(delayed["end_date"], "20260904")
        # Clearing validation on a later retry extends the range again.
        self.assertEqual(self.prepare(date(2026, 9, 7))["end_date"], "20260906")

    def test_manual_date_keys_are_rejected_even_when_empty(self):
        for conf in (
            {"start_date": "20260601", "end_date": "20260630"},
            {"start_date": ""}, {"end_date": None},
            {"start_date": "20260802", "end_date": "20260904"},
        ):
            with self.subTest(conf=conf), self.assertRaises(ValueError):
                self.prepare(date(2026, 9, 5), conf=conf, run_type="manual")

    def test_manual_without_dates_uses_current_month(self):
        window = self.prepare(
            date(2026, 9, 5), run_type="manual",
            scheduled=datetime(2026, 6, 1, tzinfo=timezone.utc),
        )
        self.assertEqual(window["start_date"], "20260802")
        self.assertEqual(window["end_date"], "20260904")

    def test_sensor_waits_for_actual_day_kst_daily(self):
        window = self.prepare(date(2026, 9, 5))
        ti = SimpleNamespace(xcom_pull=lambda **_: window)
        with patch.object(DATES, "execution_day", return_value=date(2026, 9, 5)):
            logical_date = DATES.monthly_daily_logical_date(None, ti=ti)
        self.assertEqual(logical_date.hour, 9)
        self.assertEqual(logical_date.astimezone(timezone.utc), datetime(2026, 9, 5, tzinfo=timezone.utc))

    def test_actual_dag_templates_share_window_and_reject_stale_retry(self):
        tree = ast.parse((DAGS / "dbt_ga4_monthly.py").read_text(encoding="utf-8"))
        dag = next(node for node in ast.walk(tree) if isinstance(node, ast.Call) and isinstance(node.func, ast.Name) and node.func.id == "DbtDag")
        args = ast.literal_eval(next(kw.value for kw in dag.keywords if kw.arg == "operator_args"))
        window = self.prepare(date(2026, 9, 5))
        ti = SimpleNamespace(xcom_pull=lambda **_: window)
        env = Environment(undefined=StrictUndefined)
        for key in ("start_date", "end_date"):
            template = env.from_string(args["vars"][key])
            with patch.object(DATES, "execution_day", return_value=date(2026, 9, 5)):
                self.assertEqual(template.render(ti=ti, monthly_date_var=DATES.monthly_date_var), window[key])
            with patch.object(DATES, "execution_day", return_value=date(2026, 9, 6)), self.assertRaises(ValueError):
                template.render(ti=ti, monthly_date_var=DATES.monthly_date_var)
        with patch.object(DATES, "execution_day", return_value=date(2026, 9, 6)), self.assertRaises(ValueError):
            DATES.monthly_daily_logical_date(None, ti=ti)

    def test_missing_window_and_bad_schedule_fail(self):
        with self.assertRaises(ValueError):
            DATES.monthly_date_var(None, "end_date")
        with self.assertRaises(ValueError):
            self.prepare(date(2026, 8, 31))
        with self.assertRaises(ValueError):
            self.prepare(date(2026, 9, 5), scheduled=datetime(2026, 9, 1))

    def test_kst_boundary_and_leap_year(self):
        window = self.prepare(
            date(2024, 3, 1), scheduled=datetime(2024, 2, 29, 15, tzinfo=timezone.utc)
        )
        self.assertEqual(window["start_date"], "20240131")
        self.assertEqual(window["end_date"], "20240229")


if __name__ == "__main__":
    unittest.main()
