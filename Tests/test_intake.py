# 用真实SQLite与生产门禁验证创建前评估、离线和今日清单。
from head import TemporaryDirectory, Path, jdmp, jld, datetime, timezone, ThreadingHTTPServer, Thread, connect
from test_cli import tstcmd
from assistant_fixture import Handler

checks=0

# 记录有业务意义的断言。
def req(value,name):
 global checks
 assert value,name
 checks+=1

# 创建可复用的全天工作模板。
def seed(db,day):
 tstcmd(db,'routine-import','# TrollTask常律模板v1\n## 周一\n- 09:00~17:00 [工作] 工作\n','work.md')
 row=next(r for r in tstcmd(db,'tasks') if r['routine_kind']=='work')
 tstcmd(db,'update',row['task_id'],jdmp({'routine_enabled':1,'due_at':day+9*3600,'timezone_id':'UTC','routine_end':1020,'recurrence_type':'daily','recurrence':['RRULE:FREQ=DAILY;INTERVAL=1']}))
 return row['task_id']

# 构造独立可验证步骤。
def part(i,minutes):
 return {'task_id':f'33333333-3333-4333-8333-{i:012d}','title':f'步骤{i}','notes':'独立成果','planned_duration':minutes*60}

# 验证完整状态迁移与事务失败后不留半成品。
def run(root):
 db=root/'intake.db';day=datetime(2030,1,7,tzinfo=timezone.utc).timestamp();at=day+8*3600
 seed(db,day)
 fields={'title':'规划验收','due_at':day+9*3600,'deadline_at':day+17*3600,'timezone_id':'UTC','planned_duration':7200}
 estimate={'minimum_minutes':60,'recommended_minutes':120,'maximum_minutes':180,'difficulty':2,'model':'fixture'}
 ctx=lambda f=fields,p=[]:tstcmd(db,'intake',jdmp(f),jdmp(p),str(at))
 verdict=lambda c,e=estimate,m=120,d=False:tstcmd(db,'verdict',jdmp(c),jdmp(e),str(m*60),jdmp(d))
 admit=lambda c,e=estimate,m=120,d=False,ok=True:tstcmd(db,'admit',jdmp(c),jdmp(e),str(m*60),jdmp(d),str(at),success=ok)
 c=ctx();req(c['room']['capacity']==8*3600,'只计算常律工作空档')
 req(verdict(c)['state']=='ready','匹配预算可保存')
 req(verdict(c,m=181)['state']=='adjust','简单任务超给工时必须调整')
 req(verdict(c,m=30)['state']=='split','预算少于最低需求先进入拆分')
 req(verdict(c,m=90)['state']=='ddl','赶DDL必须另行确认')
 req(verdict(c,m=90,d=True)['state']=='ready','最低可行以上允许确认DDL')
 for invalid in [{'minimum_minutes':True,'recommended_minutes':2,'maximum_minutes':3},{'minimum_minutes':10,'recommended_minutes':5,'maximum_minutes':20},{'minimum_minutes':0,'recommended_minutes':1,'maximum_minutes':1}]:
  tstcmd(db,'verdict',jdmp(c),jdmp(invalid),'120','false',success=False);req(True,'无效AI区间被拒绝')
 before=tstcmd(db,'snapshot');admit(c,m=30,ok=False);admit(c,m=90,d=True,ok=False)
 req(tstcmd(db,'snapshot')==before,'低预算和未取得DDL方案都不能提前写库')
 saved=admit(c);id=saved['task_id'];req(saved['planning_mode']=='window','新建普通任务使用窗口规划')
 req(tstcmd(db,'review',id)['state']=='ready','评估与任务同库保存')
 admit(c,ok=False);req(len(tstcmd(db,'tasks'))==2,'连续提交只创建一次')
 plan=tstcmd(db,'day',str(day),'UTC');entry=next(e for e in plan['entries'] if e['task_id']==id)
 req(entry['start_at']==day+9*3600 and entry['end_at']==day+11*3600,'窗口内实际只安排需要的两小时')
 req(all(a['kind']=='deadline' or a['remind_at']==entry['start_at'] for a in tstcmd(db,'plan',str(day+8*3600))['alerts'] if a['task_id']==id),'窗口起点不冒充固定提醒')
 today=tstcmd(db,'today',str(day+8*3600),'UTC');req(sum(r['task_id']==id for r in today)==1,'今日清单不复制父任务或任务记录')
 req(not any(r['routine_kind']=='work' for r in today),'工作容器不作为待办重复展示')
 req(not any(r['task_id']==id for r in tstcmd(db,'today',str(day-86400),'UTC')),'未来任务不会提前混进今日律')
 other=ctx(dict(fields,title='第二项'))
 req(other['room']['capacity']==6*3600,'已有任务会扣除可用工时')
 tstcmd(db,'update',id,jdmp({'notes':'外部修改'}));admit(other,ok=False)
 req(tstcmd(db,'review',id)['state']=='stale','重新编辑后旧评估明确失效')
 re=ctx(dict(fields,task_id=id));admit(re);req(tstcmd(db,'review',id)['state']=='ready','原任务可补做评估且UUID不变')
 offline={'offline':True}
 for days,state in [(3,'blocked'),(2.999,'offline'),(2,'offline')]:
  f=dict(fields,title='离线边界',deadline_at=fields['due_at']+days*86400)
  c=ctx(f);req(verdict(c,offline)['state']==state,'离线三天含边界严格判断')
 short=ctx(dict(fields,title='离线任务'));off=admit(short,offline);req(tstcmd(db,'review',off['task_id'])['state']=='offline','离线任务保留待补评估状态')
 # 已占用四小时，仅剩四小时；大任务不能因拆分而凭空增加容量。
 c=ctx(dict(fields,title='不可行任务'));req(verdict(c,dict(estimate,minimum_minutes=300,recommended_minutes=360,maximum_minutes=480),m=360)['state']=='adjust','总工时不足不能靠拆分绕过')
 tstcmd(db,'delete',id);tstcmd(db,'delete',off['task_id'])
 c=ctx(dict(fields,title='DDL任务'),[part(1,45),part(2,45)]);urgent=dict(estimate,ddl_verified=True)
 urgent_task=admit(c,urgent,m=90,d=True);children=[r for r in tstcmd(db,'tasks') if r['parent_id']==urgent_task['task_id']]
 req(len(children)==2,'最高档DDL方案确认后一次保存完整子任务')
 row=tstcmd(db,'today',str(at),'UTC');req(not any(r['task_id']==urgent_task['task_id'] for r in row),'今日只显示实际执行子任务')
 req([r['task_id'] for r in row if r['parent_id']==urgent_task['task_id']]==[part(1,45)['task_id'],part(2,45)['task_id']],'AI依赖顺序保持且实际排入空档')
 malformed=ctx(dict(fields,title='错误步骤'),[part(3,20),part(4,20)])
 req(verdict(malformed,m=120)['state']=='split','步骤总工时不一致不能保存')
 before=tstcmd(db,'snapshot');admit(malformed,ok=False);req(tstcmd(db,'snapshot')==before,'失败的父子提交完全回滚')
 # 午夜和重复事件只影响当前日，不重新生成副本。
 tstcmd(db,'complete-next',part(1,45)['task_id']);req(not any(r['task_id']==part(1,45)['task_id'] and r['status']!='completed' for r in tstcmd(db,'today',str(at),'UTC')),'完成子任务不再作为未完成出现')
 req(tstcmd(db,'schema')['schema_version']==15,'单库迁移版本正确')

# 验证真实请求分档、结构化输出和服务静默换模型的阻断。
def network(root):
 db=root/'network.db';server=ThreadingHTTPServer(('127.0.0.1',0),Handler);server.log=root/'routes.jsonl'
 worker=Thread(target=server.serve_forever,daemon=True);worker.start()
 config={'endpoint':f'http://127.0.0.1:{server.server_port}/v1','model':'deepseek-v4.1-flash','hard_model':'glm-5.3','ddl_model':'glm-5.3'}
 configpath=root/'config.json';inputpath=root/'input.json';configpath.write_text(jdmp(config))
 # 每项都经过原生URLSession和生产JSON校验。
 def call(query,ok=True):
  inputpath.write_text(jdmp(query));return tstcmd(db,'ai',str(configpath),str(inputpath),success=ok)
 try:
  base={'mode':'assessment','title':'网络协议验收','difficulty':0,'notes':'本机备注','existing_steps':[{'title':'一步','notes':'本机步骤备注'}]}
  for difficulty,ddl,model in [(0,False,'deepseek-v4.1-flash'),(2,False,'glm-5.3'),(3,True,'glm-5.3')]:
   query=dict(base,difficulty=difficulty,ddl=ddl)
   if ddl:query['total_minutes']=45
   result=call(query);req(result['model']==model,'默认、复杂、DDL分别使用真实指定模型');req(result['ddl_verified']==ddl,'只有最高档DDL响应持有确认凭据')
  for variant in ['range','sum','negative','tool','model']:
   server.variant=variant;before=tstcmd(db,'snapshot');failure=call(base,False);req(failure['code']!=2,'无效结果和静默模型替换不能伪装离线');req(tstcmd(db,'snapshot')==before,'无效AI响应不修改数据库')
  server.variant='';query={'mode':'order','difficulty':3,'tasks':[{'task_id':'a','notes':'日内备注'},{'task_id':'b'}]};req(call(query)['order']==['b','a'],'日内AI排序返回完整原ID集合')
  call({'mode':'split','title':'拆分请求','notes':'本机拆分备注'})
  records=[jld(record) for record in server.log.read_text().splitlines()]
  req(records[-1]['has_notes'],'拆分请求携带用户备注以贴合任务')
  req(all(not record['has_notes'] for record in records[:-1]),'评估和排序请求仍不携带用户备注')
  for variant in ['duplicate','foreign']:
   server.variant=variant;call(query,False);req(True,'重复或外来任务不能进入日内排序')
 finally:server.shutdown();worker.join();server.server_close()

# 容量足够也必须按顺序排得下；失败事务不留父子或评估残片。
def boundaries(root):
 db=root/'boundaries.db';day=datetime(2030,1,7,tzinfo=timezone.utc).timestamp();at=day+8*3600;work=seed(db,day);tstcmd(db,'update',work,jdmp({'routine_end':720}))
 busy=tstcmd(db,'create',jdmp({'title':'固定占用','due_at':day+10*3600,'planned_duration':3600}))
 fields={'title':'碎片空档','due_at':day+9*3600,'deadline_at':day+12*3600,'timezone_id':'UTC','planned_duration':7200,'rush':True}
 estimate={'minimum_minutes':90,'recommended_minutes':120,'maximum_minutes':150,'difficulty':2}
 rows=[part(10,45),part(11,45),part(12,30)]
 c=tstcmd(db,'intake',jdmp(fields),jdmp(rows),str(at));v=tstcmd(db,'verdict',jdmp(c),jdmp(estimate),'7200','false')
 req(c['room']['capacity']==7200 and v['state']=='adjust','两小时总空档仍排不下45、45、30分钟的依赖步骤')
 req(v['suggested_end']>fields['deadline_at'],'不足时建议实际排得下的更晚结束时刻')
 fields['deadline_at']+=86400;c=tstcmd(db,'intake',jdmp(fields),jdmp(rows),str(at));req(tstcmd(db,'verdict',jdmp(c),jdmp(estimate),'7200','false')['state']=='ready','延长窗口后顺序排程可行')
 before=tstcmd(db,'snapshot')
 with connect(db) as connection:connection.execute("CREATE TRIGGER fail_review BEFORE INSERT ON task_reviews BEGIN SELECT RAISE(ABORT,'fixture');END")
 tstcmd(db,'admit',jdmp(c),jdmp(estimate),'7200','false',str(at),success=False);req(tstcmd(db,'snapshot')==before,'评估保存失败时父子与全部时刻均整体回滚')
 with connect(db) as connection:connection.execute('DROP TRIGGER fail_review')
 parent=tstcmd(db,'admit',jdmp(c),jdmp(estimate),'7200','false',str(at));plan=tstcmd(db,'day',str(day),'UTC');entries=[e for e in plan['entries'] if e['task']['parent_id']==parent['task_id']]
 actual=[e['task_id'] for e in entries];expected=[part(10,45)['task_id'],part(11,45)['task_id']]
 req(actual==expected,'次序不足时不能把后一步提前塞回前面空档 actual=%r expected=%r'%(actual,expected))
 req(entries[0]['end_at']<=entries[1]['start_at'],'子任务按依赖顺序执行')
 # 日内排序必须是原候选的置换，旧排序不能重复应用。
 context=tstcmd(db,'day-order',str(at));order=[r['task_id'] for r in context['tasks']]
 tstcmd(db,'apply-order',jdmp(context),jdmp({'order':order+order}),str(at),success=False);req(True,'日内重复ID被拒绝')
 tstcmd(db,'apply-order',jdmp(context),jdmp({'order':order}),str(at));tstcmd(db,'apply-order',jdmp(context),jdmp({'order':order}),str(at),success=False);req(True,'日内排序一次生效后拒绝旧结果')
 # 完成既有步骤后，重评只统计剩余工时并保留完成内容。
 tstcmd(db,'complete',part(10,45)['task_id']);f=dict(fields,task_id=parent['task_id']);c=tstcmd(db,'intake',jdmp(f),jdmp(rows),str(at))
 req(c['completed_effort']==2700,'已完成子任务从剩余工作量中扣除')
 e={'minimum_minutes':60,'recommended_minutes':75,'maximum_minutes':90};req(tstcmd(db,'verdict',jdmp(c),jdmp(e),'4500','false')['state']=='ready','重评剩余步骤不把完成工时重复占用')
 # 离线三天使用当地日历，跨夏令时也不能绕过。
 f={'title':'夏令时边界','due_at':datetime(2030,3,9,20,tzinfo=timezone.utc).timestamp(),'deadline_at':datetime(2030,3,12,19,tzinfo=timezone.utc).timestamp(),'timezone_id':'America/Los_Angeles'}
 c=tstcmd(db,'intake',jdmp(f),'[]',str(f['due_at']-3600));req(tstcmd(db,'verdict',jdmp(c),jdmp({'offline':True}),'600','false')['state']=='blocked','夏令时少一小时仍属于三天离线禁区')
 # 从第11版升级，失败回滚，恢复后保留全部旧任务。
 migration=root/'migration.db';old=tstcmd(migration,'create',jdmp({'title':'原任务'}))
 with connect(migration) as connection:
  connection.executescript(Path('Tests/Fixtures/archive-v12.sql').read_text())
  connection.executescript("DROP TABLE task_reviews;ALTER TABLE tasks DROP COLUMN planning_mode;UPDATE store_meta SET schema_version=11;CREATE TRIGGER fail_v12 BEFORE UPDATE ON store_meta WHEN NEW.schema_version=12 BEGIN SELECT RAISE(ABORT,'fixture');END;")
 tstcmd(migration,'schema',success=False)
 with connect(migration) as connection:
  req(connection.execute('SELECT schema_version FROM store_meta').fetchone()[0]==11,'迁移失败保留版本十一');req(not any(r[1]=='planning_mode' for r in connection.execute('PRAGMA table_info(tasks)')),'迁移失败回滚新增列');connection.execute('DROP TRIGGER fail_v12')
 req(tstcmd(migration,'schema')['schema_version']==15 and tstcmd(migration,'get',old['task_id'])['title']=='原任务','迁移恢复保留原身份与内容')

# 通过真实事务校验整日窗口、最长天数、加星和备注保留。
def calendar_days(root):
 db=root/'calendar-days.db';day=datetime(2030,1,7,tzinfo=timezone.utc).timestamp();at=day+7*3600
 seed(db,day)
 fields={'title':'总目标','notes':'私有备注','due_at':day,'deadline_at':day+86400,'timezone_id':'UTC','schedule_kind':'date','deadline_kind':'date','planning_mode':'window','starred':True,'difficulty':2,'urgency':0}
 ctx=lambda **changes:tstcmd(db,'intake',jdmp(dict(fields,**changes)),jdmp([]),str(at))
 req(ctx(deadline_at=day+30*86400)['fields']['deadline_at']==day+30*86400,'最多允许30个自然日')
 for invalid in [dict(deadline_at=day+31*86400),dict(due_at=day+3600)]:
  error=tstcmd(db,'intake',jdmp(dict(fields,**invalid)),jdmp([]),str(at),success=False)
  req(error['code']!=2,'拒绝第31天或非整日起点')
 estimate={'minimum_minutes':15,'recommended_minutes':30,'maximum_minutes':45,'difficulty':3}
 row=tstcmd(db,'admit',jdmp(ctx()),jdmp(estimate),'1800','false',str(at))
 req(row['schedule_kind']==row['deadline_kind']=='date' and row['deadline_at']==day+86400,'同一天覆盖含截止日期在内的完整一天')
 req(row['starred']==1 and row['urgency']==3 and row['difficulty']==2 and row['notes']=='私有备注','手动加星保存高紧急度，保留所选难易度和备注')
 alerts=tstcmd(db,'plan',str(at))['alerts']
 req(any(alert['task_id']==row['task_id'] and alert['kind']=='deadline' and alert['scheduled_at']==day+86400 for alert in alerts),'整日任务在截止日期结束时触发到期')
 first=datetime(2030,10,15,4,tzinfo=timezone.utc).timestamp();last=datetime(2030,11,14,5,tzinfo=timezone.utc).timestamp()
 local=dict(fields,due_at=first,deadline_at=last,timezone_id='America/New_York')
 req(tstcmd(db,'intake',jdmp(local),'[]',str(first))['fields']['deadline_at']==last,'跨夏令时按当地日历而非固定小时数计30天')

# 验证低/中/高/赶DDL的每日配额、难度数量和创建门禁。
def density(root):
 day=int(datetime(2030,1,7,tzinfo=timezone.utc).timestamp());at=day+8*3600
 def fresh(name):
  db=root/(name+'.db');seed(db,day);return db
 def base(**kw):
  row={'title':'密度','due_at':day+9*3600,'deadline_at':day+17*3600,'timezone_id':'UTC','difficulty':2}
  row.update(kw);return row
 def case(name,fields,parts,ok):
  db=fresh(name);c=tstcmd(db,'intake',jdmp(fields),jdmp(parts),str(at));effort=sum(p['planned_duration'] for p in parts) if parts else 60
  est={'minimum_minutes':max(1,effort//60),'recommended_minutes':max(1,effort//60),'maximum_minutes':max(1,effort//60),'difficulty':fields.get('difficulty',2)}
  v=tstcmd(db,'verdict',jdmp(c),jdmp(est),str(effort),'false')
  if ok:
   req(v['state'] in ['ready','offline'],name+' 允许');tstcmd(db,'admit',jdmp(c),jdmp(est),str(effort),'false',str(at))
  else:
   req(v['state'] not in ['ready','offline'] or tstcmd(db,'admit',jdmp(c),jdmp(est),str(effort),'false',str(at),success=False) is not None,name+' 拒绝')
  return db,c
 # 低紧急 1/3：一天 8 小时最多 2h40，三小时排不下；延到两天可行。
 case('low-one-day',base(urgency=1),[part(20,60),part(21,60),part(22,60)],False)
 db,c=case('low-two-days',base(urgency=1,deadline_at=day+17*3600+86400),[part(23,60),part(24,60),part(25,60)],True)
 days=[int((p['day_at']-day)//86400) for p in c.get('dry',{}).get('placements',[])]
 req(days.count(0)==2 and days.count(1)==1,'低紧急跨天密度')
 # 高紧急留 1 小时：七小时可行，七小时半不可行。
 case('high-seven',base(urgency=3),[part(26,420)],True)
 case('high-seven-half',base(urgency=3),[part(27,450)],False)
 # 赶DDL可以占满：八小时可行，八小时半不可行。
 case('ddl-eight',base(urgency=3,rush=True),[part(28,480)],True)
 case('ddl-eight-half',base(urgency=3,rush=True),[part(29,510)],False)
 # 困难任务每天最多一个：三天窗口可行，一天不可行。
 case('hard-one-day',base(urgency=1,difficulty=3),[part(30,20),part(31,20),part(32,20)],False)
 case('hard-three-days',base(urgency=1,difficulty=3,deadline_at=day+17*3600+2*86400),[part(33,20),part(34,20),part(35,20)],True)
 # 窗口被已有任务占满时禁止新任务。
 db=fresh('full');tstcmd(db,'create',jdmp({'title':'占满','due_at':day+9*3600,'deadline_at':day+17*3600,'timezone_id':'UTC','planned_duration':8*3600,'planning_mode':'window'}))
 c=tstcmd(db,'intake',jdmp(base(title='新任务')),'[]',str(at));req(c['room']['capacity']==0,'占满窗口空余为零')
 v=tstcmd(db,'verdict',jdmp(c),jdmp({'minimum_minutes':60,'recommended_minutes':60,'maximum_minutes':60,'difficulty':2}),'3600','false')
 req(v['state']=='adjust' and tstcmd(db,'admit',jdmp(c),jdmp({'minimum_minutes':60,'recommended_minutes':60,'maximum_minutes':60,'difficulty':2}),'3600','false',str(at),success=False) is not None,'占满窗口拒绝创建')

with TemporaryDirectory(prefix='trolltask-intake-') as folder:
 root=Path(folder);run(root);network(root);boundaries(root);calendar_days(root);density(root)
print(f'创建评估专项通过：{checks}项')
