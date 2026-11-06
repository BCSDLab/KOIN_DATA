{{ config(enabled=(var('gold_validation_enabled', false) is sameas true), tags=['gold_44_20']) }}
{{ gold_naming_validation() }}
