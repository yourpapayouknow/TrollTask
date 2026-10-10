# 原生重复规则依赖

libical4.0.6，官方标签v4.0.6，提交9cfca65c122fa23b9680a28e0c9225a2fd015fc5。
来源https://github.com/libical/libical；选择MPL-2.0许可，保留上游每文件版权及双许可标记。

仅接入libical的C核心源文件，不引入GLib、Java、C++、BerkeleyDB或ICU。派生表/头文件由上游CMake/Perl生成，Darwin配置取自本机官方CMake检测；工程直接以系统Clang构建宿主与arm64静态库，安装包不依赖CMake或动态libical。

时区数据取当前系统Foundation的NSTimeZone.data，提供给libical原生TZif读取器；不使用上游可能过时的内置时区文件。规则计算用同一原生实现。第三方原始函数命名与注释保留。

针对Tests/test_sync.m直接复现的边界，仅修改icalrecur.c两处：逆向范围对UNTIL增加非空判断，避免无限重复错误地从空日期回溯；原生候选约束增加TZif绝对时间往返检查，排除夏令时跳变中不存在的当地时刻，且不计入COUNT/BYSETPOS。未重写上游解析或日期展开算法。

安装包ThirdParty/NOTICE.md提供来源说明，ThirdParty/libical-source.zip包含全部实际使用及修改后的C源码、生成头文件和原始LICENSES。可直接解压tipa取得对应源代码，不依赖单独下载。MPL-2.0适用于上游及上述原生文件修改，其他文件依其原有许可。

范围为GoogleCalendar采用的公历RFC5545规则；未启用ICU的非公历RFC7529。64位上游迭代年份上限2582，超出范围的重复起点会返回字段错误，不宣称无限年份支持。

一次性生成过程中CMake的Unix Makefiles强制MAKEFLAGS=SHELL=/bin/zsh，make命令显式SHELL=/bin/zsh，没有执行旧Shell。
