-- 保存升级前的数据模型与已有跨天任务。
CREATE TABLE store_meta(singleton INTEGER PRIMARY KEY, schema_version INTEGER NOT NULL);
INSERT INTO store_meta VALUES(1,1);
CREATE TABLE task_lists(list_id TEXT PRIMARY KEY, title TEXT NOT NULL, created_at REAL, updated_at REAL);
INSERT INTO task_lists VALUES('00000000-0000-4000-8000-000000000001','我的任务',1700000000,1700000000);
CREATE TABLE tasks(
    task_id TEXT PRIMARY KEY, title TEXT NOT NULL, notes TEXT NOT NULL DEFAULT '', due_at REAL,
    timezone_id TEXT NOT NULL, recurrence_type TEXT NOT NULL DEFAULT 'none', recurrence_interval INTEGER NOT NULL DEFAULT 1,
    status TEXT NOT NULL DEFAULT 'needsAction', snooze_until REAL, created_at REAL NOT NULL, updated_at REAL NOT NULL,
    list_id TEXT NOT NULL REFERENCES task_lists(list_id), parent_id TEXT REFERENCES tasks(task_id), position INTEGER NOT NULL DEFAULT 0,
    starred INTEGER NOT NULL DEFAULT 0, schedule_kind TEXT NOT NULL DEFAULT 'none', planned_duration REAL,
    deadline_at REAL, deadline_kind TEXT NOT NULL DEFAULT 'none', recurrence_json TEXT NOT NULL DEFAULT '[]',
    completed_at REAL, deleted INTEGER NOT NULL DEFAULT 0
);
INSERT INTO tasks(task_id,title,notes,due_at,timezone_id,created_at,updated_at,list_id,schedule_kind,planned_duration,deadline_at,deadline_kind)
VALUES('11111111-1111-4111-8111-111111111111','跨天报告','必须保留',1700000000.125,'Asia/Shanghai',1699990000,1699990100,
    '00000000-0000-4000-8000-000000000001','timed',172800,1700259200,'timed');
CREATE TABLE reminder_occurrences(
    occurrence_id TEXT PRIMARY KEY, task_id TEXT NOT NULL REFERENCES tasks(task_id), scheduled_at REAL NOT NULL,
    triggered_at REAL, handled_at REAL, status TEXT NOT NULL DEFAULT 'pending', action TEXT, snooze_until REAL,
    created_at REAL NOT NULL, updated_at REAL NOT NULL, UNIQUE(task_id,scheduled_at)
);
INSERT INTO reminder_occurrences(occurrence_id,task_id,scheduled_at,created_at,updated_at)
VALUES('22222222-2222-4222-8222-222222222222','11111111-1111-4111-8111-111111111111',1700000000.125,1699990000,1699990000);
