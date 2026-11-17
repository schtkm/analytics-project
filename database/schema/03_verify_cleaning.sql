-- Read-only verification after a transformation. No guest personal data returned.
SELECT run_id, started_at, finished_at, status, error_code, report
FROM core.etl_runs ORDER BY started_at DESC LIMIT 5;

SELECT run_id, source_table, outcome, count(*) AS records
FROM core.etl_rejected_records
WHERE run_id=(SELECT run_id FROM core.etl_runs ORDER BY started_at DESC LIMIT 1)
GROUP BY run_id, source_table, outcome ORDER BY source_table, outcome;

SELECT source_table, reason->>'field' AS field, reason->>'code' AS code, count(*)
FROM core.etl_rejected_records r
CROSS JOIN LATERAL jsonb_array_elements(r.reasons) reason
WHERE run_id=(SELECT run_id FROM core.etl_runs ORDER BY started_at DESC LIMIT 1)
GROUP BY source_table, reason->>'field', reason->>'code'
ORDER BY source_table, code;

-- Never add different currencies together.
SELECT currency, count(*) AS reservations, sum(room_revenue) AS room_revenue,
       sum(cancellation_fee) AS cancellation_fee
FROM core.clean_pms_reservations GROUP BY currency;
