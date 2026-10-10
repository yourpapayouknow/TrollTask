# 验证命令入口的真实持久化、失败退出及批量事务。
from head import ROOT, TemporaryDirectory, run, jdmp, jld, connect, Path


# 调用原生存储命令并校验退出状态。
def tstcmd(path, *args, success=True):
    result = run([str(ROOT / 'build/taskstore'), str(path), *args], capture_output=True, text=True)
    assert (result.returncode == 0) == success, result.stderr
    if success:
        return jld(result.stdout)
    assert not result.stdout and result.stderr
    return jld(result.stderr)


# 检查命令解析不会提交无效或部分数据。
def tstcli():
    with TemporaryDirectory(prefix='trolltask-cli-') as root:
        path = Path(root) / 'tasks.sqlite3'
        assert tstcmd(path, 'schema')['schema_version'] == 3
        assert tstcmd(path, 'lists')[0]['title'] == '我的任务'
        task = tstcmd(path, 'create', jdmp({'title': '两天完成', 'planned_duration': 172800, 'deadline_at': 1800000000}))
        task_id = task['task_id']
        assert task['deadline_kind'] == 'timed' and task['status'] == 'needsAction'
        occurrence = tstcmd(path, 'occur', task_id, '1700000000.25')
        assert tstcmd(path, 'occur', task_id, '1700000000.25')['occurrence_id'] == occurrence['occurrence_id']
        tstcmd(path, 'batch', jdmp([
            ['update', task_id, jdmp({'status': 'completed'})],
            ['handle', occurrence['occurrence_id'], jdmp({'status': 'handled', 'handled_at': 1700000100, 'action': 'complete'})]
        ]))
        assert tstcmd(path, 'get', task_id)['completed_at'] is not None
        assert tstcmd(path, 'occurrences', task_id)[0]['status'] == 'handled'
        before = tstcmd(path, 'get', task_id)
        tstcmd(path, 'batch', jdmp([
            ['update', task_id, jdmp({'notes': '不应保存'})],
            ['update', task_id, jdmp({'difficulty': 99})]
        ]), success=False)
        assert tstcmd(path, 'get', task_id) == before
        for args in [('create', '{'), ('create', '[]'), ('update', task_id, 'null'), ('unknown',), ('occur', task_id, 'true')]:
            tstcmd(path, *args, success=False)
        with connect(path) as db:
            assert db.execute('pragma integrity_check').fetchone() == ('ok',)
            assert db.execute('pragma foreign_key_check').fetchall() == []
        assert tstcmd(path, 'tasks')[0]['task_id'] == task_id
        tstcmd(path, 'restore', task_id)
        assert tstcmd(path, 'completed') == []
        assert tstcmd(path, 'pending')[0]['remind_at'] == 1800000000
        tstcmd(path, 'complete', task_id)
        assert tstcmd(path, 'completed')[0]['task_id'] == task_id
        imported = tstcmd(path, 'import', '22222222-2222-4222-8222-222222222222', jdmp({'title': '导入', 'due_at': 100}))
        assert tstcmd(path, 'import', imported['task_id'].upper(), jdmp({'title': '冲突'}), success=False)['kind'] == 'duplicate_uuid'
        assert tstcmd(path, 'create', jdmp({'due_at': True}), success=False)['kind'] == 'invalid_fields'
        assert tstcmd(path, 'get', '99999999-9999-4999-8999-999999999999', success=False)['kind'] == 'not_found'
        plan = tstcmd(path, 'plan', '101')
        assert tstcmd(path, 'claim', jdmp(plan['alerts'][0]), '0.5', '101', success=False)['kind'] == 'invalid_fields'
        alert = tstcmd(path, 'claim', jdmp(plan['alerts'][0]), str(plan['revision']), '101')
        assert alert['task_id'] == imported['task_id']
        assert tstcmd(path, 'action', alert['occurrence_id'], 'snooze', 'false', success=False)['kind'] == 'invalid_fields'
        tstcmd(path, 'action', alert['occurrence_id'], 'dismiss')
        assert tstcmd(path, 'plan', '101')['alerts'] == []
        tstcmd(path, 'delete', imported['task_id'])
        assert tstcmd(path, 'pending') == []
        bad = Path(root) / 'broken.sqlite3'
        bad.write_bytes(b'not sqlite')
        assert tstcmd(bad, 'schema', success=False)['kind'] == 'database_failure'
        with connect(path) as lock:
            lock.execute('begin immediate')
            assert tstcmd(path, 'update', task_id, jdmp({'notes': '锁等待失败'}), success=False)['kind'] == 'database_busy'
            lock.rollback()
        assert tstcmd(path, 'get', task_id)['notes'] == before['notes']
    print('TaskStore CLI: JSON, durable CRUD/import/order, explicit errors, claims/actions and atomic batch rollback passed')


# 执行独立CLI验收。
if __name__ == '__main__':
    tstcli()
