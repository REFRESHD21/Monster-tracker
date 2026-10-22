CREATE TABLE refund_requests (id TEXT PRIMARY KEY, sale_id TEXT NOT NULL REFERENCES events(id), body TEXT NOT NULL);
CREATE TABLE refund_observations (id TEXT PRIMARY KEY, request_id TEXT NOT NULL REFERENCES refund_requests(id), body TEXT NOT NULL);
CREATE TABLE refund_returns (id TEXT PRIMARY KEY, request_id TEXT NOT NULL REFERENCES refund_requests(id), event_id TEXT NOT NULL UNIQUE REFERENCES events(id), body TEXT NOT NULL);
CREATE TRIGGER refund_request_no_update BEFORE UPDATE ON refund_requests BEGIN SELECT RAISE(ABORT,'Refund requests are immutable'); END;
CREATE TRIGGER refund_request_no_delete BEFORE DELETE ON refund_requests BEGIN SELECT RAISE(ABORT,'Refund history is append-only'); END;
CREATE TRIGGER refund_observation_no_update BEFORE UPDATE ON refund_observations BEGIN SELECT RAISE(ABORT,'Refund observations are immutable'); END;
CREATE TRIGGER refund_observation_no_delete BEFORE DELETE ON refund_observations BEGIN SELECT RAISE(ABORT,'Refund history is append-only'); END;
CREATE TRIGGER refund_return_no_update BEFORE UPDATE ON refund_returns BEGIN SELECT RAISE(ABORT,'Returned goods are immutable'); END;
CREATE TRIGGER refund_return_no_delete BEFORE DELETE ON refund_returns BEGIN SELECT RAISE(ABORT,'Returned goods history is append-only'); END;
