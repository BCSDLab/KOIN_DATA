"""합성 입력으로 공개 직전 검사만 재현하는 SQL을 생성한다.

실제 Silver/Gold 참조와 물리 테이블 공개 부분은 포함하지 않는다.
실행 도구가 아니며 BigQuery에 보낼 검증 SQL을 stdout으로 출력한다.
"""
import argparse
import json
from pathlib import Path
import re

from gold_stage import publication_sql

SCENARIOS = {
    'valid': '',
    'missing_retention': """DELETE FROM mart_service_metrics_daily_candidate
WHERE metric_type='retention_daily' AND period_n=7;\n""",
    'funnel_without_source': """UPDATE mart_kpi_user_daily_candidate
SET funnel_session_facts=ARRAY(SELECT AS STRUCT f.* REPLACE(
  ARRAY(SELECT TIMESTAMP_ADD(t,INTERVAL 1 MICROSECOND)
    FROM UNNEST(f.step_reached_at) t WITH OFFSET n ORDER BY n) AS step_reached_at)
  FROM UNNEST(funnel_session_facts) f)
WHERE ARRAY_LENGTH(funnel_session_facts)>0;\n""",
}


def regression_sql(p, target, scenario='valid'):
    script = publication_sql(p,target)
    script = script[:script.index('CREATE TABLE IF NOT EXISTS')]
    fixture = (target/'compiled/koin_data/tests/assert_gold_44_20_fixture.sql').read_text()
    fixture_ctes = fixture[:fixture.index('\nu as (')].rstrip().rstrip(',')
    setup = ('CREATE TEMP TABLE regression_events AS ('+fixture_ctes+' SELECT * FROM fixture_events);\n'
             'CREATE TEMP TABLE regression_users AS ('+fixture_ctes+' SELECT * FROM fixture_users);\n')
    for table, replacement in [('silver_events_v2','regression_events'),('silver__users','regression_users')]:
        for ref in [f'`koin-stage-438512.silver.{table}`',f'`koin-stage-438512`.`silver`.`{table}`']:
            script = re.sub(re.escape(ref)+r'\s+for system_time as of timestamp\([^)]*\)',
                            replacement,script,flags=re.I)
    if re.search(r'koin-stage-438512|kap-chat|BEGIN TRANSACTION|CREATE TABLE IF NOT EXISTS',script,re.I):
        raise ValueError('Synthetic regression still contains a real relation or publication')
    first_check = script.rfind('ASSERT NOT EXISTS(',0,script.index('AS "assert_gold_44_20_input"'))
    script = script[:first_check]+SCENARIOS[scenario]+script[first_check:]
    return setup+script+'\nSELECT "all_candidate_checks_passed" AS result;\n'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--contract',type=Path,required=True)
    parser.add_argument('--target',type=Path,required=True)
    parser.add_argument('--scenario',choices=SCENARIOS,default='valid')
    args = parser.parse_args()
    print(regression_sql(json.loads(args.contract.read_text()),args.target,args.scenario),end='')


if __name__ == '__main__':
    main()
