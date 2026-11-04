-- 移除新版评估结构，恢复真实第十版形态。
DROP TABLE task_reviews;
ALTER TABLE tasks DROP COLUMN planning_mode;
-- 将隔离的新库退回真实十版结构，供迁移和回滚验收复用。
DROP TABLE agenda_slots;
DROP TABLE routine_documents;
DROP INDEX routine_source_unique;
ALTER TABLE tasks DROP COLUMN routine_kind;
ALTER TABLE tasks DROP COLUMN routine_end;
ALTER TABLE tasks DROP COLUMN routine_enabled;
ALTER TABLE tasks DROP COLUMN routine_source;
UPDATE store_meta SET schema_version=10;
