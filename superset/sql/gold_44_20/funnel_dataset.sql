-- Virtual Dataset. Time column: event_dt; required filters: funnel_id, funnel_version.
-- Do not SUM parent daily counts after UNNEST. No raw-event ordering in Superset.
SELECT g.event_dt, g.user_pseudo_id, g.gender, g.major, g.entry_year, g.user_type,
  g.build_id, g.user_snapshot_at, g.event_complete_start_dt, g.event_complete_dt,
  f.funnel_id, f.funnel_version, f.session_key, f.anchor_dt,
  f.is_complete, f.max_step_reached, f.total_steps, step_no
FROM `koin-stage-438512.gold.mart_kpi_user_daily` g
CROSS JOIN UNNEST(g.funnel_session_facts) f
CROSS JOIN UNNEST(GENERATE_ARRAY(1, f.total_steps)) step_no
