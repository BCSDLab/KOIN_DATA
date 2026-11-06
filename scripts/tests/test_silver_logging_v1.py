"""신규 분류의 opt-in·Stage·기간 게이트와 명세 카탈로그를 검증한다."""
import datetime
import re
from pathlib import Path
from types import SimpleNamespace
import unittest

from jinja2 import Environment,StrictUndefined

ROOT = Path(__file__).resolve().parents[2]


class Returned(Exception):
    def __init__(self,value):
        self.value = value


def returned(value):
    raise Returned(value)


def compiler_error(message):
    raise ValueError(message)


def module(target=None,variables=None):
    env = Environment(undefined=StrictUndefined,extensions=['jinja2.ext.do'])
    return env.from_string((ROOT/'dbt/macros/silver_logging_v1.sql').read_text()).make_module({
        'return':returned,'target':target or SimpleNamespace(name='dev',database='koin-stage-438512'),
        'var':lambda name,default=None:(variables or {}).get(name,default),
        'exceptions':SimpleNamespace(raise_compiler_error=compiler_error),
        'modules':SimpleNamespace(datetime=datetime,re=re),
    })


class SilverLoggingTests(unittest.TestCase):
    def test_every_platform_contract_has_independent_expected_result(self):
        with self.assertRaises(Returned) as result:
            module().silver_logging_v1_rules()
        rules=result.exception.value
        env=Environment(undefined=StrictUndefined,extensions=['jinja2.ext.do'])
        expected_module=env.from_string((ROOT/'dbt/macros/silver_logging_v1_expected.sql').read_text()).make_module({'return':returned})
        with self.assertRaises(Returned) as result:
            expected_module.silver_logging_v1_expected_contracts()
        expected=result.exception.value
        actual={(r[0],r[1],r[2],p):(r[3],r[4],r[7] if len(r)>7 else 'any')
                for r in rules for p in r[5]}
        oracle={(r[0],r[1],r[2],r[3]):(r[4],r[5],r[9]) for r in expected}
        self.assertEqual(len(expected),86)
        self.assertEqual(len(actual),86)
        self.assertEqual(actual,oracle)

    def test_rule_keys_unique_and_sources_present(self):
        with self.assertRaises(Returned) as result:
            module().silver_logging_v1_rules()
        keys=[]
        for row in result.exception.value:
            label,owner,category,service,stage,platforms,source = row[:7]
            self.assertRegex(source,r'^[0-9a-f]{32}$')
            self.assertEqual(label.split('__')[-1],category)
            self.assertIn(owner,['DA1','DA2'])
            for platform in platforms:
                keys.append((label,owner,category,platform))
            self.assertNotEqual(service,'main')
            self.assertNotIn(stage,['form_entry','signup_complete','main'])
        self.assertEqual(len(keys),len(set(keys)))

    def test_prod_target_blocked(self):
        for target in [SimpleNamespace(name='prod',database='koin-stage-438512'),
                       SimpleNamespace(name='dev',database='kap-chat')]:
            with self.subTest(target=target),self.assertRaisesRegex(ValueError,'Stage-only'):
                module(target).silver_logging_v1_classify('events')

    def test_missing_scope_blocked(self):
        with self.assertRaisesRegex(ValueError,'Explicit silver_logging_v1_scopes'):
            module().silver_logging_v1_classify('events')

    def test_invalid_scope_blocked(self):
        cases=[dict(platform='ANY',event_name='DA1',evidence='test'),
               dict(platform='WEB',event_name='DA1',evidence=''),
               dict(platform='WEB',event_name='DA1',evidence='test',start_dt='2026-02-30',end_dt='2026-03-01'),
               dict(platform='WEB',event_name='DA1',evidence='test',start_dt='2026-11-01',end_dt='2026-10-01')]
        for case in cases:
            with self.subTest(case=case),self.assertRaises(ValueError):
                module().silver_logging_v1_classify('events',[case])

    def test_legacy_patterns_blocked(self):
        scope=dict(platform='WEB',event_name='DA1',start_dt='2026-10-01',end_dt='2026-11-30',evidence='synthetic')
        legacy=dict(scope,event_label='bus__old__%',event_category='click',source_url='https://example.com')
        with self.assertRaisesRegex(ValueError,'no patterns'):
            module().silver_logging_v1_classify('events',[scope],[legacy])


if __name__=='__main__':
    unittest.main()
