"""새 Silver 매핑과 Silver→Gold 합성 검사를 DB 접속 없이 컴파일한다.

실제 로깅 배포·입력 검증 플래그나 BigQuery 테이블은 변경하지 않는다.
"""
import argparse
import json
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def compile_offline(target, synthetic_model=False):
    from dbt.cli.main import dbtRunner
    from dbt.flags import get_flags
    from dbt.config.runtime import RuntimeConfig
    from dbt.compilation import Compiler

    os.environ.update(KOIN_DATA_GCP_PROJECT='koin-stage-438512',
        KOIN_DATA_BIGQUERY_LOCATION='asia-northeast3',KOIN_DATA_GA4_PROJECT='koin-stage-438512',
        KOIN_DATA_GA4_DATASET='analytics_427218788',KOIN_DATA_APP_DB_PROJECT='koin-stage-438512',
        KOIN_DATA_APP_DB_DATASET='analytics_427218788',DBT_SEND_ANONYMOUS_USAGE_STATS='false',
        DBT_LOG_PATH=str(target/'logs'))
    # Default: enable synthetic tests only. --synthetic-model also compiles the
    # enabled model branch with fake scopes; neither path executes a model.
    variables = {'silver_logging_validation_enabled':True}
    if synthetic_model:
        variables.update(silver_logging_v1_enabled=True,silver_logging_v1_scopes=[
            dict(platform=p,event_name=n,start_dt='2026-10-01',end_dt='2026-11-30',
                 evidence='SYNTHETIC compilation only; not deployment')
            for p in ['WEB','ANDROID','IOS'] for n in ['DA1','DA2']])
    result = dbtRunner().invoke(['--no-use-colors','parse','--project-dir',str(ROOT/'dbt'),
        '--profiles-dir',str(ROOT/'dbt'),'--target','dev','--target-path',str(target),
        '--vars',json.dumps(variables)])
    if not result.success:
        raise RuntimeError('dbt parse failed')
    manifest = result.result
    compiler = Compiler(RuntimeConfig.from_args(get_flags()))
    selected = []
    for node in manifest.nodes.values():
        if node.name=='silver_events_v2' or 'silver_logging_v1_fixture' in node.tags:
            compiler.compile_node(node,manifest)
            selected.append(node.name)
    required = {'silver_events_v2','assert_silver_logging_v1_mapping_fixture',
                'assert_silver_logging_v1_gold_fixture','assert_silver_logging_v1_all_contracts',
                'assert_silver_logging_v1_unknown_rejected','assert_silver_logging_v1_route_rejected'}
    if not required <= set(selected):
        raise ValueError('Silver synthetic validations missing')
    (target/'silver_logging_compile_summary.json').write_text(json.dumps({
        'compiled':selected,'compiled_mapping_enabled':synthetic_model,'execution_performed':False,'logging_deployed':False,
        'coverage_verified':False,'mapping_verified':False},indent=2))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--target',type=Path,required=True)
    parser.add_argument('--synthetic-model',action='store_true',help='합성 범위로 모델 opt-in 컴파일만 수행')
    args=parser.parse_args()
    compile_offline(args.target,args.synthetic_model)
