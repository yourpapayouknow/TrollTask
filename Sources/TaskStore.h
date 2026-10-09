#pragma once

#define TS_DB_PATH @"/var/mobile/Library/Application Support/com.iwmei.taskforiwmei/tasks.sqlite3"
#define TS_DFLT_LST @"00000000-0000-4000-8000-000000000001"
#define TS_SCH_VER 2

// 提供主App与HUD共用的SQLite数据模型。
@interface TaskStore : NSObject
@property(nonatomic, readonly, copy) NSString *path;
// 打开当前进程的共享存储。
+ (instancetype)shrd:(NSError **)error;
// 在指定绝对路径创建或迁移数据库。
- (instancetype)initAt:(NSString *)path error:(NSError **)error;
// 读取应用数据模型版本。
- (NSInteger)schver:(NSError **)error;
// 将多个存储操作作为同一事务提交。
- (BOOL)wrTxn:(BOOL (^)(NSError **))work error:(NSError **)error;
// 创建稳定UUID的任务清单。
- (NSDictionary *)crtLst:(NSString *)title error:(NSError **)error;
// 修改清单名称。
- (BOOL)updLst:(NSString *)listID title:(NSString *)title error:(NSError **)error;
// 读取全部清单。
- (NSArray *)lsLsts:(NSError **)error;
// 创建稳定UUID的任务。
- (NSDictionary *)crtTsk:(NSDictionary *)fields error:(NSError **)error;
// 修改任务字段并保留原身份。
- (BOOL)updTsk:(NSString *)taskID fields:(NSDictionary *)fields error:(NSError **)error;
// 读取单个任务，缺失时返回错误。
- (NSDictionary *)rdTsk:(NSString *)taskID error:(NSError **)error;
// 读取包括软删除记录在内的任务。
- (NSArray *)lsTsks:(NSError **)error;
// 幂等记录某任务某个计划时刻的一次提醒。
- (NSDictionary *)crtOcc:(NSString *)taskID at:(NSNumber *)stamp error:(NSError **)error;
// 更新单次提醒的触发及处理记录。
- (BOOL)updOcc:(NSString *)occID fields:(NSDictionary *)fields error:(NSError **)error;
// 读取某个任务的提醒记录。
- (NSArray *)lsOcc:(NSString *)taskID error:(NSError **)error;
@end

// 解析命令行参数并调用存储模块。
int ts_cli(int argc, char *argv[], NSString *path);
