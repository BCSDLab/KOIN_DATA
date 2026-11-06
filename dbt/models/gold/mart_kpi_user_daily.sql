{{ config(materialized="table", partition_by={"field": "event_dt", "data_type": "date"}, cluster_by=["user_pseudo_id", "user_id"], tags=["gold_44_20"]) }}
{{ gold_block_individual_publish() }}
{# New logging v1: consume validated Silver classifications, never reconstruct them. #}
{{ gold_user_query() }}
