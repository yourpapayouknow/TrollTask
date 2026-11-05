# 验证生产写入事务中的完整常律校验及工作占位避让。
from head import ROOT, TemporaryDirectory, Path, jdmp, jld, datetime, timezone, ThreadPoolExecutor
from test_cli import tstcmd

checks = 0

# 累计有明确失败原因的断言。
def req(value, message):
    global checks
    assert value, message
    checks += 1

# 使用未来UTC周一，避免实际运行日期改变用例含义。
def at(text):
    return datetime.fromisoformat(text).replace(tzinfo=timezone.utc).timestamp()

# 生成可调整的每日常律输入。
def fields(title, hour=8, end=540, **patch):
    value = dict(title=title, list_id='00000000-0000-4000-8000-000000000002', routine_kind='fixed', due_at=at('2030-01-07T00:00')+hour*3600, routine_end=end, routine_enabled=1, recurrence_type='daily', timezone_id='UTC')
    value.update(patch)
    return value

# 保存失败时包括任务、轮次和修订在内均不能变化。
def reject(db, command, *args):
    before = tstcmd(db, 'snapshot')
    error = tstcmd(db, command, *args, success=False)
    req(tstcmd(db, 'snapshot') == before, '拒绝后数据库保持原样')
    return error

# 覆盖全部冲突、边界、重复周期、原子导入与并发连接。
def run(root):
    db = root/'guard.db'
    one = tstcmd(db, 'create', jdmp(fields('早餐')))
    two = tstcmd(db, 'create', jdmp(fields('阅读', 9, 600)))
    req(one and two, '首尾相接可保存')
    err = reject(db, 'create', jdmp(fields('冲突', 8.5, 570)))
    req('冲突' in err['message'], '冲突有可理解错误')
    reject(db, 'create', jdmp(fields('并行也需避让', routine_kind='background')))
    req(tstcmd(db, 'update', one['task_id'], jdmp({'notes':'只改自己'})), '编辑排除自己的旧记录')
    reject(db, 'update', two['task_id'], jdmp({'due_at': at('2030-01-07T08:30')}))
    reject(db, 'create', jdmp(fields('无结束草稿', routine_end=None, routine_enabled=0)))
    # 日周按完整周期比较；不以未来几周的抽样充当完整校验。
    periodic = root/'period.db'
    tstcmd(periodic, 'create', jdmp(fields('隔两周', recurrence_type='custom', recurrence=['RRULE:FREQ=WEEKLY;INTERVAL=2;BYDAY=MO'])))
    tstcmd(periodic, 'create', jdmp(fields('交错两周', recurrence_type='custom', due_at=at('2030-01-14T08:00'), recurrence=['RRULE:FREQ=WEEKLY;INTERVAL=2;BYDAY=MO'])))
    reject(periodic, 'create', jdmp(fields('四周后的冲突', recurrence_type='custom', due_at=at('2030-02-04T08:00'), recurrence=['RRULE:FREQ=WEEKLY;INTERVAL=4;BYDAY=MO'])))
    # 月规则必须有界；多年后的冲突仍能检测。
    finite = root/'finite.db'
    reject(finite, 'create', jdmp(fields('无限月规则', recurrence_type='custom', recurrence=['RRULE:FREQ=MONTHLY;BYMONTHDAY=7'])))
    tstcmd(finite, 'create', jdmp(fields('有界月规则', recurrence_type='custom', recurrence=['RRULE:FREQ=MONTHLY;BYMONTHDAY=7;COUNT=120'])))
    reject(finite, 'create', jdmp(fields('九年后', due_at=at('2039-01-07T08:00'), recurrence_type='custom', recurrence=['RRULE:FREQ=YEARLY;COUNT=1'])))
    reject(finite, 'create', jdmp(fields('过大范围', recurrence_type='custom', recurrence=['RRULE:FREQ=MONTHLY;COUNT=20001'])))
    reject(finite, 'create', jdmp(fields('大量例外', recurrence_type='custom', recurrence=['RRULE:FREQ=HOURLY;UNTIL=20400101T000000Z','EXRULE:FREQ=HOURLY'])))
    # 跨夜与周日到周一的边界。
    night = root/'night.db'
    tstcmd(night, 'create', jdmp(fields('周日休息',23,60,recurrence_type='custom',due_at=at('2030-01-06T23:00'),recurrence=['RRULE:FREQ=WEEKLY;BYDAY=SU'])))
    reject(night, 'create', jdmp(fields('周一凌晨',.5,90,recurrence_type='custom',recurrence=['RRULE:FREQ=WEEKLY;BYDAY=MO'])))
    # 工作窗口主动扣除具体安排，剩余碎片接纳拆细的普通任务。
    work = root/'work.db'
    tstcmd(work, 'create', jdmp(fields('工作占位',8,660,routine_kind='work')))
    tstcmd(work, 'create', jdmp(fields('固定安排',9,570)))
    tstcmd(work, 'create', jdmp(fields('原并行事项',10,630,routine_kind='background')))
    for title, minutes in [('步骤一',45),('步骤二',30),('步骤三',20)]:
        tstcmd(work,'create',jdmp({'title':title,'planned_duration':minutes*60}))
    plan = tstcmd(work,'day',str(at('2030-01-07T00:00')),'UTC')
    slots = plan['allocations']
    req(len(slots)==3 and not plan['conflicts'], '三项待办填入避让后的碎片')
    blocks = [(at('2030-01-07T09:00'),at('2030-01-07T09:30')),(at('2030-01-07T10:00'),at('2030-01-07T10:30'))]
    req(all(not (s['start_at']<b and a<s['end_at']) for s in slots for a,b in blocks),'所有待办避开具体常律')
    # 模板正式导入，不产生禁用草稿；错误行、重叠和中途失败均整批回滚。
    imp = root/'import.db'
    text = '# TrollTask常律模板v1\n## 周一\n- 08:00~09:00 [工作] 工作\n- 08:20~08:30 [固定] 早餐\n## 周二\n- 07:00~07:30 [固定] **保留原文**\n'
    result = tstcmd(imp,'routine-import',text,'template.md')
    req(result['added']==3 and all(t['routine_enabled'] for t in tstcmd(imp,'tasks')), '一次创建正式常律且保留明确类型')
    req(any(t['title']=='**保留原文**' for t in tstcmd(imp,'tasks')),'模板标题不被Markdown展开或改写')
    rev = tstcmd(imp,'snapshot')['revision']
    req(tstcmd(imp,'routine-import',text,'template.md')['added']==0 and tstcmd(imp,'snapshot')['revision']==rev,'重复导入无额外写入')
    reject(imp,'routine-import',text+'- 坏行\n','bad.md')
    reject(imp,'routine-import','# TrollTask常律模板v1\n## 周三\n- 08:00~09:00 [固定] A\n- 08:30~09:30 [休息] B\n','overlap.md')
    reject(imp,'routine-import','# TrollTask常律模板v1\n## 周一\n- 08:00~09:00 [固定] A\n- 08:00~09:00 [固定] A\n','duplicate.md')
    # 两个真实进程争抢同一时段，只能一方提交。
    race = root/'race.db'; tstcmd(race,'schema')
    def create(title):
        from head import run
        return run([str(ROOT/'build/taskstore'),str(race),'create',jdmp(fields(title))],capture_output=True,text=True).returncode
    with ThreadPoolExecutor(max_workers=2) as pool:
        codes = list(pool.map(create,['竞争A','竞争B']))
    req(sorted(codes)==[0,1] and len(tstcmd(race,'tasks'))==1,'并发写入互斥，不产生重叠常律')

if __name__=='__main__':
    with TemporaryDirectory(prefix='routine-guard-') as value:
        run(Path(value))
    print(f'常律校验通过：{checks}项')
