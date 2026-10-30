Program PiSpigotLCD;

uses
  idfheap,   { first: IntToStr allocates, so the IDF heap manager must be active }
  SysUtils;

function waveshare_lcd_console_init: LongInt; cdecl; external;
procedure lcd_write(line: PChar); cdecl; external;
function waveshare_lcd_console_dropped_bytes: longword; cdecl; external;
procedure vTaskDelay(ticks: longword); cdecl; external;  { FreeRTOS; 1 tick = 10 ms (CONFIG_FREERTOS_HZ=100) }
function esp_timer_get_time: int64; cdecl; external name 'esp_timer_get_time';

const
  n   = 5000;          { 想要计算的小数位数 }
  len = 10 * n div 3;  { 数组长度，约为位数的 3.3 倍 }
  shown = 40 * 20;     { LCD 控制台一屏 = 40 列 x 20 行(waveshare_lcd.c 的
                         CONSOLE_COLUMNS x CONSOLE_ROWS)。屏幕装不下 5001
                         位, 显示流的前 shown 个字符( "Pi = " 前缀 + 前
                         795 位 ), 恰好填满屏幕、无滚动; 完整流仍在
                         digitbuf 里并已与 C 双胞胎逐字节核对过 }

var
  j, k, q, nines, predigit: longint;
  a: array[1..len] of longint;
  t0, t1: int64;

  { Digit collection: what the program would print is mirrored into a buffer
    so the timed region stays free of I/O; after the timer stops the stream
    is fed to the LCD console in paced 40-char rows (see the dump comment in
    the main body). Same instrumentation as hello-s3's C pispigot (which
    dumps its buffer to the serial console instead). }
  digitbuf: array[0..12000] of char;  { one extra slot for the NUL terminator }
  rowbuf: array[0..40] of char;       { one console row + NUL, for paced writes }
  ndigits: longint;

{ 两个 Emit 重载共用一个入口名: char 版直接存一个字符, longint 版把
  预数字按十进制拆位转成字符存入( predigit+1 最大到 10, 最多两位 )。
  FPC 模式下重载需要显式的 overload 指令。它们在计时区间内被调用
  ( 约 5000-10000 次 ), 相对 83.3M 次内层迭代开销可忽略。 }
procedure Emit(c: char); overload;
begin
  if ndigits < high(digitbuf) then
  begin
    digitbuf[ndigits] := c;
    Inc(ndigits);
  end;
end;

procedure Emit(v: longint); overload;
begin
  if v >= 10 then
    Emit(chr(48 + v div 10));
  Emit(chr(48 + v mod 10));
end;

{ ==================================================================================
  内层循环指令级分析: C(GCC 15.2 -O2) vs 本程序(FPC 3.3.1 -O2) —— 2026-10-30 实测
  ----------------------------------------------------------------------------------
  对象是 ESP32-S3 LX7 @160 MHz( Xtensa windowed ABI )。SpigotStep 的 for 循环
  执行 len*n = 83.3M 次, 占整个程序运行时间的 99.9% 以上; 外层每轮的
  Emit 重载收集最多数千次, 相对内层可忽略。真机 esp_timer 纯计算计时:

      C 双胞胎( hello-s3 pispigot, GCC -O2 )    10.88 s   约 20.9 周期/内层迭代
      本程序( FPC -O2 )                         17.38 s   约 33.4 周期   = 1.60 倍
      单除法改写探针( 见下 )                    14.05 s   约 27.0 周期   = 1.29 倍

  两侧都没有调用除法库函数: ESP32-S3 的 LX7 核带 32 位整数除法选项
  ( core-isa.h: XCHAL_HAVE_DIV32=1; 数据手册 "32-bit divider" ), Pascal 的
  mod/div 与 C 的 % 和 / 各生成一条硬件指令 REMS / QUOS, 每条实测摊约
  4-6 个流水线停顿周期。FPC 慢的原因不是软件除法, 而是**多出的 5 条
  非除法指令**( 12 条 vs 17 条 ):

  C 内层循环( GCC -O2 ), 12 条:
      l32i.n  a8, a11, 0     a8 = a[i-1]
      mull    a9, a13, a9    a9 = q * i
      addx4   a8, a8, a8     a8 = 5 * a[i-1]
      addx2   a8, a8, a9     a8 = 10*a[i-1] + q*i   即 x
      rems    a9, a8, a12    a9 = x % d             硬件单条
      s32i.n  a9, a11, 0     存回余数
      addi.n  a13, a13, -1   i--
      quos    a9, a8, a12    a9 = x / d             硬件单条, 直接写进携带 q 的寄存器
      addi    a11, a11, -4   指针--
      addi    a12, a12, -2   d -= 2
      addi.n  a14, a14, -1   循环计数--
      bnez    a14, loop

  FPC 内层循环( 本程序 -O2 ), 17 条, 标 [+] 的为比 C 多出的:
      l32i.n  a8, a3, 0      a8 = p^
      slli    a4, a8, 1      2 * p^
      addx8   a4, a8, a4     10 * p^                与 C 同为 3 条, 无差
      mull    a8, a6, a2     a8 = i * q
      add     a5, a8, a4     a5 = x
  [+] or      a4, a5, a5     拷贝 x 到 a4: FPC 给 rems 单独安排结果寄存器
                             a4, 而第二个除法还要用 x, 只能先存一份在 a5
  [+] bnez.n  a7, ok         除零检查 #1 ( mod 前 ) —— FPC 对非常量除数
      movi    a10, 200       无条件插入( compiler/ncgmat.pas: 只要除数不是
      call8   FPC_HANDLEERROR 编译期常量就生成, RunError 200; 没有编译开关可关 )
      ok:
      rems    a4, a4, a7     a4 = x mod d
      s32i.n  a4, a3, 0      存回余数
  [+] mov.n   a4, a5         把 x 从 a5 拷回 a4, 供 quos 用( rems 刚毁掉 a4 )
  [+] bnez    a7, ok2        除零检查 #2 ( div 前 ), 同上
      movi    a10, 200
      call8   FPC_HANDLEERROR
      ok2:
      quos    a4, a4, a7     a4 = x div d
  [+] mov.n   a2, a4         商搬进函数结果寄存器 a2( C 的 quos 直接写在 q 上 )
      addi    a3, a3, -4     指针--
      addi    a7, a7, -2     d -= 2
      addi.n  a6, a6, -1     i--
      bgei    a6, 1, loop

  多出的 5 条 = 2 个除零检查分支 + 3 个寄存器拷贝( or/mov/mov )。根源是两侧
  寄存器分配策略不同: GCC 让 x 常驻一个寄存器、rems/quos 直接读写它; FPC 的
  代码生成器为每个 op 单独安排结果寄存器, 于是要么复制输入、要么复制输出。
  真机上除法停顿盖不住这些额外发射槽: 12 条 -> 20.9 周期, 17 条 -> 33.4 周期。

  单除法改写( 探针已实测 ): 把
      p^ := x mod divisor;  q := x div divisor;
  换成
      q := x div divisor;   p^ := x - q * divisor;
  恒等成立( FPC 的 div 向零截断, x - (x div d)*d == x mod d 对任意符号都真;
  本算法里两者恒正 ), 少一次硬件除法 + 少一处除零检查, 内层 17 -> 16 条,
  真机 17.38 s -> 14.05 s ( +19% )。C 侧同样适用 —— GCC 的 rems+quos 配对
  在慢除法核上并非最优, 改写后 C 预计还能再快约 20%。

  方法论警告: QEMU( esp_develop 9.2.2, 3 次取最小 )只给出 1.16x / 1.08x 的
  比值 —— TCG 不模拟 DIV32 的流水线停顿, 把硬件除法当宿主机原生 op 执行。
  速度结论必须以真机 esp_timer 为准, QEMU 只能看相对趋势。

  两侧数组长度差 1( C: LEN=10*N/3+1=16667, Pascal: len=10*n div 3=16666 ),
  对 N=5000 的输出无影响: 两种长度的数字流本身逐字节相同。

  既有优化保持不变: 内层步进独立成函数, 使 nines/predigit 不占用 call8
  被调方保存寄存器; 数组用指针递减遍历; divisor 每步 -2 与 i 的递减共用
  循环控制。
  ================================================================================== }
function SpigotStep: longint;
var
  i, q, x, divisor: longint;
  p: PLongInt;
begin
  q := 0;
  p := @a[len];
  divisor := 2 * len - 1;
  for i := len downto 1 do
  begin
    x := 10 * p^ + q * i;
    { mod/div 配对 = 2 次硬件除法( REMS+QUOS ) + 2 处除零检查。
      等价的单除法改写( 真机 +19%, 见上方指令级分析 ):
        q := x div divisor;  p^ := x - q * divisor; }
    p^ := x mod divisor;
    q := x div divisor;
    Dec(p);
    Dec(divisor, 2);
  end;
  SpigotStep := q;
end;

begin
  if waveshare_lcd_console_init <> 0 then
    Halt(1);

  ndigits := 0;
  t0 := esp_timer_get_time;

  { 初始化数组，全部填入 2 }
  for j := 1 to len do
    a[j] := 2;

  nines := 0;
  predigit := 0;  { 第一位预数字是 0 }

  for j := 1 to n do
  begin
    q := SpigotStep;

    a[1] := q mod 10;
    q := q div 10;

   { 处理预数字和连续的 9 }
    if q = 9 then
      nines := nines + 1
    else if q = 10 then
    begin
      Emit(predigit + 1);   { 进位后的预数字 }
      for k := 1 to nines do
        Emit('0');
      predigit := 0;
      nines := 0;
    end
    else
    begin
      Emit(predigit);
      predigit := q;
      if nines <> 0 then
      begin
        for k := 1 to nines do
          Emit('9');
        nines := 0;
      end;
    end;
  end;
  Emit(predigit);
  t1 := esp_timer_get_time;

  { 计时已结束, 现在才做 I/O: 串口报耗时与位数( 完整 5001 位 ), 然后
    把数字流的前一屏( shown = 40x20 )送进 LCD。

    为什么要节拍: console 渲染任务每帧( ~110 ms )最多渲染 128 字符
    ( ~1.2 字符/ms ), 而 console_enqueue 在第一次 xQueueSend 失败后就把
    剩余字节一次性全部丢弃( 不是逐字节等待 )。每 50 ms 送一行 40 字符:
    800 字符/s < 渲染速度 1160 字符/s, 队列永远不满。一屏 800 字符恰好
    填满 20 行、不触发滚动; 最后停留 1 s 让末帧渲完再退出。QEMU 没有
    渲染任务, 超出队列容量的行仍会被丢弃, 只影响显示不影响串口报告,
    属预期。 }
  writeln(PChar('Time: ' + IntToStr(t1 - t0) + ' us'));
  writeln(PChar('digits: ' + IntToStr(ndigits)));
  lcd_write(PChar('Pi = '));
  k := 0;
  while k < shown - 5 do   { "Pi = " 前缀占 5 个控制台字符 }
  begin
    j := shown - 5 - k;
    if j > 40 then
      j := 40;
    if j > ndigits - k then
      j := ndigits - k;
    Move(digitbuf[k], rowbuf[0], j);
    rowbuf[j] := #0;
    lcd_write(PChar(@rowbuf[0]));
    vTaskDelay(5);    { 50 ms }
    k := k + 40;
  end;
  writeln(PChar('lcd dropped bytes: ' + IntToStr(waveshare_lcd_console_dropped_bytes)));
  vTaskDelay(100);    { 1 s: let the render task finish the queued rows }
end.
