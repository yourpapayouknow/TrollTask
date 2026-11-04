# 验证拆分事务、每日时间轴和真实HTTP退化路径。
from head import ROOT, TemporaryDirectory, Path, jdmp, jld, ThreadingHTTPServer, SimpleHTTPRequestHandler, Thread, datetime, timezone
from test_cli import tstcmd

checks = 0

# 累计有明确含义的检查。
def req(value, message):
    global checks
    assert value, message
    checks += 1

# 将稳定UTC日期转成绝对时刻。
def stamp(text):
    return datetime.fromisoformat(text).replace(tzinfo=timezone.utc).timestamp()

# 生成确定性合法子任务身份。
def part(index, minutes=20):
    return {'task_id': f'22222222-2222-4222-8222-{index:012d}', 'title': f'步骤{index}', 'notes': '独立验收', 'planned_duration': minutes * 60}

# 返回有效拆分和失败时的原子快照。
def split(db, parent, rows, expected=None, success=True):
    expected = expected or tstcmd(db, 'split-draft', parent)
    before = tstcmd(db, 'snapshot') if not success else None
    result = tstcmd(db, 'split', parent, jdmp(rows), jdmp(expected), success=success)
    if not success:
        req(tstcmd(db, 'snapshot') == before, '无效或过期拆分必须整体回滚')
    return result

# 在唯一任务树上验证重复确认、既有子任务和活动提醒保护。
def division(root):
    db = root / 'division.db'
    parent = tstcmd(db, 'create', jdmp({'title': '长任务', 'planned_duration': 7200}))['task_id']
    draft = tstcmd(db, 'split-draft', parent)
    rows = [part(1), part(2)]
    split(db, parent, rows, draft)
    req(tstcmd(db, 'get', parent)['planned_duration'] == 2400, '父级汇总步骤用时')
    split(db, parent, rows, draft, success=False)
    req(len(tstcmd(db, 'tasks')) == 3, '重复确认不能重复建子任务')
    for invalid in [[], [part(3), part(3)], [dict(part(3), title='')], [dict(part(3), planned_duration=True)], [dict(part(3), planned_duration=-1)], [dict(part(3), task_id=parent)], [dict(part(3), permission='execute')]]:
        split(db, parent, invalid, success=False)
    edited = [dict(rows[1], title='手改内容'), rows[0]]
    split(db, parent, edited)
    req(tstcmd(db, 'get', rows[1]['task_id'])['position'] == 0 and tstcmd(db, 'get', rows[1]['task_id'])['title'] == '手改内容', '既有子任务保留身份并允许重排修改')
    stale = tstcmd(db, 'split-draft', parent)
    tstcmd(db, 'update', rows[0]['task_id'], jdmp({'notes': '另处更新'}))
    split(db, parent, edited, stale, success=False)
    fresh = tstcmd(db, 'split-draft', parent)
    tstcmd(db, 'update', parent, jdmp({'notes': '父任务更新'}))
    split(db, parent, edited, fresh, success=False)
    tstcmd(db, 'complete', rows[0]['task_id'])
    fresh = tstcmd(db, 'split-draft', parent)
    children = [{k: child[k] for k in ('task_id','title','notes','planned_duration')} for child in fresh['children']]
    split(db, parent, [child for child in children if child['task_id'] != rows[0]['task_id']], success=False)
    split(db, parent, [dict(child, title='改完成记录') if child['task_id'] == rows[0]['task_id'] else child for child in children], success=False)
    split(db, parent, children)
    req(tstcmd(db, 'get', rows[0]['task_id'])['status'] == 'completed', '完成子任务保持只读')
    # 深层版本变化同样使外层草稿失效。
    second = rows[1]['task_id']
    split(db, second, [part(4),part(5)])
    stale = tstcmd(db, 'split-draft', parent)
    tstcmd(db, 'update', part(4)['task_id'], jdmp({'notes': '孙任务更新'}))
    split(db, parent, children, stale, success=False)
    # 已经展示或延后的轮次不能被拆分抹掉。
    alert_task = tstcmd(db, 'create', jdmp({'title': '当前弹窗', 'due_at': 100}))['task_id']
    plan = tstcmd(db, 'plan', '101'); alert = next(a for a in plan['alerts'] if a['task_id'] == alert_task)
    occurrence = tstcmd(db, 'claim', jdmp(alert), str(plan['revision']), '101')['occurrence_id']
    split(db, alert_task, [part(6)], success=False)
    tstcmd(db, 'hold', occurrence, 'snooze')
    split(db, alert_task, [part(6)], success=False)
    req(tstcmd(db, 'occurrences', alert_task)[0]['status'] == 'snoozed', '拆分失败保留延后状态')
    # 旧版无估时已完成子任务也可原样保留。
    legacy = tstcmd(db, 'create', jdmp({'title': '旧父任务'}))['task_id']
    child = tstcmd(db, 'create', jdmp({'title': '旧步骤', 'parent_id': legacy}))
    tstcmd(db, 'complete', child['task_id'])
    retained = {k: child[k] for k in ('task_id','title','notes','planned_duration')}
    split(db, legacy, [retained,part(7)])
    req(tstcmd(db, 'get', child['task_id'])['planned_duration'] is None, '旧完成记录不被虚构估时')

# 验证日界、父子时间边界和严格几何。
def calendar(root):
    db = root / 'calendar.db'; day = stamp('2030-01-07T00:00:00')
    # 常律UUID从同库常驻列表读取，避免复制存储常量。
    tstcmd(db, 'routine-import', '## 周一\n1. 9:00~12:00 根据一般待办按顺序完成任务\n2. 12:00~12:30 早餐\n## 周二\n1. 15:00~16:00 洗澡\n', 'week.md')
    mon = tstcmd(db,'day',str(day),'UTC','drafts'); tue = tstcmd(db,'day',str(day+86400),'UTC','drafts')
    req([e['task']['title'] for e in mon['entries']] != [e['task']['title'] for e in tue['entries']], '每天只展示匹配当日的常律')
    req(all(day <= e['start_at'] < e['end_at'] <= day+86400 for e in mon['entries']), '日程不会串入次日')
    routines = [r for r in tstcmd(db,'tasks') if r['routine_kind'] != 'none']
    work = next(r for r in routines if r['routine_kind'] == 'work')
    tstcmd(db,'update',work['task_id'],jdmp({'routine_enabled':1,'due_at':day+9*3600,'timezone_id':'UTC','routine_end':720}))
    task = tstcmd(db,'create',jdmp({'title':'超长任务','planned_duration':14400,'deadline_at':day+11*3600}))['task_id']
    plan = tstcmd(db,'day',str(day),'UTC'); row = next(r for r in plan['unplaced'] if r['task']['task_id'] == task)
    req(row['needs_split'] and row['max_span'] == 7200 and plan['max_span'] == 10800, '超出连续时段的长任务必须拆分')
    split(db, task, [part(10,60),part(11,60)])
    plan = tstcmd(db,'day',str(day),'UTC')
    req(all(e['task']['task_id'] != task for e in plan['entries']), '父级汇总不重复占用时间')
    req([e['task']['task_id'] for e in plan['entries'] if e['kind']=='task'] == [part(10)['task_id'],part(11)['task_id']], '已有子任务按原顺序直接排程')
    req(all(e['end_at'] <= day+11*3600 for e in plan['entries'] if e['kind']=='task'), '子任务继承父级截止')
    geometry = tstcmd(db,'timeline',str(day),'UTC')
    for entry, frame in zip(plan['entries'], geometry['frames']):
        req(frame[1] == (entry['start_at']-day)/60*6 and frame[3] == max(1,(entry['end_at']-entry['start_at'])/60*6), '坐标和高度严格对应真实时刻')
        req(frame[0]>=64 and frame[2]>0, '事件框在刻度右侧且宽度为正')
    fixed = tstcmd(db,'create',jdmp({'title':'固定开始的长任务','planned_duration':14400,'due_at':day+9*3600}))['task_id']
    fixed_plan = tstcmd(db,'day',str(day),'UTC')
    req(any(r['task']['task_id']==fixed and r.get('needs_split') for r in fixed_plan['unplaced']), '固定开始的长任务同样提供拆分入口')
    tstcmd(db,'delete',fixed)
    # 原定时间变到次日后子任务不得出现在今天。
    tstcmd(db,'update',task,jdmp({'due_at':day+86400+9*3600,'schedule_kind':'timed'}))
    plan = tstcmd(db,'day',str(day),'UTC')
    req(not any(e['task']['parent_id']==task for e in plan['entries']), '父任务次日开始时子任务不会提前')
    # 真实当地日长覆盖23/25小时。
    for text,hours in [('2030-03-10T12:00:00',23),('2030-11-03T12:00:00',25)]:
        dst = tstcmd(db,'timeline',str(stamp(text)),'America/New_York')
        req(dst['day_end']-dst['day_at']==hours*3600 and dst['height']==hours*360+32, '夏令时沿真实日界布局')
    # 没有独立提醒能力的旧子任务不得让父级提醒消失。
    legacy=root/'legacy-parent.db'
    root_task=tstcmd(legacy,'create',jdmp({'title':'旧有父提醒','due_at':day+9*3600,'planned_duration':1800}))['task_id']
    old_child=tstcmd(legacy,'create',jdmp({'title':'旧有未估时步骤','parent_id':root_task}))['task_id']
    alarms=tstcmd(legacy,'plan',str(day+8*3600))['alerts']
    req(any(a['task_id']==root_task for a in alarms), '旧子任务未估时时保留父提醒')
    tstcmd(legacy,'create',jdmp({'title':'可排时段','list_id':work['list_id'],'routine_kind':'work','routine_end':720,'due_at':day+9*3600,'routine_enabled':1,'recurrence_type':'daily','timezone_id':'UTC'}))
    tstcmd(legacy,'update',old_child,jdmp({'planned_duration':1800}))
    alarms=tstcmd(legacy,'plan',str(day+8*3600))['alerts']
    req(any(a['task_id']==old_child for a in alarms) and not any(a['task_id']==root_task for a in alarms), '子任务独立排程后停止重复汇总提醒')
    tstcmd(legacy,'complete',old_child)
    alarms=tstcmd(legacy,'plan',str(day+8*3600))['alerts']
    req(any(a['task_id']==root_task for a in alarms), '子任务完成后保留父级最终确认提醒')
    # 汇总已在全局HUD时，即便子级后来独立设置提醒也不能撤掉当前轮次。
    active_db=root/'active-parent.db'
    active_parent=tstcmd(active_db,'create',jdmp({'title':'当前父提醒','due_at':100}))['task_id']
    active_child=tstcmd(active_db,'create',jdmp({'title':'后来安排的子级','parent_id':active_parent}))['task_id']
    current=tstcmd(active_db,'plan','101');candidate=next(a for a in current['alerts'] if a['task_id']==active_parent)
    occurrence=tstcmd(active_db,'claim',jdmp(candidate),str(current['revision']),'101')['occurrence_id']
    tstcmd(active_db,'update',active_child,jdmp({'due_at':200}))
    current=tstcmd(active_db,'plan','101')
    req(any(a['task_id']==active_parent and a.get('occurrence_id')==occurrence for a in current['alerts']), '已呈现父轮次不被子级新提醒撤掉')
    tstcmd(active_db,'hold',occurrence,'snooze');current=tstcmd(active_db,'plan','101')
    req(any(a['task_id']==active_parent and a.get('occurrence_id')==occurrence for a in current['alerts']), '已延后父轮次仍保留原身份和提醒')
    # 大量并行事件不压成负宽度。
    overlap = root/'overlap.db'
    for index in range(12):
        tstcmd(overlap,'create',jdmp({'title':f'并行{index}','list_id':work['list_id'],'routine_kind':'background','routine_end':600,'due_at':day+9*3600,'routine_enabled':1,'recurrence_type':'daily','timezone_id':'UTC'}))
    geometry = tstcmd(overlap,'timeline',str(day),'UTC')
    req(max(geometry['columns'])==12 and all(f[2]>=96 for f in geometry['frames']), '并行列可以横向滚动且保留可读宽度')
    single=tstcmd(overlap,'create',jdmp({'title':'独立事件','planned_duration':1800,'due_at':day+12*3600}))
    mixed=tstcmd(overlap,'timeline',str(day),'UTC');req(mixed['frames'][-1][2]==256, '并行组不会撑宽其他普通事件')
    for i,a in enumerate(geometry['frames']):
        for b in geometry['frames'][i+1:]:
            req(a[0]+a[2]<=b[0] or b[0]+b[2]<=a[0], '并行事件不会覆盖彼此')

# HTTP夹具返回真实协议对象，并记录是否发生重定向泄露。
class Fixture(SimpleHTTPRequestHandler):
    mode='valid'; requests=[]
    def log_message(self, *_): pass
    def do_POST(self):
        body=jld(self.rfile.read(int(self.headers['Content-Length'])));self.requests.append((self.path,body,self.headers.get('Authorization')))
        mode=self.mode
        if mode=='redirect':
            self.send_response(302);self.send_header('Location',f'http://127.0.0.1:{self.server.server_port}/stolen');self.end_headers();return
        if mode in ['401','503']:
            self.send_response(int(mode));self.end_headers();return
        result={'title':'整理资料','notes':'完成整理','steps':[{'title':'分类','notes':'分类完成','minutes':15},{'title':'归档','minutes':15}]}
        if mode=='bool':result['steps'][0]['minutes']=True
        if mode=='fraction':result['steps'][0]['minutes']=1.5
        if mode=='total':result['steps'][0]['minutes']=14
        if mode=='limit':result['steps'][0]['minutes']=16;result['steps'][1]['minutes']=14
        if mode=='empty':result['steps']=[]
        if mode=='extra':result['steps'][0]['command']='touch /tmp/unwanted'
        if mode=='notes':result['steps'][0]['notes']=123
        text=jdmp(result)
        if mode=='fenced':text='```json\n'+text+'\n```'
        if mode=='invalid':text='not-json'
        message={'role':'assistant','content':text}
        if mode=='tools':message['tool_calls']=[{'function':{'name':'execute'}}]
        payload=jdmp({'choices':[{'message':message}]}).encode()
        self.send_response(200);self.send_header('Content-Type','application/json');self.end_headers();self.wfile.write(payload)

# 验证网络仅返回草稿，断线、异常和重定向均不写库。
def network(root):
    db=root/'network.db';config=root/'config.json';request=root/'input.json'
    server=ThreadingHTTPServer(('127.0.0.1',0),Fixture);thread=Thread(target=server.serve_forever,daemon=True);thread.start()
    settings={'endpoint':f'http://127.0.0.1:{server.server_port}/v1','model':'auto','key':'fixture-secret'}
    config.write_text(jdmp(settings));request.write_text(jdmp({'title':'整理资料','total_minutes':30,'max_minutes':15}));config.chmod(0o600)
    before=tstcmd(db,'snapshot')
    try:
        for mode in ['valid','fenced','bool','fraction','total','limit','empty','extra','notes','invalid','tools','401','503','redirect']:
            Fixture.mode=mode;ok=mode in ['valid','fenced'];result=tstcmd(db,'ai',str(config),str(request),success=ok)
            if ok:req(len(result['steps'])==2 and result['steps'][0]['planned_duration']==900,'AI结果规范化为可编辑草稿')
            else:req(result['kind']=='assistant_failure','服务异常可以退化手动')
            req(tstcmd(db,'snapshot')==before,'建议生成绝不提前写入数据库')
        req(not any(path=='/stolen' for path,_,_ in Fixture.requests),'拒绝重定向传送任务和密钥')
        req(all(path=='/v1/chat/completions' for path,_,_ in Fixture.requests),'使用已核对的兼容接口路径')
        req(all(auth=='Bearer fixture-secret' for _,_,auth in Fixture.requests),'认证只发送到用户配置地址')
        req(all(body['model']=='auto' and body['stream'] is False and len(body['messages'])==2 for _,body,_ in Fixture.requests),'仅携带单个目标及明确系统格式')
        for endpoint in ['http://192.168.1.1:8765/v1','HTTP://192.168.1.1:8765/v1','http://127.0.0.1:99999/v1']:
            settings['endpoint']=endpoint;config.write_text(jdmp(settings))
            tstcmd(db,'ai',str(config),str(request),success=False)
        req(tstcmd(db,'snapshot')==before,'无效网络配置不影响原任务')
    finally:server.shutdown();server.server_close();thread.join()
    settings['endpoint']=f'http://127.0.0.1:{server.server_port}/v1';config.write_text(jdmp(settings))
    tstcmd(db,'ai',str(config),str(request),success=False)
    req(tstcmd(db,'snapshot')==before,'离线后可以保留全部手动草稿')

if __name__=='__main__':
    with TemporaryDirectory(prefix='trolltask-assistant-') as directory:
        root=Path(directory);division(root);calendar(root);network(root)
    print(f'PASS assistant/timeline: {checks} checks')
