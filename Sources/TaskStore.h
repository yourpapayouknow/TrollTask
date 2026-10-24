#pragma once

#define TS_DB_PATH @"/var/mobile/Library/Application Support/com.iwmei.taskforiwmei/tasks.sqlite3"
#define TS_DFLT_LST @"00000000-0000-4000-8000-000000000001"
#define TS_SCH_VER 8
#define TS_ATT_MAX 6
#define TS_DATA_NOTE "com.iwmei.taskforiwmei.data"
#define TS_CAPTURE_NOTE "com.iwmei.taskforiwmei.capture"

// 提供主App与HUD共用的SQLite数据模型。
@interface TaskStore : NSObject
@property(nonatomic, readonly, copy) NSString *path;
@property(nonatomic, readonly, copy) NSString *changeNote;
@property(nonatomic, readonly, strong) NSError *syncError;
// 打开当前进程的共享存储。
+ (instancetype)shrd:(NSError **)error;
// 在提交前复用存储层的标题与说明校验。
+ (BOOL)vldTxt:(NSString *)title notes:(NSString *)notes error:(NSError **)error;
// 统一校验图片及普通文件批次。
+ (BOOL)vldPrfs:(NSArray *)attachments error:(NSError **)error;
// 在指定绝对路径创建或迁移数据库。
- (instancetype)initAt:(NSString *)path error:(NSError **)error;
// 读取应用数据模型版本。
- (NSInteger)schver:(NSError **)error;
// 将多个存储操作作为同一事务提交。
- (BOOL)wrTxn:(BOOL (NS_NOESCAPE ^)(NSError **))work error:(NSError **)error;
// 创建稳定UUID的任务清单。
- (NSDictionary *)crtLst:(NSString *)title error:(NSError **)error;
// 修改清单名称。
- (BOOL)updLst:(NSString *)listID title:(NSString *)title error:(NSError **)error;
// 软删除非默认清单及其中全部任务。
- (BOOL)delLst:(NSString *)listID error:(NSError **)error;
// 清理指定清单中的已完成任务及其子树。
- (BOOL)clrCmpl:(NSString *)listID error:(NSError **)error;
// 读取全部清单。
- (NSArray *)lsLsts:(NSError **)error;
// 创建稳定UUID的任务。
- (NSDictionary *)crtTsk:(NSDictionary *)fields error:(NSError **)error;
// 导入指定UUID，冲突时拒绝覆盖。
- (NSDictionary *)crtTsk:(NSDictionary *)fields uuid:(NSString *)uuid error:(NSError **)error;
// 修改任务字段并保留原身份。
- (BOOL)updTsk:(NSString *)taskID fields:(NSDictionary *)fields error:(NSError **)error;
// 读取单个任务，缺失时返回错误。
- (NSDictionary *)rdTsk:(NSString *)taskID error:(NSError **)error;
// 读取包括软删除记录在内的任务。
- (NSArray *)lsTsks:(NSError **)error;
// 软删除指定任务及所有后代。
- (BOOL)delTsk:(NSString *)taskID error:(NSError **)error;
// 完成指定任务并停止该任务的整个提醒系列。
- (BOOL)cmplTsk:(NSString *)taskID error:(NSError **)error;
// 完成当前重复轮次并保留后续系列。
- (BOOL)cmplNxt:(NSString *)taskID error:(NSError **)error;
// 按展示的轮次和版本完成，过时意图不推进下一轮。
- (BOOL)cmplNxt:(NSString *)taskID cycle:(NSNumber *)cycle generation:(NSNumber *)generation error:(NSError **)error;
// 恢复已完成任务并重新建立提醒计划。
- (BOOL)rstrTsk:(NSString *)taskID error:(NSError **)error;
// 按实际下一次提醒时间读取所有未完成且未删除任务。
- (NSArray *)lsPnd:(NSError **)error;
// 独立读取未删除的已完成任务。
- (NSArray *)lsCmpl:(NSError **)error;
// 读取持久化数据修订号。
- (long long)revision:(NSError **)error;
// 取得同一数据库快照中的任务和提醒处理记录。
- (NSDictionary *)snapshot:(NSError **)error;
// 从同一快照建立实际提醒时间升序的计划。
- (NSDictionary *)planAt:(NSTimeInterval)stamp error:(NSError **)error;
// 在核对最新修订号与任务版本后认领到期提醒。
- (NSDictionary *)claim:(NSDictionary *)alert revision:(long long)revision at:(NSTimeInterval)stamp error:(NSError **)error;
// 原子处理当前提醒，延后不修改原截止日期。
- (BOOL)actOcc:(NSString *)occID action:(NSString *)action until:(NSNumber *)until error:(NSError **)error;
// 收起当前轮次并持久化截图或唯一五分钟延期。
- (NSDictionary *)hldOcc:(NSString *)occID mode:(NSString *)mode error:(NSError **)error;
// 主动展开尚未处理的边栏提醒。
- (BOOL)rsmOcc:(NSString *)occID error:(NSError **)error;
// 原子保存有效图片与当前轮次的完成记录。
- (BOOL)chkOcc:(NSString *)occID method:(NSString *)method image:(NSData *)image error:(NSError **)error;
// 校验并原子提交最多六个附件，全部成功后完成提醒。
- (BOOL)chkOcc:(NSString *)occID attachments:(NSArray<NSDictionary *> *)attachments error:(NSError **)error;
// 按附件序号读取同库证据，元数据读取不加载图片。
- (NSArray<NSDictionary *> *)lsChk:(NSString *)occID images:(BOOL)images error:(NSError **)error;
// 读取本次打卡元数据或完整图片。
- (NSDictionary *)rdChk:(NSString *)occID image:(BOOL)image error:(NSError **)error;
// 在同库建立唯一的短期前台采集请求。
- (NSDictionary *)reqCap:(NSString *)occID source:(NSString *)source limit:(NSInteger)limit error:(NSError **)error;
// 读取指定或当前采集请求及已返回的图片。
- (NSDictionary *)rdCap:(NSString *)token error:(NSError **)error;
// 由前台采集进程认领请求。
- (BOOL)ackCap:(NSString *)token error:(NSError **)error;
// 原子交回选图结果，空批次表示取消，不完成待办。
- (BOOL)finCap:(NSString *)token attachments:(NSArray *)attachments issue:(NSString *)issue error:(NSError **)error;
// 清理指定或全部短期采集记录。
- (BOOL)delCap:(NSString *)token error:(NSError **)error;
// 幂等记录某任务某个计划时刻的一次提醒。
- (NSDictionary *)crtOcc:(NSString *)taskID at:(NSNumber *)stamp error:(NSError **)error;
// 更新单次提醒的触发及处理记录。
- (BOOL)updOcc:(NSString *)occID fields:(NSDictionary *)fields error:(NSError **)error;
// 读取某个任务的提醒记录。
- (NSArray *)lsOcc:(NSString *)taskID error:(NSError **)error;
@end

// 解析命令行参数并调用存储模块。
int ts_cli(int argc, char *argv[], NSString *path);
// 统一检查有限数值，布尔值不能作为时间或分档。
BOOL ts_num(id value);
