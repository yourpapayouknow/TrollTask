# 验证命令入口的真实持久化、失败退出及批量事务。
from head import ROOT, TemporaryDirectory, run, jdmp, jld, connect, Path


# 调用原生存储命令并校验退出状态。
def tstcmd(path, *args, success=True):
    result = run([str(ROOT / 'build/taskstore'), str(path), *args], capture_output=True, text=True)
    assert (result.returncode == 0) == success, result.stderr
    if success:
        assert result.stdout.isascii(), "device console JSON must use ASCII escapes"
        return jld(result.stdout)
    assert not result.stdout and result.stderr
    return jld(result.stderr)


# 检查命令解析不会提交无效或部分数据。
def tstcli():
    with TemporaryDirectory(prefix='trolltask-cli-') as root:
        path = Path(root) / 'tasks.sqlite3'
        assert tstcmd(path, 'schema')['schema_version'] == 12
        assert tstcmd(path, 'lists')[0]['title'] == '我的任务'
        task = tstcmd(path, 'create', jdmp({'title': '两天完成', 'planned_duration': 172800, 'deadline_at': 1800000000}))
        task_id = task['task_id']
        assert task['deadline_kind'] == 'timed' and task['status'] == 'needsAction'
        occurrence = tstcmd(path, 'occur', task_id, '1700000000.25')
        assert tstcmd(path, 'occur', task_id, '1700000000.25')['occurrence_id'] == occurrence['occurrence_id']
        tstcmd(path, 'batch', jdmp([
            ['update', task_id, jdmp({'status': 'completed'})],
            ['handle', occurrence['occurrence_id'], jdmp({'status': 'resolved', 'handled_at': 1700000100, 'action': 'complete'})]
        ]))
        assert tstcmd(path, 'get', task_id)['completed_at'] is not None
        assert tstcmd(path, 'occurrences', task_id)[0]['status'] == 'resolved'
        before = tstcmd(path, 'get', task_id)
        tstcmd(path, 'batch', jdmp([
            ['update', task_id, jdmp({'notes': '不应保存'})],
            ['update', task_id, jdmp({'difficulty': 99})]
        ]), success=False)
        assert tstcmd(path, 'get', task_id) == before
        for args in [('create', '{'), ('create', '[]'), ('update', task_id, 'null'), ('unknown',), ('occur', task_id, 'true')]:
            tstcmd(path, *args, success=False)
        tstcmd(path, 'day', '1700000000', 'UTC', 'invalid', success=False)
        source = '# TrollTask常律模板v1\n## 周一\n- 08:00~09:00 [工作] 工作\n- 09:00~09:30 [固定] 早餐\n'
        imported = tstcmd(path, 'routine-import', source, 'cli-test.md')
        assert imported['added'] == 2
        assert tstcmd(path, 'routine-import', source, 'cli-test.md')['added'] == 0
        assert tstcmd(path, 'day', '1700000000', 'UTC')['draft_count'] == 0
        routines = [item for item in tstcmd(path, 'tasks') if item['routine_source']]
        assert len(routines) == 2 and all(item['routine_enabled'] == 1 for item in routines)
        for item in routines:
            tstcmd(path, 'delete', item['task_id'])
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
        listing = tstcmd(path, 'new-list', '测试清单')['list_id']
        extra = tstcmd(path, 'create', jdmp({'title': '清单任务', 'list_id': listing}))['task_id']
        tstcmd(path, 'complete-next', extra)
        tstcmd(path, 'clear-completed', listing)
        assert tstcmd(path, 'get', extra)['deleted'] == 1
        tstcmd(path, 'delete-list', listing)
        assert len(tstcmd(path, 'lists')) == 2
        assert tstcmd(path, 'clear-completed', listing, success=False)['kind'] == 'not_found'
        assert tstcmd(path, 'delete-list', '00000000-0000-4000-8000-000000000001', success=False)['kind'] == 'invalid_fields'
        proof_task = tstcmd(path, 'create', jdmp({'title': '图片打卡命令', 'due_at': 100}))
        plan = tstcmd(path, 'plan', '101')
        alert = next(item for item in plan['alerts'] if item['task_id'] == proof_task['task_id'])
        occurrence = tstcmd(path, 'claim', jdmp(alert), str(plan['revision']), '101')['occurrence_id']
        assert tstcmd(path, 'hold', occurrence, 'snooze')['defer_count'] == 1
        assert tstcmd(path, 'hold', occurrence, 'snooze', success=False)['kind'] == 'invalid_fields'
        assert tstcmd(path, 'resume', occurrence)['resumed']
        picture = ROOT / 'Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-60@2x.png'
        proof = tstcmd(path, 'checkin', occurrence, 'image', str(picture))
        assert proof['occurrence_id'] == occurrence and proof['image_bytes'] == len(picture.read_bytes())
        file_task = tstcmd(path, 'create', jdmp({'title': '普通文件打卡', 'due_at': 100}))
        file_plan = tstcmd(path, 'plan', '101')
        file_alert = next(item for item in file_plan['alerts'] if item['task_id'] == file_task['task_id'])
        file_id = tstcmd(path, 'claim', jdmp(file_alert), str(file_plan['revision']), '101')['occurrence_id']
        document = Path(root) / '原始文件.bin'
        document.write_bytes(bytes([0, 255, 1, 0, 42]))
        file_proof = tstcmd(path, 'checkin', file_id, 'file', str(document))
        assert file_proof['method'] == 'file' and file_proof['name'] == document.name and file_proof['image_bytes'] == 5
        output = Path(root) / 'roundtrip.bin'
        tstcmd(path, 'proof', file_id, str(output))
        assert output.read_bytes() == document.read_bytes()
        exported = Path(root) / 'proof.png'
        assert tstcmd(path, 'proof', occurrence, str(exported))['method'] == 'image'
        assert exported.read_bytes() == picture.read_bytes()
        assert tstcmd(path, 'get', proof_task['task_id'])['status'] == 'completed'
        assert tstcmd(path, 'checkin', occurrence, 'image', str(picture), success=False)['kind'] == 'not_found'
        batch_task = tstcmd(path, 'create', jdmp({'title': '六附件命令', 'due_at': 100}))
        plan = tstcmd(path, 'plan', '101')
        alert = next(item for item in plan['alerts'] if item['task_id'] == batch_task['task_id'])
        batch_id = tstcmd(path, 'claim', jdmp(alert), str(plan['revision']), '101')['occurrence_id']
        tstcmd(path, 'checkin', batch_id, 'image', *([str(picture)] * 7), success=False)
        tstcmd(path, 'checkin', batch_id, 'image', str(picture), str(Path(root) / 'missing.png'), success=False)
        assert tstcmd(path, 'proofs', batch_id) == [] and tstcmd(path, 'get', batch_task['task_id'])['status'] == 'needsAction'
        tstcmd(path, 'checkin', batch_id, 'image', *([str(picture)] * 6))
        records = tstcmd(path, 'proofs', batch_id)
        assert len(records) == 6 and [row['position'] for row in records] == list(range(6))
        assert all(row['image_bytes'] == len(picture.read_bytes()) for row in records)
        assert tstcmd(path, 'get', batch_task['task_id'])['status'] == 'completed'
        bad = Path(root) / 'broken.sqlite3'
        bad.write_bytes(b'not sqlite')
        assert tstcmd(bad, 'schema', success=False)['kind'] == 'database_failure'
        with connect(path) as lock:
            lock.execute('begin immediate')
            assert tstcmd(path, 'update', task_id, jdmp({'notes': '锁等待失败'}), success=False)['kind'] == 'database_busy'
            lock.rollback()
        assert tstcmd(path, 'get', task_id)['notes'] == before['notes']
        encoded = {'title': '中文𠀀与引号"', 'notes': '换行\n原样反斜杠\\path'}
        utf = tstcmd(path, 'create', jdmp(encoded))
        assert utf['title'] == encoded['title'] and utf['notes'] == encoded['notes']
        tstcmd(path, 'delete', utf['task_id'])
    print('TaskStore CLI: JSON, durable CRUD/import/order, explicit errors, claims/actions, hold/resume/checkin/proof and atomic batch rollback passed')


# 执行独立CLI验收。
if __name__ == '__main__':
    tstcli()
