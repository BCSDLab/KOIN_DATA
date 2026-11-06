"""DB 접속 없이 실제 dbt ls로 Silver/Gold 테스트 선택 격리를 검증한다."""
import contextlib
import io
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import gold_stage

SILVER_READERS = {
    'assert_gold_44_20_input','assert_gold_44_20_naming',
    'assert_gold_44_20_new_mapping_examples','assert_gold_44_20_funnel_source',
}


class DbtSelectionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        try:
            from dbt.cli.main import dbtRunner
        except ImportError:
            raise unittest.SkipTest('dbt-bigquery environment required')
        cls.runner = dbtRunner
        cls.temp = tempfile.TemporaryDirectory()
        cls.addClassCleanup(cls.temp.cleanup)
        cls.project = Path(__file__).resolve().parents[2]/'dbt'
        cls.target = Path(cls.temp.name)/'target'
        env = patch.dict(os.environ,dict(
            KOIN_DATA_GCP_PROJECT='koin-stage-438512',KOIN_DATA_BIGQUERY_LOCATION='asia-northeast3',
            KOIN_DATA_GA4_PROJECT='koin-stage-438512',KOIN_DATA_GA4_DATASET='analytics_427218788',
            KOIN_DATA_APP_DB_PROJECT='koin-stage-438512',KOIN_DATA_APP_DB_DATASET='analytics_427218788',
            DBT_SEND_ANONYMOUS_USAGE_STATS='false',DBT_LOG_PATH=str(Path(cls.temp.name)/'logs')))
        env.start()
        cls.addClassCleanup(env.stop)

    def selected(self,selection,exclude=(),variables=None):
        args = ['--quiet','ls','--project-dir',str(self.project),'--profiles-dir',str(self.project),
                '--target','dev','--target-path',str(self.target),'--resource-type','test',
                '--output','json','--output-keys','name','tags','--select',*selection]
        if exclude:
            args += ['--exclude',*exclude]
        if variables is not None:
            args += ['--vars',json.dumps(variables)]
        with contextlib.redirect_stdout(io.StringIO()):
            result = self.runner().invoke(args)
        self.assertTrue(result.success,str(result.exception))
        return {json.loads(n)['name'] if isinstance(n,str) else n['name'] for n in result.result}

    def assert_no_gold(self,names):
        self.assertFalse({n for n in names if n.startswith('assert_gold_44_20')
                          or 'mart_kpi_user_daily' in n or 'mart_service_metrics_daily' in n})

    def test_silver_models_exclude_gold_by_default(self):
        for selection in [('silver_events_v2',),('silver__users',),('silver_events_v2','silver__users')]:
            with self.subTest(selection=selection):
                self.assert_no_gold(self.selected(selection))

    def test_daily_and_monthly_exclude_gold_before_and_after_bootstrap(self):
        for tag in ['tag:airflow_daily','tag:airflow_monthly']:
            for exclude in [(),('tag:initial_load_required',)]:
                with self.subTest(tag=tag,exclude=exclude):
                    self.assert_no_gold(self.selected((tag,),exclude))

    def test_gold_tag_does_not_enable_silver_readers(self):
        names = self.selected(('tag:gold_44_20',))
        self.assertFalse(names & SILVER_READERS)

    def test_opt_in_requires_boolean_true(self):
        for value in [False,'true',1]:
            with self.subTest(value=value):
                names = self.selected(('tag:gold_44_20',),variables={'gold_validation_enabled':value})
                self.assertFalse(names & SILVER_READERS)

    def test_gold_opt_in_includes_required_and_generic_tests(self):
        names = self.selected(('tag:gold_44_20',),variables={'gold_validation_enabled':True})
        self.assertTrue(set(gold_stage.VALIDATION_NAMES)<=names)
        manifest = json.loads((self.target/'manifest.json').read_text())
        gold_stage.require_validation_inventory(manifest)
        generic = {n.split(':',1)[1] for n in gold_stage.generic_test_names(manifest)}
        self.assertEqual(len(generic),50)
        self.assertTrue(generic<=names)


if __name__ == '__main__':
    unittest.main()
