"""Compile Gold and generate guarded Stage-only joint publication SQL.

No BigQuery writes are performed by this utility. SQL must be inspected and
executed as one script after all input-contract gates pass.
"""
import argparse
import datetime as dt
import json
import hashlib
import os
from pathlib import Path
import re
import subprocess

from gold_schema import TABLES, schema_sql

ROOT = Path(__file__).resolve().parents[1]
STAGE = 'koin-stage-438512'
GATES = ('logging_deployed', 'coverage_verified', 'signup_verified', 'mapping_verified', 'session_verified')


def validate_contract(p, publish=False):
    for key in ('snapshot_at', 'computed_at'):
        dt.datetime.fromisoformat(p[key].replace('Z', '+00:00'))
        if dt.datetime.fromisoformat(p[key].replace('Z', '+00:00')).tzinfo is None:
            raise ValueError(f'{key}: timezone required')
    dates = {k: dt.date.fromisoformat(p[k]) for k in (
        'logging_start_dt', 'event_complete_start_dt', 'event_complete_dt', 'metric_start_dt', 'metric_end_dt')}
    if dates['event_complete_start_dt'] > dates['event_complete_dt']:
        raise ValueError('Invalid completeness interval')
    if dates['metric_start_dt'] > dates['metric_end_dt']:
        raise ValueError('Invalid metric interval')
    for key in ('build_id', 'funnel_version'):
        if not re.fullmatch(r'[A-Za-z0-9_.:-]+', p[key]):
            raise ValueError(f'Invalid {key}')
    for gate in GATES:
        if type(p.get(gate)) is not bool:
            raise ValueError(f'{gate}: a boolean is required')
    for key in ('session_inactivity_minutes', 'late_arrival_hours'):
        if type(p.get(key)) is not int or p[key] < 0:
            raise ValueError(f'{key}: non-negative integer required')
    if publish:
        blocked = [g for g in GATES if p[g] is not True]
        if blocked:
            raise ValueError('Publication blocked: ' + ', '.join(blocked))
        if (p['build_id'] == 'compile_only' or 'draft' in p['funnel_version'].lower()
                or p['session_inactivity_minutes'] <= 0):
            raise ValueError('Real build identity and approved session timeout required')
        for gate in GATES:
            if not isinstance(p.get(gate + '_evidence'), str) or not p[gate + '_evidence'].strip():
                raise ValueError(f'{gate}_evidence required')
        if dates['event_complete_start_dt'] < dates['logging_start_dt']:
            raise ValueError('Cannot certify new logging before deployment')
        if dates['metric_end_dt'] > dates['event_complete_dt']:
            raise ValueError('Snapshot range exceeds complete interval')


def compile_models(p, dbt, target, offline=False):
    validate_contract(p)
    env = dict(os.environ)
    env.update(KOIN_DATA_GCP_PROJECT=STAGE, KOIN_DATA_BIGQUERY_LOCATION='asia-northeast3',
               KOIN_DATA_GA4_PROJECT=STAGE, KOIN_DATA_GA4_DATASET='analytics_427218788',
               KOIN_DATA_APP_DB_PROJECT=STAGE, KOIN_DATA_APP_DB_DATASET='analytics_427218788',
               DBT_SEND_ANONYMOUS_USAGE_STATS='false', DBT_LOG_PATH=str(target / 'logs'))
    variables = json.dumps({'gold_build': p, 'event_complete_start_dt': p['event_complete_start_dt'],
                            'event_complete_dt': p['event_complete_dt']})
    base = [dbt, '--no-use-colors', '--no-populate-cache']
    options = ['--project-dir', str(ROOT / 'dbt'), '--profiles-dir', str(ROOT / 'dbt'),
               '--target', 'dev', '--target-path', str(target), '--vars', variables]
    if offline:
        # The normal CLI opens an ADC connection even with --no-introspect.
        # Use dbt's real parser/compiler without opening any database connection.
        from dbt.cli.main import dbtRunner
        from dbt.flags import get_flags
        from dbt.config.runtime import RuntimeConfig
        from dbt.compilation import Compiler
        os.environ.update(env)
        parsed = dbtRunner().invoke(['--no-use-colors', 'parse'] + options)
        if not parsed.success:
            raise RuntimeError('dbt parse failed')
        manifest_object = parsed.result
        config = RuntimeConfig.from_args(get_flags())
        compiler = Compiler(config)
        for node in manifest_object.nodes.values():
            if node.name in TABLES or 'gold_44_20' in node.tags or 'gold_44_20_fixture' in node.tags:
                compiler.compile_node(node, manifest_object)
    else:
        subprocess.run(base + ['parse'] + options, check=True, env=env)
        subprocess.run(base + ['compile', '--no-introspect', '--select', 'tag:gold_44_20'] + options,
                       check=True, env=env)
    manifest = json.loads((target / 'manifest.json').read_text())
    for name in TABLES:
        node = manifest['nodes']['model.koin_data.' + name]
        expected = {'model.koin_data.silver_events_v2', 'model.koin_data.silver__users'}
        if set(node['depends_on']['nodes']) != expected or node['database'] != STAGE:
            raise ValueError('Unexpected dependency or project: ' + name)
    for source in manifest['sources'].values():
        if source['database'] != STAGE:
            raise ValueError('Non-Stage source in manifest')
    hashes = {n: hashlib.sha256((target / 'compiled/koin_data/models/gold' / (n+'.sql')).read_bytes()).hexdigest()
              for n in TABLES}
    (target / 'gold_build_contract.json').write_text(json.dumps({'contract': p, 'sha256': hashes}, sort_keys=True, indent=2))


def publication_sql(p, target):
    validate_contract(p, publish=True)
    lock = json.loads((target / 'gold_build_contract.json').read_text())
    if lock['contract'] != p:
        raise ValueError('Compile contract differs from publication contract; recompile')
    for n in TABLES:
        path = target / 'compiled/koin_data/models/gold' / (n+'.sql')
        if hashlib.sha256(path.read_bytes()).hexdigest() != lock['sha256'][n]:
            raise ValueError('Compiled SQL changed: ' + n)
    queries = {n: (target / 'compiled/koin_data/models/gold' / (n + '.sql')).read_text().strip().rstrip(';')
               for n in TABLES}
    for q in queries.values():
        if 'kap-chat' in q or '2000-01-01' in q:
            raise ValueError('Unresolved or cross-environment SQL')
    event_input = (f'`{STAGE}.silver.silver_events_v2` FOR SYSTEM_TIME AS OF '
                   f"TIMESTAMP('{p['snapshot_at']}')")
    user_input = (f'`{STAGE}.silver.silver__users` FOR SYSTEM_TIME AS OF '
                  f"TIMESTAMP('{p['snapshot_at']}')")
    cutover = f"event_dt>=DATE('{p['logging_start_dt']}')"
    # Read-only checks are repeated on exactly the frozen inputs used by both models.
    sql = [
        f'ASSERT (SELECT COUNT(*)>0 FROM {event_input} WHERE {cutover}) AS "No post-deployment events";',
        f'ASSERT NOT EXISTS(SELECT event_id FROM {event_input} WHERE {cutover} GROUP BY event_id '
        'HAVING event_id IS NULL OR COUNT(*)!=1) AS "Silver event key";',
        f'ASSERT NOT EXISTS(SELECT user_pseudo_id FROM {user_input} GROUP BY user_pseudo_id '
        'HAVING user_pseudo_id IS NULL OR COUNT(*)!=1) AS "Silver user key";',
        f'ASSERT NOT EXISTS(SELECT 1 FROM {event_input} e LEFT JOIN {user_input} u USING(user_pseudo_id) '
        f'WHERE e.{cutover} AND e.user_pseudo_id IS NOT NULL AND '
        '(u.user_pseudo_id IS NULL OR u.first_seen_at IS NULL)) AS "Silver relationship";',
        f'ASSERT NOT EXISTS(SELECT 1 FROM {user_input} u LEFT JOIN {event_input} e '
        'ON u.user_pseudo_id=e.user_pseudo_id AND e.event_dt=DATE(u.first_seen_at) '
        f"WHERE DATE(u.first_seen_at) BETWEEN DATE('{p['event_complete_start_dt']}') "
        f"AND DATE('{p['event_complete_dt']}') AND e.event_id IS NULL) AS \"Missing new-user D0\";",
        f'ASSERT NOT EXISTS(SELECT 1 FROM {event_input} WHERE event_dt IS NULL OR ({cutover} AND '
        '(event_ts IS NULL OR service_name IS NULL))) AS "Silver required columns";',
        f'ASSERT (SELECT COUNT(*)>0 FROM {event_input} WHERE {cutover} AND '
        "event_name IN ('DA1','DA2') AND ARRAY_LENGTH(SPLIT(event_label,'__')) IN (4,5)) "
        'AS "New logging events absent";',
        f'ASSERT NOT EXISTS(SELECT 1 FROM {event_input} WHERE {cutover} AND '
        "event_name IN ('DA1','DA2') AND (event_label IS NULL OR "
        "NOT REGEXP_CONTAINS(event_label,r'^[a-z][a-z0-9_]*(?:__[a-z][a-z0-9_]*){3,4}$') OR "
        "ARRAY_LENGTH(SPLIT(event_label,'__')) NOT IN (4,5) OR "
        "SPLIT(event_label,'__')[SAFE_OFFSET(ARRAY_LENGTH(SPLIT(event_label,'__'))-1)] "
        'IS DISTINCT FROM event_category)) AS "Invalid new logging naming contract";',
    ]
    # Metadata-only contract check is insufficient: validate candidates before the transaction.
    for n, q in queries.items():
        sql.append(f'CREATE TEMP TABLE {n}_candidate AS (\n{q}\n);')
    u = 'mart_kpi_user_daily_candidate'
    m = 'mart_service_metrics_daily_candidate'
    sql += [
        f'ASSERT (SELECT COUNT(*)>0 FROM {u}) AS "Empty user candidate";',
        f'ASSERT (SELECT COUNT(*)>0 FROM {m}) AS "Empty metric candidate";',
        f'ASSERT (SELECT SUM(event_cnt_day) FROM {u})=(SELECT COUNT(*) FROM {event_input} '
        f'WHERE {cutover} AND user_pseudo_id IS NOT NULL) AS "Event total mismatch";',
        f'ASSERT NOT EXISTS(SELECT 1 FROM {u} GROUP BY event_dt,user_pseudo_id HAVING COUNT(*)>1) AS "Duplicate USER DAY";',
        f'ASSERT NOT EXISTS(SELECT 1 FROM {u} WHERE event_dt IS NULL OR user_pseudo_id IS NULL OR first_seen_dt IS NULL) AS "Missing user fields";',
        f'ASSERT NOT EXISTS(SELECT 1 FROM {u} WHERE ARRAY_LENGTH(funnel_session_facts)>10000) AS "Funnel array requires cost review";',
        f'ASSERT NOT EXISTS(SELECT 1 FROM {m} GROUP BY metric_row_id HAVING COUNT(*)>1) AS "Duplicate metric key";',
        f'ASSERT NOT EXISTS(SELECT 1 FROM {m} WHERE denominator_users IS NULL OR denominator_users<=0 OR is_complete IS NULL OR '
        '(is_complete AND (numerator_users IS NULL OR numerator_users<0 OR numerator_users>denominator_users)) OR '
        '(NOT is_complete AND numerator_users IS NOT NULL)) AS "Invalid metric counts";',
        f'ASSERT (SELECT COUNT(DISTINCT TO_JSON_STRING(STRUCT(build_id,user_snapshot_at,event_complete_start_dt,event_complete_dt)))=1 '
        f'FROM (SELECT build_id,user_snapshot_at,event_complete_start_dt,event_complete_dt FROM {u} UNION ALL '
        f'SELECT build_id,user_snapshot_at,event_complete_start_dt,event_complete_dt FROM {m})) AS "Mixed batch metadata";',
        schema_sql(),
        'BEGIN TRANSACTION;',
    ]
    for n, (columns, _, _) in TABLES.items():
        fields = ','.join(c for c, _ in columns)
        sql += [f'DELETE FROM `{STAGE}.gold.{n}` WHERE TRUE;',
                f'INSERT INTO `{STAGE}.gold.{n}` ({fields}) SELECT {fields} FROM {n}_candidate;']
    sql += ['COMMIT TRANSACTION;']
    return '\n\n'.join(sql) + '\n'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['schema', 'compile', 'compile-offline', 'publish-sql'])
    parser.add_argument('--contract', type=Path)
    parser.add_argument('--target', type=Path, default=ROOT / 'dbt/target')
    parser.add_argument('--dbt', default='dbt')
    args = parser.parse_args()
    if args.command == 'schema':
        print(schema_sql(), end='')
        return
    if args.contract is None:
        parser.error('--contract is required')
    p = json.loads(args.contract.read_text())
    if args.command in ('compile', 'compile-offline'):
        compile_models(p, args.dbt, args.target, offline=args.command == 'compile-offline')
    else:
        print(publication_sql(p, args.target), end='')


if __name__ == '__main__':
    main()
