-- 将隔离库的归档结构恢复到迁移前。
DROP TRIGGER archive_task_new;
DROP TRIGGER archive_task_done;
DROP TRIGGER archive_occ_new;
DROP TRIGGER archive_occ_done;
DROP TRIGGER archive_local_day;
DROP TABLE archive_files;
DROP TABLE task_archive;
UPDATE store_meta SET schema_version=12;
