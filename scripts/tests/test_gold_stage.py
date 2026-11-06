"""공개 게이트·후보 바인딩·컴파일 산출물 변조에 대한 회귀 검사."""
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import gold_stage


def contract():
    p = dict(build_id='test_build', funnel_version='test_v1',
             snapshot_at='2026-12-01T00:00:00Z', computed_at='2026-12-01T00:00:00Z',
             logging_start_dt='2026-10-01', event_complete_start_dt='2026-10-01',
             event_complete_dt='2026-11-30', metric_start_dt='2026-10-01',
             metric_end_dt='2026-11-30', session_inactivity_minutes=30, late_arrival_hours=0,
             naming_scopes=[dict(platform='WEB', event_name='DA1', start_dt='2026-10-01',
                                 end_dt='2026-11-30', evidence='Synthetic test only')],
             approved_legacy_labels=[])
    for gate in gold_stage.GATES:
        p[gate] = True
        p[gate+'_evidence'] = 'Synthetic test only'
    return p


class PublicationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.target = Path(self.temp.name)
        self.p = contract()
        generic = 'generic:not_null_test'
        manifest = {'nodes': {'test': dict(name='not_null_test', resource_type='test',
                     test_metadata={'name':'not_null'}, depends_on={'nodes':[
                     'model.koin_data.mart_kpi_user_daily']})}}
        for name in gold_stage.VALIDATION_NAMES:
            manifest['nodes'][name] = dict(name=name,resource_type='test',config={'enabled':True})
        (self.target/'manifest.json').write_text(json.dumps(manifest))
        hashes = {}
        for name in list(gold_stage.ARTIFACTS)+[generic]:
            file = gold_stage.compiled_path(self.target,name)
            file.parent.mkdir(parents=True,exist_ok=True)
            text = ('select * from `koin-stage-438512`.`gold`.`mart_kpi_user_daily` '
                    'where event_dt is null') if name in gold_stage.VALIDATION_NAMES or name==generic else 'select 1'
            file.write_text(text)
            hashes[name] = hashlib.sha256(file.read_bytes()).hexdigest()
        self.lock = dict(contract=self.p, sha256=hashes, generic_checks=[generic])
        self.write_lock()

    def write_lock(self):
        (self.target/'gold_build_contract.json').write_text(json.dumps(self.lock))

    def test_all_checks_bind_candidates_before_transaction(self):
        sql = gold_stage.publication_sql(self.p,self.target)
        boundary = sql.index('BEGIN TRANSACTION;')
        for name in list(gold_stage.VALIDATION_NAMES)+self.lock['generic_checks']:
            self.assertLess(sql.index('AS "'+name+'"'),boundary)
        checks = sql[sql.index('AS "assert_gold_44_20_input"')-120:boundary]
        self.assertNotIn('`gold`',checks)
        self.assertIn('mart_kpi_user_daily_candidate', checks)
        self.assertLess(sql.index('SELECT * FROM gold_input_quality_candidate'),boundary)

    def test_unverified_gate_blocks(self):
        self.p['mapping_verified'] = False
        with self.assertRaisesRegex(ValueError,'Publication blocked'):
            gold_stage.publication_sql(self.p,self.target)

    def test_absent_scope_blocks(self):
        self.p['naming_scopes'] = []
        with self.assertRaisesRegex(ValueError,'naming_scopes'):
            gold_stage.publication_sql(self.p,self.target)

    def test_scope_requires_evidence(self):
        self.p['naming_scopes'][0]['evidence'] = ''
        with self.assertRaisesRegex(ValueError,'evidence'):
            gold_stage.validate_contract(self.p,True)

    def test_legacy_wildcard_rejected(self):
        self.p['approved_legacy_labels'] = [dict(platform='WEB',event_name='DA1',
            event_label='cafeteria%',event_category='click',evidence='test',source_url='https://example.com')]
        with self.assertRaisesRegex(ValueError,'no patterns'):
            gold_stage.validate_contract(self.p,True)

    def test_changed_validation_sql_blocks(self):
        file = gold_stage.compiled_path(self.target,'assert_gold_44_20_retention_grid')
        file.write_text('select 1 where false')
        with self.assertRaisesRegex(ValueError,'Compiled SQL changed'):
            gold_stage.publication_sql(self.p,self.target)

    def test_changed_generic_test_blocks(self):
        gold_stage.compiled_path(self.target,'generic:not_null_test').write_text('select 0')
        with self.assertRaisesRegex(ValueError,'Compiled SQL changed'):
            gold_stage.publication_sql(self.p,self.target)

    def test_changed_contract_blocks(self):
        self.p['build_id'] = 'different'
        with self.assertRaisesRegex(ValueError,'Compile contract differs'):
            gold_stage.publication_sql(self.p,self.target)

    def test_disabled_required_test_blocks_even_with_old_compiled_sql(self):
        path = self.target/'manifest.json'
        manifest = json.loads(path.read_text())
        manifest['nodes']['assert_gold_44_20_input']['config']['enabled'] = False
        path.write_text(json.dumps(manifest))
        with self.assertRaisesRegex(ValueError,'Required Gold tests disabled'):
            gold_stage.publication_sql(self.p,self.target)

    def test_missing_required_test_blocks_even_with_old_compiled_sql(self):
        path = self.target/'manifest.json'
        manifest = json.loads(path.read_text())
        del manifest['nodes']['assert_gold_44_20_naming']
        path.write_text(json.dumps(manifest))
        with self.assertRaisesRegex(ValueError,'Required Gold tests disabled'):
            gold_stage.publication_sql(self.p,self.target)


if __name__ == '__main__':
    unittest.main()
