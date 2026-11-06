{{ config(materialized='table', partition_by={'field': 'metric_dt', 'data_type': 'date'},
          cluster_by=['metric_type','service_name','major','entry_year'], tags=['gold_44_20']) }}
{{ gold_block_individual_publish() }}
{{ gold_metrics_query() }}
