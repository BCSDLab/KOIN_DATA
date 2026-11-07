"""새 명세 카탈로그의 중복·범위·근거 및 퍼널 격리를 DB 접속 없이 검사한다."""
import ast
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


def tuples(path):
    text = path.read_text(encoding='utf-8')
    literal = text.split('{% set rules = ', 1)[1].split(' %}', 1)[0]
    return ast.literal_eval(literal.replace('none', 'None').replace('true', 'True').replace('false', 'False'))


class NewLoggingCatalogTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.rows = tuples(ROOT/'dbt/macros/silver_logging_v1_catalog.sql')
        cls.original = tuples(ROOT/'dbt/macros/silver_logging_v1.sql')
        cls.evidence = json.loads((ROOT/'docs/silver_logging_v1_catalog_20261107.json').read_text(encoding='utf-8'))

    def test_exact_contract_keys_are_unique(self):
        keys = [(r[0],r[1],r[2],r[4]) for r in self.rows]
        self.assertEqual(len(keys),len(set(keys)))

    def test_existing_platform_and_funnel_contracts_not_overridden(self):
        original_labels = {r[0] for r in self.original}
        self.assertFalse(original_labels & {r[0] for r in self.rows})

    def test_catalog_matches_reviewed_source_contracts(self):
        expected = {tuple(r[k] for k in ('label','owner','category','service','platform','entry','id'))
                    for r in self.evidence['contracts']}
        self.assertEqual(set(self.rows),expected)
        for r in self.evidence['contracts']:
            self.assertIn('https://app.notion.com/p/'+r['id'],r['sources'])

    def test_frozen_and_excluded_services_are_absent(self):
        for r in self.rows:
            self.assertNotIn(r[0].split('__')[0],{'team_recruit','club','grad_calc'})
            self.assertNotIn('soldout',r[0])
            self.assertNotIn('abtest',r[0])

    def test_names_category_platform_and_provenance(self):
        for label,owner,category,service,platform,entry,page in self.rows:
            self.assertIn(len(label.split('__')),(4,5))
            self.assertEqual(label.split('__')[-1],category)
            self.assertIn(owner,('DA1','DA2'))
            self.assertIn(platform,('WEB','ANDROID','IOS'))
            self.assertIsInstance(entry,bool)
            self.assertRegex(page,r'^[0-9a-f]{32}$')

    def test_logical_main_click_is_not_main_visit(self):
        rows = [r for r in self.rows if r[0]=='main__main__navigation__main_entry__click']
        self.assertTrue(rows)
        self.assertTrue(all(r[3]=='main' and r[5] is False for r in rows))

    def test_bus_other_routes_are_not_search_funnel(self):
        rows = [r for r in self.rows if r[0] in {
            'main__main__bus_entry__timetable_entry__click',
            'main__main__bus_entry__ticket_entry__click'}]
        self.assertTrue(rows)
        self.assertTrue(all(len(r)==7 and r[3]=='bus' and r[5] is True for r in rows))


if __name__ == '__main__':
    unittest.main()
