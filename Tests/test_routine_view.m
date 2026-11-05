#import "LBHead.h"

static int checks;
// 累计常律展示断言。
static void rv_req(BOOL valid,NSString *message){if(!valid){NSLog(@"常律展示失败：%@",message);abort();}checks++;}
// 按明确时区解析测试日期。
static double rv_time(NSString *text,NSString *zone){NSDateFormatter *format=[NSDateFormatter new];format.locale=[[NSLocale alloc]initWithLocaleIdentifier:@"en_US_POSIX"];format.timeZone=[NSTimeZone timeZoneWithName:zone];format.dateFormat=@"yyyy-MM-dd HH:mm";return [format dateFromString:text].timeIntervalSince1970;}
// 从日模板生成分组输入。
static NSDictionary *rv_day(double day, NSUInteger count) {
    NSMutableArray *entries = [NSMutableArray array];
    for (NSUInteger index=0; index<count; index++) {
        NSDictionary *task = @{@"task_id":@(index),@"list_id":TS_RTN_LST,@"created_at":@2,@"remind_at":@3};
        [entries addObject:@{@"task":task,@"start_at":@(day+index*60),@"cycle_at":@(day+index*60)}];
    }
    return @{@"day_at":@(day),@"entries":entries};
}

// 验证空日、五项分组、跨日隔离和唯一时刻标签。
static void rv_group(void) {
    double day=rv_time(@"2026-11-03 00:00",@"UTC");
    for (NSNumber *count in @[@0,@1,@5,@6,@10,@11]) {
        NSArray *input=@[rv_day(day,count.unsignedIntegerValue),rv_day(day+86400,1)];
        NSArray *sections=[TaskRoutineView sections:input];
        rv_req(sections.count==2 && [sections[1][@"rows"] count]==2,@"日期独立，空日仍可继续浏览");
        NSArray *rows=sections[0][@"rows"];
        rv_req(rows.count==count.unsignedIntegerValue+(count.unsignedIntegerValue+4)/5,@"每五项一个分隔线");
        NSUInteger total=0;
        for (NSDictionary *row in rows) {
            rv_req([row[@"routine_fire_at"] doubleValue]==day+total*60,@"使用规则时刻而非提醒与创建时刻");
            if ([row[@"routine_marker"] boolValue]) rv_req(row.count==2,@"分隔线只标起始");
            else { rv_req([row[@"routine_group_first"] boolValue]==(total%5==0),@"首项时刻避免重复显示"); total++; }
        }
    }
}

// 验证范围读取、跨页无重复及常律脱离执行状态。
static void rv_store(NSString *path) {
    TaskStore *store=[[TaskStore alloc]initAt:path error:nil];rv_req(store!=nil,@"打开隔离数据库");
    double day=rv_time(@"2026-11-03 00:00",@"UTC"),start=day+9*3600;
    for (NSString *kind in @[@"fixed",@"work",@"rest"]) {
        NSError *error=nil;
        NSDictionary *task=[store crtTsk:@{@"title":kind,@"list_id":TS_RTN_LST,@"routine_kind":kind,@"routine_enabled":@1,@"routine_end":@600,@"due_at":@(start),@"recurrence_type":@"daily",@"timezone_id":@"UTC"} error:&error];
        rv_req(task!=nil,error.localizedDescription);
        if ([kind isEqual:@"fixed"]) rv_req([store cmplTsk:task[@"task_id"] error:nil],@"设置已处理模板夹具");
    }
    rv_req([store crtTsk:@{@"title":@"已停用",@"list_id":TS_RTN_LST,@"routine_kind":@"fixed",@"routine_enabled":@0,@"routine_end":@660,@"due_at":@(start+3600),@"recurrence_type":@"daily",@"timezone_id":@"UTC"} error:nil]!=nil,@"设置未启用夹具");
    [store crtTsk:@{@"title":@"普通任务",@"due_at":@(start),@"planned_duration":@600} error:nil];
    long long revision=[store revision:nil];
    NSArray *page=[store rtnDays:day-86400 count:7 zone:@"UTC" error:nil];
    rv_req(page.count==7 && [page[0][@"entries"] count]==0 && [page[1][@"entries"] count]==4,@"开始日前为空，普通任务不混入，已处理和草稿保留");
    rv_req([page[6][@"day_end"] isEqual:[store rtnDays:day+6*86400 count:7 zone:@"UTC" error:nil][0][@"day_at"]],@"相邻页无重叠和缺口");
    rv_req([[store rtnDays:day+60*86400 count:7 zone:@"UTC" error:nil][6][@"entries"] count]==4,@"远期只展开请求的七天");
    rv_req([store rtnDays:day count:29 zone:@"UTC" error:nil]==nil && [store rtnDays:day count:7 zone:@"Invalid/Zone" error:nil]==nil,@"拒绝超大和无效日期窗口");
    double dst=rv_time(@"2026-11-01 00:00",@"America/New_York");
    NSArray *fall=[store rtnDays:dst count:2 zone:@"America/New_York" error:nil];
    rv_req([fall[1][@"day_at"] doubleValue]-[fall[0][@"day_at"] doubleValue]==90000,@"按日历翻页保留25小时换日");
    rv_req([store revision:nil]==revision,@"浏览不写入任务、历史或修订号");
    NSDictionary *fixture=[store crtTsk:@{@"title":@"确认删除夹具",@"list_id":TS_RTN_LST,@"routine_kind":@"fixed",
        @"routine_enabled":@1,@"routine_end":@720,@"due_at":@(day+11*3600),@"recurrence_type":@"daily",@"timezone_id":@"UTC"} error:nil];
    rv_req(fixture && [[store rtnDays:day count:2 zone:@"UTC" error:nil][1][@"entries"] count]==5,@"同一模板跨日展示");
    rv_req([store delTsk:fixture[@"task_id"] error:nil],@"使用既有软删除提交常律");
    NSArray *remaining=[store rtnDays:day count:2 zone:@"UTC" error:nil];
    rv_req([remaining[0][@"entries"] count]==4 && [remaining[1][@"entries"] count]==4,@"仅删除指定模板的所有日期安排");
    for (NSDictionary *alert in [store planAt:day error:nil][@"alerts"])
        rv_req(![alert[@"task_id"] isEqual:fixture[@"task_id"]],@"被删模板的后续提醒不再排程");
}
// 执行常律只读投影测试。
int main(void){@autoreleasepool{NSString *root=[NSTemporaryDirectory()stringByAppendingPathComponent:NSUUID.UUID.UUIDString];[NSFileManager.defaultManager createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:nil];rv_group();rv_store([root stringByAppendingPathComponent:@"routine.sqlite3"]);[NSFileManager.defaultManager removeItemAtPath:root error:nil];printf("TaskRoutineView: %d checks passed\n",checks);}return 0;}
