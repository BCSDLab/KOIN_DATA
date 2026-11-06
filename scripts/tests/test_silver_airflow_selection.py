"""Stage V2 전환의 실제 선택 정책·환경 차단·기존 일별 날짜 계약 검사."""

import ast
import re
from datetime import datetime, timedelta, timezone
from importlib.util import module_from_spec, spec_from_file_location
from pathlib import Path
from types import SimpleNamespace
import unittest
from unittest.mock import patch

from jinja2 import Environment, StrictUndefined

DAGS = Path(__file__).resolve().parents[2] / "airflow/dags"
_spec=spec_from_file_location('silver_selection_policy',DAGS/'dbt_ga4_silver_selection.py')
_policy=module_from_spec(_spec)
_spec.loader.exec_module(_policy)
silver_selection=_policy.silver_selection
validate_stage_silver_environment=_policy.validate_stage_silver_environment


def stage_env():
    return dict(DBT_TARGET="dev", KOIN_DATA_GCP_PROJECT="koin-stage-438512",
                KOIN_DATA_GA4_PROJECT="koin-stage-438512", KOIN_DATA_GA4_DATASET="stage_events",
                KOIN_DATA_APP_DB_PROJECT="koin-stage-438512", KOIN_DATA_APP_DB_DATASET="stage_users",
                KOIN_DATA_SILVER_V2_ONLY="true", KOIN_DATA_SILVER_BOOTSTRAP_COMPLETE="true")


def load_function(file, name, namespace):
    tree = ast.parse((DAGS / file).read_text())
    node = next(n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == name)
    exec(compile(ast.Module(body=[node], type_ignores=[]), str(DAGS / file), "exec"), namespace)
    return namespace[name]


class SilverAirflowSelectionTests(unittest.TestCase):
    def test_default_and_existing_bootstrap_selection_are_preserved(self):
        self.assertEqual(silver_selection("airflow_daily", {}),
                         dict(select=["tag:airflow_daily"], exclude=["tag:initial_load_required"]))
        self.assertEqual(silver_selection("airflow_daily", {"KOIN_DATA_SILVER_BOOTSTRAP_COMPLETE":"true"}),
                         dict(select=["tag:airflow_daily"], exclude=[]))

    def test_v2_requires_stage_output_and_both_explicit_sources(self):
        for key in ["KOIN_DATA_GCP_PROJECT", "KOIN_DATA_GA4_PROJECT", "KOIN_DATA_APP_DB_PROJECT"]:
            for bad in [None, "kap-chat"]:
                env = stage_env()
                if bad is None:
                    env.pop(key)
                else:
                    env[key] = bad
                with self.subTest(key=key,bad=bad), self.assertRaises(ValueError):
                    silver_selection("airflow_daily", env)
        for key in ["KOIN_DATA_GA4_DATASET", "KOIN_DATA_APP_DB_DATASET"]:
            env=stage_env(); env[key]=""
            with self.subTest(key=key), self.assertRaises(ValueError):
                silver_selection("airflow_daily", env)

    def test_v2_blocks_prod_and_incomplete_bootstrap(self):
        for override in [{"DBT_TARGET":"prod"}, {"KOIN_DATA_SILVER_BOOTSTRAP_COMPLETE":"false"},
                         {"KOIN_DATA_SILVER_BOOTSTRAP_COMPLETE":""}, {"KOIN_DATA_SILVER_V2_ONLY":"yes"}]:
            with self.subTest(override=override), self.assertRaises(ValueError):
                silver_selection("airflow_daily", dict(stage_env(), **override))

    def test_legacy_prod_policy_does_not_require_stage_sources(self):
        validate_stage_silver_environment({"DBT_TARGET":"prod"})

    def test_runtime_blocks_changed_v2_environment(self):
        with self.assertRaises(ValueError):
            validate_stage_silver_environment({}, require_v2=True)
        for override in [{"KOIN_DATA_APP_DB_PROJECT":"kap-chat"}, {"KOIN_DATA_SILVER_BOOTSTRAP_COMPLETE":"false"}]:
            with self.subTest(override=override), self.assertRaises(ValueError):
                validate_stage_silver_environment(dict(stage_env(),**override), require_v2=True)

    def test_monthly_runtime_guard_runs_before_date_planning(self):
        planned=[]
        fn=load_function("dbt_ga4_monthly.py", "prepare_validated_monthly_window", {
            "validate_stage_silver_environment":validate_stage_silver_environment,
            "prepare_monthly_window":lambda **ctx:planned.append(ctx) or {"ok":True}})
        with patch.dict("os.environ",stage_env(),clear=True):
            self.assertEqual(fn(stage_v2_required=True), {"ok":True})
        planned.clear()
        with patch.dict("os.environ",{},clear=True), self.assertRaises(ValueError):
            fn(stage_v2_required=True)
        self.assertEqual(planned,[])

    def test_daily_runtime_guard_rejects_environment_change(self):
        fn=load_function("dbt_ga4_common.py", "validate_conf_dates", {
            "validate_stage_silver_environment":validate_stage_silver_environment,
            "DATE_PATTERN":re.compile(r"^\d{8}$"), "Any":object})
        with patch.dict("os.environ",stage_env(),clear=True):
            fn(stage_v2_required=True)
        with patch.dict("os.environ",{},clear=True), self.assertRaises(ValueError):
            fn(stage_v2_required=True)

    def test_daily_recent_three_days_and_manual_dates_unchanged(self):
        fn=load_function("dbt_ga4_common.py", "create_date_vars", {})
        templates=fn(3)
        kst=timezone(timedelta(hours=9))
        env=Environment(undefined=StrictUndefined)
        def render(conf):
            return {k:env.from_string(v).render(dag_run=SimpleNamespace(conf=conf),
                       data_interval_start=datetime(2026,11,6,9,tzinfo=kst),
                       macros=SimpleNamespace(timedelta=timedelta),
                       ) for k,v in templates.items()}
        env.filters["ds_nodash"]=lambda value:value.strftime("%Y%m%d")
        self.assertEqual(render({}), {"start_date":"20261103","end_date":"20261105"})
        self.assertEqual(render({"start_date":"20261001","end_date":"20261003"}),
                         {"start_date":"20261001","end_date":"20261003"})

    def test_daily_and_monthly_crons_unchanged(self):
        for file,cron in [("dbt_ga4_daily.py","0 9 * * *"),("dbt_ga4_monthly.py","0 12 1 * *")]:
            tree=ast.parse((DAGS/file).read_text())
            crons=[ast.literal_eval(n.args[0]) for n in ast.walk(tree) if isinstance(n,ast.Call)
                   and isinstance(n.func,ast.Name) and n.func.id=="create_cron_schedule"]
            self.assertEqual(crons,[cron])

    def test_daily_partition_writes_are_serialized(self):
        tree=ast.parse((DAGS/'dbt_ga4_daily.py').read_text())
        dag=next(n for n in ast.walk(tree) if isinstance(n,ast.Call)
                 and isinstance(n.func,ast.Name) and n.func.id=='DbtDag')
        limit=next(k.value for k in dag.keywords if k.arg=='max_active_runs')
        self.assertEqual(ast.literal_eval(limit),1)


if __name__ == "__main__":
    unittest.main()
