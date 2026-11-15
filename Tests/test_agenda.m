#import "LBHead.h"

static int checks;
// 累计有明确失败信息的日程断言。
static void ag_req(BOOL valid, NSString *message) { if (!valid) { NSLog(@"日程失败：%@",message); abort(); } checks++; }
// 解析确定性的UTC测试时刻。
static double ag_time(NSString *text) { NSDateFormatter *f=[NSDateFormatter new];f.locale=[[NSLocale alloc]initWithLocaleIdentifier:@"en_US_POSIX"];f.timeZone=[NSTimeZone timeZoneForSecondsFromGMT:0];f.dateFormat=@"yyyy-MM-dd HH:mm";return [f dateFromString:text].timeIntervalSince1970; }
// 打开隔离存储。
static TaskStore *ag_store(NSString *path) { NSError *error=nil;TaskStore *s=[[TaskStore alloc]initAt:path error:&error];ag_req(s!=nil,error.localizedDescription);return s; }
// 建立固定或可安排的每日常律。
static NSDictionary *ag_rtn(TaskStore *store, NSString *title, NSString *kind, double start, NSInteger end, BOOL enabled) {
    NSError *error=nil;NSDictionary *r=[store crtTsk:@{@"title":title,@"list_id":TS_RTN_LST,@"due_at":@(start),@"routine_kind":kind,@"routine_end":@(end),@"routine_enabled":@(enabled),@"recurrence_type":@"daily",@"timezone_id":@"UTC"} error:&error];ag_req(r!=nil,error.localizedDescription);return r;
}
// 按稳定身份查找某任务的展示或分配。
static NSDictionary *ag_find(NSArray *rows, NSString *taskID) { for(NSDictionary *r in rows)if([r[@"task_id"] ?: r[@"task"][@"task_id"] isEqual:taskID])return r;return nil; }
// 核对一般任务填空、固定常律、跨日与稳定写入。
static void ag_day(NSString *path) {
    TaskStore *s=ag_store(path);double day=ag_time(@"2026-11-02 00:00"),now=day+6*3600;
    ag_rtn(s,@"一般任务",@"work",day+9*3600,12*60,YES);
    NSDictionary *meal=ag_rtn(s,@"用餐",@"fixed",day+10*3600,10*60+30,YES);
    ag_rtn(s,@"听歌",@"background",day+11.5*3600,12*60,YES);
    ag_rtn(s,@"已停用",@"fixed",day+6*3600,7*60,NO);
    NSDictionary *a=[s crtTsk:@{@"title":@"任务A",@"planned_duration":@2400,@"position":@1} error:nil];
    NSDictionary *b=[s crtTsk:@{@"title":@"任务B",@"planned_duration":@3600,@"position":@2} error:nil];
    NSDictionary *c=[s crtTsk:@{@"title":@"放不下",@"planned_duration":@7200,@"position":@3} error:nil];
    [s crtTsk:@{@"title":@"未估时"} error:nil];
    NSDictionary *finished=[s crtTsk:@{@"title":@"已提前完成的固定任务",@"due_at":@(day+9.5*3600)} error:nil];
    ag_req([s cmplTsk:finished[@"task_id"] error:nil],@"已完成但未估时的旧任务不阻塞新安排");
    NSDictionary *plan=[s dayAt:day zone:@"UTC" now:now error:nil];
    ag_req([plan[@"conflicts"] count]==0,@"工作占位避让具体安排");ag_req([plan[@"allocations"] count]==2,@"只安排能放下的两个任务");
    ag_req([ag_find(plan[@"allocations"],a[@"task_id"])[@"start_at"] doubleValue]==day+9*3600,@"按既有顺序安排任务A");
    ag_req([ag_find(plan[@"allocations"],b[@"task_id"])[@"start_at"] doubleValue]==day+10.5*3600,@"任务B整项跨过用餐占用");
    ag_req(ag_find(plan[@"allocations"],c[@"task_id"])==nil && [plan[@"unplaced"] count]==2,@"超容量和无预计分钟明确列出");
    ag_req([plan[@"draft_count"] integerValue]==1,@"停用事项不占时间也不提醒");
    ag_req([s arrangeAt:now zone:@"UTC" error:nil],@"同库原子安排成功");long long revision=[s revision:nil];
    ag_req([s arrangeAt:now zone:@"UTC" error:nil] && [s revision:nil]==revision,@"重复事件不反复写入或发送通知");
    NSDictionary *snapshot=[s planAt:now error:nil];
    ag_req(ag_find(snapshot[@"alerts"],a[@"task_id"])!=nil,@"未设日期的普通任务接入现有调度");
    ag_req([s rdTsk:a[@"task_id"] error:nil][@"due_at"]==NSNull.null,@"排程不覆盖用户原计划字段");
    NSDictionary *claim=[s claim:ag_find(snapshot[@"alerts"],a[@"task_id"]) revision:[snapshot[@"revision"] longLongValue] at:day+9*3600 error:nil];
    ag_req(claim!=nil,@"日程候选通过原提醒认领核验");
    NSDictionary *fresh=[s crtTsk:@{@"title":@"刚加入",@"planned_duration":@60,@"position":@0} error:nil];
    ag_req([s arrangeAt:day+9*3600+1 zone:@"UTC" error:nil],@"当前提醒期间允许计算但不抢占");
    plan=[s dayAt:day zone:@"UTC" now:day+9*3600+1 error:nil];ag_req(!ag_find(plan[@"allocations"],fresh[@"task_id"]),@"上项未提交时不挪动或新增当前任务");
    ag_req([s actOcc:claim[@"occurrence_id"] action:@"complete" until:nil error:nil],@"完成沿用既有状态机");
    ag_req([[s rdTsk:a[@"task_id"] error:nil][@"status"] isEqual:@"completed"],@"普通任务只完成一次");
    snapshot=[s planAt:day+9*3600+2 error:nil];ag_req(!ag_find(snapshot[@"alerts"],a[@"task_id"]),@"完成不被日程重新触发");
    ag_req([s lsOcc:a[@"task_id"] error:nil].count==1,@"重复调度不重复Occurrence");
    ag_req(![s delLst:TS_RTN_LST error:nil] && ![s updLst:TS_RTN_LST title:@"改名" error:nil],@"常律清单常驻保护");
    ag_req([s updTsk:meal[@"task_id"] fields:@{@"routine_enabled":@0} error:nil],@"可停用单条常律");
}
// 核对重复日期任务提前填空后仍保留原轮次身份与一次延期。
static void ag_repeat(NSString *path) {
    TaskStore *s=ag_store(path);double day=ag_time(@"2026-11-02 00:00"),now=day+7*3600;
    ag_rtn(s,@"早间工作",@"work",day+8*3600,9*60,YES);
    NSDictionary *task=[s crtTsk:@{@"title":@"每日普通任务",@"due_at":@(day),@"schedule_kind":@"date",@"timezone_id":@"UTC",@"recurrence_type":@"daily",@"planned_duration":@1200} error:nil];
    NSDictionary *snap=[s planAt:now error:nil],*alert=ag_find(snap[@"alerts"],task[@"task_id"]);
    ag_req([alert[@"remind_at"] doubleValue]==day+8*3600 && [alert[@"scheduled_at"] doubleValue]==day+9*3600,@"安排早于默认九点但不更换原身份");
    NSDictionary *occ=[s claim:alert revision:[snap[@"revision"] longLongValue] at:day+8*3600 error:nil];ag_req(occ!=nil,@"日期轮次可按安排时间认领");
    ag_req([s hldOcc:occ[@"occurrence_id"] mode:@"snooze" error:nil]!=nil,@"日程轮次仍只使用原五分钟延后");
    snap=[s planAt:day+8*3600+1 error:nil];alert=ag_find(snap[@"alerts"],task[@"task_id"]);
    NSDictionary *row=[s lsOcc:task[@"task_id"] error:nil].firstObject;
    // 按原轮次匹配，真实五分钟延期可能晚于下一日的另一轮。
    alert=nil;for(NSDictionary *candidate in snap[@"alerts"])if([candidate[@"task_id"]isEqual:task[@"task_id"]] && [candidate[@"cycle_at"]isEqual:row[@"cycle_at"]]){alert=candidate;break;}
    ag_req([alert[@"remind_at"] isEqual:row[@"next_fire_at"]],@"重新排程不吞掉或重置延期");
    ag_req([s rsmOcc:occ[@"occurrence_id"] error:nil],@"从延后恢复当前轮次");
    ag_req([s actOcc:occ[@"occurrence_id"] action:@"complete" until:nil error:nil],@"完成当前日重复");
    snap=[s planAt:now error:nil];ag_req([ag_find(snap[@"alerts"],task[@"task_id"])[@"cycle_at"] doubleValue]>day,@"当前轮完成只剩后续轮次");
    NSDictionary *both=[s crtTsk:@{@"title":@"日期与截止同刻",@"due_at":@(day),@"schedule_kind":@"date",@"deadline_at":@(day+9*3600),@"planned_duration":@600,@"timezone_id":@"UTC"} error:nil];
    snap=[s planAt:now error:nil];alert=ag_find(snap[@"alerts"],both[@"task_id"]);
    ag_req([alert[@"kind"] isEqual:@"both"] && [alert[@"remind_at"] doubleValue]==day+8*3600 && [alert[@"scheduled_at"] doubleValue]==day+9*3600,@"合并双提醒也能安排且保持唯一原身份");
    occ=[s claim:alert revision:[snap[@"revision"] longLongValue] at:day+8*3600 error:nil];ag_req(occ!=nil,@"合并双提醒按安排时刻认领");
    ag_req([s actOcc:occ[@"occurrence_id"] action:@"complete" until:nil error:nil] && [s lsOcc:both[@"task_id"] error:nil].count==1,@"合并双提醒只完成一轮");
}
// 核对冲突、截止、非法字段及当地日界。
static void ag_edges(NSString *path) {
    TaskStore *s=ag_store(path);double day=ag_time(@"2026-11-02 00:00");
    ag_rtn(s,@"工作",@"work",day+9*3600,12*60,YES);
    ag_rtn(s,@"会议A",@"fixed",day+10*3600,11*60,YES);
    NSDictionary *legacy=ag_rtn(s,@"会议B",@"fixed",day+12*3600,13*60,YES);
    // 模拟旧版重叠记录，读取时仍须暴露冲突。
    sqlite3 *db=NULL;ag_req(sqlite3_open(path.fileSystemRepresentation,&db)==SQLITE_OK,@"打开旧版冲突夹具");
    NSString *sql=[NSString stringWithFormat:@"UPDATE tasks SET due_at=%.0f,routine_end=720 WHERE task_id='%@'",day+10.5*3600,legacy[@"task_id"]];
    ag_req(sqlite3_exec(db,sql.UTF8String,NULL,NULL,NULL)==SQLITE_OK,@"写入旧版重叠夹具");sqlite3_close(db);
    [s crtTsk:@{@"title":@"普通待办",@"planned_duration":@60} error:nil];
    NSDictionary *plan=[s dayAt:day zone:@"UTC" now:day error:nil];ag_req([plan[@"conflicts"] count]>0 && [plan[@"allocations"] count]==0,@"固定冲突不靠挤占普通任务掩盖");ag_req([plan[@"entries"] count]>=2,@"冲突安排仍按真实时间显示供用户修正");
    ag_req([s dayAt:day zone:@"Invalid/Zone" now:day error:nil]==nil,@"非法时区不生成日程");
    ag_req([s crtTsk:@{@"title":@"非法常律",@"list_id":TS_RTN_LST,@"routine_kind":@"fixed"} error:nil]==nil,@"缺少时间和重复不能启用常律");
    ag_req([s crtTsk:@{@"title":@"非法结束",@"routine_end":@1440} error:nil]==nil,@"结束分钟越界拒绝");
    plan=[s dayAt:ag_time(@"2026-11-01 12:00") zone:@"America/New_York" now:0 error:nil];ag_req([plan[@"day_end"] doubleValue]-[plan[@"day_at"] doubleValue]==90000,@"秋季夏令时按当地25小时日界");
    plan=[s dayAt:ag_time(@"2026-03-08 12:00") zone:@"America/New_York" now:0 error:nil];ag_req([plan[@"day_end"] doubleValue]-[plan[@"day_at"] doubleValue]==82800,@"春季夏令时按当地23小时日界");
}
// 执行日程真实存储测试。
static void ag_import(NSString *path) {
    TaskStore *s=ag_store(path);NSString *text=@"``` 晨间套装\n- 7:00~7:10 起床\n- 7:10~7:20 洗漱\n```\n``` 常规\n- ## 周一\n```\n## 周一\n1. 7:00~7:20 **晨间套装**\n2. 8:00~10:00 根据一般待办按顺序完成任务\n3. 22:00~次日 休息\n4. 10:00~11:00 异步1{看盘} 异步2{按顺序完成任务}\n## 周二\n1. 7:00~7:20 **晨间套装**\n## 周六\n1. 7:00~次日 **常规**\n2. 去除1{所有关于看盘的任务去掉，留出的时间加入一般工作}\n";
    NSError *error=nil;NSDictionary *doc=[TaskRoutineImport parse:text source:@"test.md" anchor:[NSDate dateWithTimeIntervalSince1970:ag_time(@"2026-11-02 12:00")] zone:@"UTC" error:&error];
    ag_req(doc!=nil,error.localizedDescription);ag_req([doc[@"tasks"] count]>=6 && [doc[@"warnings"] count]>0,@"展开套装和继承，并保留次日结束歧义");
    for(NSDictionary *task in doc[@"tasks"])ag_req([task[@"routine_enabled"] isEqual:@0],@"全部导入项明确禁用");
    ag_req([s importRtns:doc error:nil]==nil && [s lsTsks:nil].count==0,@"旧版不完整草稿禁止入库");
    NSString *template=@"# TrollTask常律模板v1\n## 周一\n- 07:00~07:10 [固定] 起床\n- 07:10~07:20 [固定] 洗漱\n";
    doc=[TaskRoutineImport load:template source:@"test.md" anchor:NSDate.date zone:@"UTC" error:&error];
    NSDictionary *result=doc ? [s importRtns:doc error:&error] : nil;ag_req(result!=nil,error.localizedDescription);
    ag_req([result[@"added"] unsignedIntegerValue]==2,@"整批创建正式常律");
    long long revision=[s revision:nil];result=[s importRtns:doc error:nil];
    ag_req([result[@"added"] integerValue]==0 && [s revision:nil]==revision,@"重复导入无重复任务和通知");
    NSMutableDictionary *bad=[doc mutableCopy];bad[@"text"]=[template stringByAppendingString:@"修改"];
    ag_req([s importRtns:bad error:nil]==nil && [s revision:nil]==revision,@"同名变化不覆盖用户常律");
    ag_req([TaskRoutineImport parse:@"没有时间表" source:@"empty.md" anchor:NSDate.date zone:@"UTC" error:nil]==nil,@"无按周条目明确报错");
}

// 核对跨夜、截止、改删、时钟跳转及重开后保持原分配身份。
static void ag_slots(NSString *path) {
    double day=ag_time(@"2026-11-02 00:00"),now=day+6*3600;
    TaskStore *s=ag_store(path);
    ag_rtn(s,@"跨夜休息",@"rest",day-2*3600,7*60,YES);
    ag_rtn(s,@"工作",@"work",day+7*3600,9*60,YES);
    NSDictionary *a=[s crtTsk:@{@"title":@"限时任务",@"planned_duration":@1800,@"deadline_at":@(day+7.5*3600)} error:nil];
    NSDictionary *b=[s crtTsk:@{@"title":@"截止前放不下",@"planned_duration":@3600,@"deadline_at":@(day+7.5*3600)} error:nil];
    NSDictionary *plan=[s dayAt:day zone:@"UTC" now:now error:nil];
    ag_req([ag_find(plan[@"entries"],a[@"task_id"])[@"end_at"] doubleValue]==day+7.5*3600,@"任务必须在独立截止前完整结束");
    ag_req([ag_find(plan[@"unplaced"],b[@"task_id"])[@"needs_split"] boolValue] && !ag_find(plan[@"allocations"],b[@"task_id"]) && [[s rdTsk:b[@"task_id"] error:nil][@"deadline_at"] doubleValue]==day+7.5*3600,@"截止不足进入拆分且不得覆盖原截止");
    ag_req([plan[@"entries"][0][@"start_at"] doubleValue]==day && [plan[@"entries"][0][@"end_at"] doubleValue]==day+7*3600,@"跨夜常律占用次日零点到结束");
    ag_req([s arrangeAt:now zone:@"UTC" error:nil],@"持久保存当天分配");
    TaskStore *reader=ag_store(path);NSDictionary *snapshot=[reader planAt:now error:nil],*first=ag_find(snapshot[@"alerts"],a[@"task_id"]);
    ag_req([first[@"remind_at"] doubleValue]==day+7*3600,@"重开存储仍可恢复未到期安排");
    NSDictionary *back=[reader planAt:now-86400 error:nil];
    ag_req([ag_find(back[@"alerts"],a[@"task_id"])[@"cycle_at"] isEqual:first[@"cycle_at"]],@"时间后跳不能为同一普通任务生成另一轮");
    snapshot=[reader planAt:day+8*3600 error:nil];NSDictionary *late=ag_find(snapshot[@"alerts"],a[@"task_id"]);
    ag_req([late[@"remind_at"] isEqual:first[@"remind_at"]],@"休眠错过安排时刻仍保留已到期候选");
    NSDictionary *occ=[reader claim:late revision:[snapshot[@"revision"] longLongValue] at:day+8*3600 error:nil];
    ag_req(occ!=nil,@"错过时刻可以补弹同一轮");
    ag_req([reader actOcc:occ[@"occurrence_id"] action:@"complete" until:nil error:nil],@"补弹完成当前轮");
    snapshot=[s planAt:now-86400 error:nil];ag_req(!ag_find(snapshot[@"alerts"],a[@"task_id"]),@"完成后时间后跳也不能复活");
    NSDictionary *c=[s crtTsk:@{@"title":@"未来修改",@"planned_duration":@1200,@"position":@2} error:nil];
    ag_req([s arrangeAt:now zone:@"UTC" error:nil],@"新增一般任务分配");
    ag_req([s updTsk:c[@"task_id"] fields:@{@"planned_duration":@2400} error:nil],@"未来用时可修改");
    plan=[s dayAt:day zone:@"UTC" now:now error:nil];NSDictionary *slot=ag_find(plan[@"allocations"],c[@"task_id"]);
    ag_req([slot[@"end_at"] doubleValue]-[slot[@"start_at"] doubleValue]==2400,@"修改后重新核算容量");
    ag_req([s delTsk:c[@"task_id"] error:nil],@"删除未来安排");snapshot=[s planAt:now error:nil];
    ag_req(!ag_find(snapshot[@"alerts"],c[@"task_id"]),@"已删除分配不能继续提醒");
}
// 使用一千个真实普通任务验证容量、顺序和调度查询。
static void ag_batch(NSString *path) {
    TaskStore *s=ag_store(path);double day=ag_time(@"2026-11-02 00:00");
    ag_rtn(s,@"全天任务时段",@"work",day,0,YES);
    ag_req([s wrTxn:^BOOL(NSError **error) {
        for(int i=0;i<1000;i++)if(![s crtTsk:@{@"title":[NSString stringWithFormat:@"批量%d",i],@"position":@(i),@"planned_duration":@60} error:error])return NO;return YES;
    } error:nil],@"一千任务原子创建");
    double started=NSDate.timeIntervalSinceReferenceDate;NSDictionary *plan=[s dayAt:day zone:@"UTC" now:day error:nil];
    ag_req([plan[@"allocations"] count]==1000 && [plan[@"conflicts"] count]==0,@"一千任务在一天内按序无重叠分配");
    double previous=day;for(NSDictionary *slot in plan[@"allocations"]) { ag_req([slot[@"start_at"] doubleValue]>=previous,@"相邻任务区间不重叠");previous=[slot[@"end_at"] doubleValue]; }
    ag_req([s arrangeAt:day zone:@"UTC" error:nil],@"一千任务写入安排");
    NSDictionary *snapshot=[s planAt:day error:nil];ag_req([snapshot[@"alerts"] count]==1000,[NSString stringWithFormat:@"一千安排都进入原调度查询（实际%lu）",(unsigned long)[snapshot[@"alerts"] count]]);
    double elapsed=NSDate.timeIntervalSinceReferenceDate-started;
    ag_req(elapsed<3,@"一千任务计算持久化与调度查询在三秒内完成");printf("Agenda batch 1000: %.3fs\n",elapsed);
}

// 核对十版原任务迁移和失败后完整回滚。
static void ag_migrate(NSString *root) {
    for(NSNumber *fail in @[@NO,@YES]) {
        NSString *path=[root stringByAppendingPathComponent:[NSString stringWithFormat:@"migration-%@.db",fail]];__block NSString *id;
        @autoreleasepool { TaskStore *s=ag_store(path);id=[s crtTsk:@{@"title":@"迁移前原任务",@"notes":@"保留原备注"} error:nil][@"task_id"]; }
        sqlite3 *db=NULL;ag_req(sqlite3_open(path.UTF8String,&db)==SQLITE_OK,@"打开隔离迁移库");
        NSString *archive=[NSString stringWithContentsOfFile:@"Tests/Fixtures/archive-v12.sql" encoding:NSUTF8StringEncoding error:nil];
        ag_req(sqlite3_exec(db,archive.UTF8String,NULL,NULL,NULL)==SQLITE_OK,@"移除归档新版结构");
        NSString *fixture=[NSString stringWithContentsOfFile:@"Tests/Fixtures/agenda-v10.sql" encoding:NSUTF8StringEncoding error:nil];
        ag_req(sqlite3_exec(db,fixture.UTF8String,NULL,NULL,NULL)==SQLITE_OK,@"使用真实十版结构");
        if(fail.boolValue)ag_req(sqlite3_exec(db,"CREATE TRIGGER agenda_fail BEFORE UPDATE ON store_meta WHEN NEW.schema_version=11 BEGIN SELECT RAISE(ABORT,'test');END",NULL,NULL,NULL)==SQLITE_OK,@"注入迁移提交失败");
        sqlite3_close(db);TaskStore *s=[[TaskStore alloc]initAt:path error:nil];
        ag_req((s==nil)==fail.boolValue,@"迁移结果符合故障注入");
        if(fail.boolValue) {
            ag_req(sqlite3_open(path.UTF8String,&db)==SQLITE_OK,@"检查失败原库");sqlite3_stmt *query=NULL;
            ag_req(sqlite3_prepare_v2(db,"SELECT schema_version,(SELECT count(*) FROM pragma_table_info('tasks') WHERE name LIKE 'routine_%'),(SELECT count(*) FROM tasks) FROM store_meta",-1,&query,NULL)==SQLITE_OK && sqlite3_step(query)==SQLITE_ROW && sqlite3_column_int(query,0)==10 && sqlite3_column_int(query,1)==0 && sqlite3_column_int(query,2)==1,@"失败原子回滚版本和字段并保留原任务");
            sqlite3_finalize(query);ag_req(sqlite3_exec(db,"DROP TRIGGER agenda_fail",NULL,NULL,NULL)==SQLITE_OK,@"撤销隔离迁移故障");sqlite3_close(db);s=ag_store(path);
        }
        ag_req([s schver:nil]==TS_SCH_VER && [[s rdTsk:id error:nil][@"notes"] isEqual:@"保留原备注"] && [[s rdTsk:id error:nil][@"routine_kind"] isEqual:@"none"],@"原任务迁移后身份备注及语义不变");
    }
}

// 验证仅当天展示，02:00原子过期与时间回拨。
static void ag_expiry(NSString *path) {
    TaskStore *s=ag_store(path);
    NSCalendar *calendar=[NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];
    calendar.timeZone=NSTimeZone.localTimeZone;
    double day=[calendar startOfDayForDate:[NSDate dateWithTimeIntervalSince1970:ag_time(@"2026-11-04 12:00")]].timeIntervalSince1970,at=day+2*3600;
    NSDictionary *yesterday=[s crtTsk:@{@"title":@"昨日未做",@"due_at":@(day-600),@"planned_duration":@1200} error:nil];
    NSDictionary *untouched=[s crtTsk:@{@"title":@"昨日未呈现",@"deadline_at":@(day-3600)} error:nil];
    NSDictionary *today=[s crtTsk:@{@"title":@"今日待办",@"due_at":@(day+4*3600),@"planned_duration":@1200} error:nil];
    NSDictionary *tomorrow=[s crtTsk:@{@"title":@"明日待办",@"due_at":@(day+86400+3600)} error:nil];
    NSDictionary *repeat=ag_rtn(s,@"午夜常律",@"fixed",day-86400,30,YES);
    NSCalendar *utc=[NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];
    utc.timeZone=[NSTimeZone timeZoneForSecondsFromGMT:0];
    NSDate *start=[NSDate dateWithTimeIntervalSince1970:day-4*3600],*end=[start dateByAddingTimeInterval:3600];
    NSInteger minutes=[utc component:NSCalendarUnitHour fromDate:end]*60+[utc component:NSCalendarUnitMinute fromDate:end];
    ag_rtn(s,@"工作时段",@"work",start.timeIntervalSince1970,minutes,YES);
    NSDictionary *assigned=[s crtTsk:@{@"title":@"昨日已排程",@"planned_duration":@1200} error:nil];
    NSDictionary *plan=[s planAt:start.timeIntervalSince1970 error:nil];
    ag_req(ag_find(plan[@"slots"],assigned[@"task_id"])!=nil,@"昨日未定时任务已有独立安排");
    plan=[s planAt:day-600 error:nil];
    NSDictionary *active=[s claim:ag_find(plan[@"alerts"],yesterday[@"task_id"]) revision:[plan[@"revision"] longLongValue] at:day-600 error:nil];
    ag_req(active!=nil,@"认领昨日跨午夜轮次");
    NSArray *rows=[TaskToday rows:s at:day+60 zone:calendar.timeZone.name error:nil];
    ag_req(ag_find(rows,today[@"task_id"]) && !ag_find(rows,yesterday[@"task_id"]) && !ag_find(rows,untouched[@"task_id"]) && !ag_find(rows,tomorrow[@"task_id"]),@"午夜立即切日且仅今日待办可见");
    plan=[s planAt:at-1 error:nil];
    ag_req(ag_find(plan[@"alerts"],yesterday[@"task_id"]) && [plan[@"agenda_wake_at"] doubleValue]==at,@"01:59仍保留昨日轮次，02:00准时重读");
    plan=[s planAt:at error:nil];
    ag_req(!ag_find(plan[@"alerts"],yesterday[@"task_id"]) && !ag_find(plan[@"alerts"],untouched[@"task_id"])
        && !ag_find(plan[@"alerts"],assigned[@"task_id"]),@"02:00同时过期已呈现、未呈现及自动安排的轮次");
    NSDictionary *row=[s lsOcc:yesterday[@"task_id"] error:nil].firstObject;
    ag_req([row[@"action"] isEqual:@"expire"] && [row[@"status"] isEqual:@"resolved"] && [row[@"occurrence_id"] isEqual:active[@"occurrence_id"]],@"过期保留轮次身份和独立状态");
    ag_req([[s rdTsk:yesterday[@"task_id"] error:nil][@"status"] isEqual:@"needsAction"],@"过期不伪造完成");
    ag_req([ag_find(plan[@"alerts"],repeat[@"task_id"])[@"cycle_at"] doubleValue]==day,@"昨日未认领重复轮次过期，保留今天和未来");
    long long revision=[s revision:nil];[s planAt:at error:nil];
    ag_req([s revision:nil]==revision,@"重复刷新不重复写入");
    plan=[s planAt:day-300 error:nil];
    ag_req(!ag_find(plan[@"alerts"],yesterday[@"task_id"]) && [ag_find(plan[@"alerts"],repeat[@"task_id"])[@"cycle_at"] doubleValue]==day,@"回拨不恢复已过期轮次");
    ag_req([TaskStore nextExpiry:ag_time(@"2026-03-08 05:00") zone:@"America/New_York"]==ag_time(@"2026-03-08 07:00"),@"春季跳过02:00时使用第一个有效时刻");
}

// 验证今日律的位置按时刻推进，保留已逾期行。
static void ag_focus(void) {
    NSArray *rows=@[@{@"remind_at":@7,@"today_end":@8},@{@"remind_at":@18,@"today_end":@22},
        @{@"remind_at":@20,@"today_end":@21},@{@"remind_at":@23},@{@"remind_at":NSNull.null}];
    ag_req([TaskToday focus:rows at:6]==0,@"未开始时定位首项");
    ag_req([TaskToday focus:rows at:8]==1,@"结束时间到达后定位下一项");
    ag_req([TaskToday focus:rows at:20]==2,@"重叠时定位最新开始的当前阶段");
    ag_req([TaskToday focus:rows at:21]==1,@"短任务结束后定位仍在进行的阶段");
    ag_req([TaskToday focus:rows at:22]==3 && [TaskToday focus:rows at:24]==3,@"等待下一项或保留当天最后一项");
    ag_req([TaskToday focus:@[rows.lastObject] at:20]==NSNotFound && rows.count==5,@"未安排任务保持原位置，历史行未移除");
}

// 执行日程真实存储测试。
int main(void) { @autoreleasepool {
    [NSTimeZone setDefaultTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
    NSString *root=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];[NSFileManager.defaultManager createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:nil];
    ag_day([root stringByAppendingPathComponent:@"day.db"]);ag_repeat([root stringByAppendingPathComponent:@"repeat.db"]);ag_edges([root stringByAppendingPathComponent:@"edges.db"]);ag_import([root stringByAppendingPathComponent:@"import.db"]);ag_slots([root stringByAppendingPathComponent:@"slots.db"]);ag_batch([root stringByAppendingPathComponent:@"batch.db"]);ag_migrate(root);ag_expiry([root stringByAppendingPathComponent:@"expiry.db"]);ag_focus();
    [NSFileManager.defaultManager removeItemAtPath:root error:nil];printf("TaskAgenda: %d checks passed\n",checks);
}return 0; }
