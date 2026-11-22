-- Migracja US-02-03: Tabela rejestrująca wyniki automatycznych testów jakości danych
CREATE TABLE IF NOT EXISTS core.dq_test_log (
    log_id SERIAL PRIMARY KEY,
    run_timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    rule_id VARCHAR(10) NOT NULL,
    rule_name VARCHAR(255) NOT NULL,
    severity VARCHAR(20) NOT NULL,          -- CRITICAL / WARNING
    violations_count INT NOT NULL,
    status VARCHAR(20) NOT NULL,            -- PASS / FAIL / WARN
    details TEXT
);

CREATE INDEX IF NOT EXISTS idx_dq_test_log_run_ts ON core.dq_test_log(run_timestamp);
CREATE INDEX IF NOT EXISTS idx_dq_test_log_rule_id ON core.dq_test_log(rule_id);
