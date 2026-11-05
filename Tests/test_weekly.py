# 核对正式周表、同库一次性写入及无冲突日程。
from head import ROOT, TemporaryDirectory, Path, jdmp, jld, datetime, timezone, connect
from test_cli import tstcmd

checks = 0

# 累计能说明失败原因的断言。
def req(value, message):
    global checks
    assert value, message
    checks += 1

# 将固定日期转为绝对时刻。
def at(text):
    return datetime.fromisoformat(text).replace(tzinfo=timezone.utc).timestamp()

# 通过生产核心提交正式周表。
def apply(db, path, now, zone='Asia/Shanghai', success=True):
    return tstcmd(db, 'routine-apply', str(path), str(now), zone, success=success)

# 验证数据源与事务、时间轴、提醒链路共用实现。
def run(root):
    path = ROOT / 'Resources/WeeklyRoutine.json'
    document = jld(path.read_text())
    count = len(document['entries'])
    db = root / 'weekly.db'
    original = tstcmd(db, 'create', jdmp({'title': '原有普通任务', 'planned_duration': 60}))
    # 旧版数据从真实存储中模拟，正式导入不再创建草稿。
    legacy = tstcmd(db, 'create', jdmp({'title':'旧版停用项','list_id':'00000000-0000-4000-8000-000000000002','routine_kind':'fixed','routine_enabled':0,'due_at':1700000000,'routine_end':10,'recurrence_type':'custom','recurrence':['RRULE:FREQ=DAILY;COUNT=1'],'routine_source':'md:legacy-weekly.md:old'}))
    old = {'added':1}
    other = tstcmd(db, 'create', jdmp({'title': '其他来源草稿', 'list_id': '00000000-0000-4000-8000-000000000002', 'routine_kind': 'fixed', 'routine_enabled': 0, 'due_at':1700000000, 'routine_end':20, 'recurrence_type':'custom','recurrence':['RRULE:FREQ=DAILY;COUNT=1']}))
    start = at('2026-11-01T16:00')  # 上海周一00:00。
    revision = tstcmd(db, 'snapshot')['revision']
    result = apply(db, path, start)
    req(result == {'added': count, 'skipped': 0, 'archived': old['added']}, '正式启用，原来源旧草稿归档')
    req(tstcmd(db, 'snapshot')['revision'] == revision + 1, '整周仅提交一次修订')
    tasks = tstcmd(db, 'tasks')
    official = [t for t in tasks if str(t['routine_source']).startswith('formal:')]
    req(len(official) == count and all(t['routine_enabled'] and not t['deleted'] for t in official), '全部为正式启用常律')
    req(next(t for t in tasks if t['task_id'] == other['task_id'])['deleted'] == 0, '不归档其他来源')
    req(next(t for t in tasks if t['task_id'] == original['task_id'])['status'] == 'needsAction', '普通任务未丢失')
    req(all(t['deleted'] for t in tasks if str(t['routine_source']).startswith('md:legacy-weekly.md:')), '旧草稿仅软归档')
    req(all('每步拍照或截图打卡' in t['notes'] for t in official), '保留所有步骤打卡要求')
    for offset in range(7):
        stamp = start + offset * 86400
        plan = tstcmd(db, 'day', str(stamp), 'Asia/Shanghai')
        req(not plan['conflicts'], f'周{offset+1}固定安排不冲突')
        rows = [e for e in plan['entries'] if e['kind'] not in ('background', 'task')]
        rows.sort(key=lambda e: e['start_at'])
        req(all(a['end_at'] <= b['start_at'] for a, b in zip(rows, rows[1:])), '跨夜与工作时段均不重叠')
        req(all(stamp <= e['start_at'] < e['end_at'] <= stamp+86400 for e in rows), '每日只显示当日截取部分')
        req(any(e['kind'] == 'work' for e in rows), '每天保留普通任务容量')
        req(any(e['kind'] == 'rest' for e in rows), '每天保留睡眠休息')
    for offset in range(7):
        stamp = start + (offset+7) * 86400
        plan = tstcmd(db, 'day', str(stamp), 'Asia/Shanghai')
        rows = sorted((e for e in plan['entries'] if e['kind'] not in ('background', 'task')), key=lambda e: e['start_at'])
        req(not plan['conflicts'], '稳定周无冲突')
        req(rows[0]['start_at'] == stamp and rows[-1]['end_at'] == stamp+86400, '跨夜休息覆盖完整24小时')
        req(all(a['end_at'] == b['start_at'] for a,b in zip(rows,rows[1:])), '24小时连续衔接，无隐性间隙')
    # 首次启用不批量补弹过去事项。
    late = root / 'late.db'
    now = start + 3*86400 + 20*3600
    apply(late, path, now)
    req(all(t['due_at'] >= now for t in tstcmd(late, 'tasks')), '所有首次轮次从真实启用时刻之后开始')
    req(all(x['remind_at'] >= now for x in tstcmd(late, 'plan', str(now))['alerts']), '没有安装前积压提醒')
    # 再次打开不覆盖编辑、停用、删除或复活已完成轮次。
    changed, deleted, completed = official[:3]
    tstcmd(db, 'update', changed['task_id'], jdmp({'title': '保留用户编辑', 'routine_enabled': 0, 'due_at':1700000000, 'routine_end':20, 'recurrence_type':'custom','recurrence':['RRULE:FREQ=DAILY;COUNT=1']}))
    tstcmd(db, 'delete', deleted['task_id'])
    tstcmd(db, 'complete-next', completed['task_id'])
    before = tstcmd(db, 'snapshot')
    req(apply(db, path, start+8*86400)['added'] == 0, '重新安装不会再创建模板')
    req(tstcmd(db, 'snapshot') == before, '用户状态与轮次完全保留，修订不变')
    # 问题周表不能产生半套已启用任务或半次归档。
    for index, mutate in enumerate([
        lambda d: d['entries'].append(dict(d['entries'][0], key='overlap')),
        lambda d: d['entries'][0].update(end=d['entries'][0]['start']),
        lambda d: d['entries'][0].update(days=[8]),
        lambda d: d['entries'][0].update(title=''),
        lambda d: [e.update(role='background') for e in d['entries']],
    ]):
        bad = jld(path.read_text()); mutate(bad)
        badpath = root / f'bad-{index}.json'; badpath.write_text(jdmp(bad))
        invalid = root / f'invalid-{index}.db'
        tstcmd(invalid, 'create', jdmp({'title':'保留普通任务'}))
        before = tstcmd(invalid, 'snapshot')
        apply(invalid, badpath, start, success=False)
        req(tstcmd(invalid, 'snapshot') == before, '无效输入没有数据库副作用')
    # 实际SQLite中途故障必须连同前面已插入事项一起回滚。
    fault = root / 'fault.db'
    tstcmd(fault, 'schema')
    before = tstcmd(fault, 'snapshot')
    with connect(fault) as sql:
        sql.execute("CREATE TRIGGER reject_formal BEFORE INSERT ON tasks WHEN NEW.routine_source LIKE 'formal:%item-002' BEGIN SELECT RAISE(ABORT,'test fault'); END")
    apply(fault, path, start, success=False)
    req(tstcmd(fault, 'snapshot') == before, '数据库中途失败不留半套常律或归档')
    with connect(fault) as sql:
        sql.execute('DROP TRIGGER reject_formal')
    req(apply(fault, path, start)['added'] == count, '失败后可完整重试')
    expected = []
    visible = ''.join(t['title']+t['notes'] for t in official)
    for item in expected:
        req(item in visible, '保留原活动：'+item)
    # 原文完整保存在唯一数据库中，关闭后重开仍保留标记。
    with connect(db) as sql:
        req(sql.execute('SELECT content FROM routine_documents WHERE name=?', (document['source'],)).fetchone()[0] == document['text'], '完整原文保存在唯一数据库中')
    req(apply(db, path, start)['skipped'] == count, '跨进程重开识别同一正式周表')

with TemporaryDirectory() as temp:
    run(Path(temp))
print(f'正式常律：{checks}项检查通过')
