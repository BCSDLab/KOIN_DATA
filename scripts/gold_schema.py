"""Gold contract 2026-11-06. No credentials, local paths, or production writes."""

USER_COLUMNS = [
    ('event_dt', 'DATE'), ('user_pseudo_id', 'STRING'), ('user_id', 'STRING'),
    ('gender', 'STRING'), ('major', 'STRING'), ('entry_year', 'INT64'), ('user_type', 'STRING'),
    ('is_deleted', 'BOOL'), ('is_mysql_mapped', 'BOOL'),
    ('platform_dominant', 'STRING'), ('device_category_dominant', 'STRING'), ('device_os_dominant', 'STRING'),
    ('event_cnt_day', 'INT64'), ('entry_event_cnt_day', 'INT64'), ('core_action_cnt_day', 'INT64'),
    ('session_cnt_day', 'INT64'), ('engagement_msec_day', 'INT64'), ('is_multi_session_user', 'INT64'),
    ('first_seen_dt', 'DATE'), ('first_signup_dt', 'DATE'), ('is_new_user', 'INT64'),
    ('is_new_signup', 'INT64'), ('had_entry_prev_day', 'INT64'),
    ('is_signup_retained_d1', 'INT64'), ('is_signup_retained_d7', 'INT64'),
    ('is_signup_retained_d14', 'INT64'), ('is_signup_retained_d30', 'INT64'),
    ('used_shop_flg', 'INT64'), ('used_cafeteria_flg', 'INT64'), ('used_bus_flg', 'INT64'),
    ('used_board_flg', 'INT64'), ('used_facility_flg', 'INT64'), ('used_timetable_flg', 'INT64'),
    ('used_account_flg', 'INT64'), ('is_active_entry', 'INT64'), ('is_active_any_event', 'INT64'),
    ('has_core_action', 'INT64'), ('used_main_flg', 'INT64'),
    ('event_complete_start_dt', 'DATE'), ('event_complete_dt', 'DATE'),
    ('user_snapshot_at', 'TIMESTAMP'), ('build_id', 'STRING'), ('computed_at', 'TIMESTAMP'),
    ('funnel_session_facts', 'ARRAY<STRUCT<funnel_id STRING, funnel_version STRING, session_key STRING, '
     'anchor_dt DATE, is_complete BOOL, max_step_reached INT64, total_steps INT64, '
     'step_reached_at ARRAY<TIMESTAMP>>>'),
]
METRIC_COLUMNS = [
    ('metric_row_id', 'STRING'), ('metric_type', 'STRING'), ('metric_dt', 'DATE'),
    ('service_name', 'STRING'), ('period_n', 'INT64'), ('window_start_dt', 'DATE'), ('window_end_dt', 'DATE'),
    ('gender', 'STRING'), ('major', 'STRING'), ('entry_year', 'INT64'), ('user_type', 'STRING'),
    ('cohort_user_segment', 'STRING'), ('denominator_users', 'INT64'), ('numerator_users', 'INT64'),
    ('is_complete', 'BOOL'), ('event_complete_start_dt', 'DATE'), ('event_complete_dt', 'DATE'),
    ('user_snapshot_at', 'TIMESTAMP'), ('build_id', 'STRING'), ('computed_at', 'TIMESTAMP'),
]
TABLES = {
    'mart_kpi_user_daily': (USER_COLUMNS, 'event_dt', ['user_pseudo_id', 'user_id']),
    'mart_service_metrics_daily': (METRIC_COLUMNS, 'metric_dt', ['metric_type', 'service_name', 'major', 'entry_year']),
}


def schema_sql():
    """Create missing empty relations only. Never replace existing data."""
    statements = []
    for name, (columns, partition, clusters) in TABLES.items():
        fields = ',\n  '.join(f'{key} {dtype}' for key, dtype in columns)
        statements.append(
            f'CREATE TABLE IF NOT EXISTS `koin-stage-438512.gold.{name}` (\n  {fields}\n)\n'
            f'PARTITION BY {partition}\nCLUSTER BY {", ".join(clusters)}\n'
            "OPTIONS(description='Gold 44/20 new logging v1; structure created independently of data validation');"
        )
    return '\n\n'.join(statements) + '\n'


if __name__ == '__main__':
    print(schema_sql())
