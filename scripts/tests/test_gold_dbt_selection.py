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
from importlib.util import module_from_spec, spec_from_file_location
_selection_spec=spec_from_file_location('silver_selection_policy',
    Path(__file__).resolve().parents[2]/'airflow/dags/dbt_ga4_silver_selection.py')
_selection_module=module_from_spec(_selection_spec)
_selection_spec.loader.exec_module(_selection_module)
silver_selection=_selection_module.silver_selection

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

    def selected(self,selection,exclude=(),variables=None,resource_type='test'):
        args = ['--quiet','ls','--project-dir',str(self.project),'--profiles-dir',str(self.project),
                '--target','dev','--target-path',str(self.target),'--resource-type',resource_type,
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
        self.assertFalse({n for n in names if n.startswith(('assert_gold_44_20','assert_silver_logging_v1'))
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

    def test_stage_v2_daily_monthly_models_and_tests(self):
        env=dict(DBT_TARGET='dev',KOIN_DATA_GCP_PROJECT='koin-stage-438512',
                 KOIN_DATA_GA4_PROJECT='koin-stage-438512',KOIN_DATA_GA4_DATASET='stage_events',
                 KOIN_DATA_APP_DB_PROJECT='koin-stage-438512',KOIN_DATA_APP_DB_DATASET='stage_users',
                 KOIN_DATA_SILVER_V2_ONLY='true',KOIN_DATA_SILVER_BOOTSTRAP_COMPLETE='true')
        env['KOIN_DATA_SILVER_SOURCE_CONTRACT']=json.dumps(dict(
            {k:env[k] for k in ['KOIN_DATA_GA4_PROJECT','KOIN_DATA_GA4_DATASET',
                                'KOIN_DATA_APP_DB_PROJECT','KOIN_DATA_APP_DB_DATASET']},
            evidence='synthetic only'))
        for tag in ['airflow_daily','airflow_monthly']:
            config=silver_selection(tag,env)
            with self.subTest(tag=tag):
                models=self.selected(config['select'],config['exclude'],resource_type='model')
                self.assertEqual(models,{'silver_events_v2','silver__users'})
                tests=self.selected(config['select'],config['exclude'])
                self.assertTrue(tests)
                self.assert_no_gold(tests)
                manifest=json.loads((self.target/'manifest.json').read_text())
                nodes={n['name']:n for n in manifest['nodes'].values() if n['resource_type']=='test'}
                for name in tests:
                    model_deps={d for d in nodes[name]['depends_on']['nodes'] if d.startswith('model.')}
                    self.assertTrue(model_deps <= {'model.koin_data.silver_events_v2','model.koin_data.silver__users'})


if __name__ == '__main__':
    unittest.main()
