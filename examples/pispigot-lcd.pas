Program PiSpigotLCD;

uses
  idfheap,   { first: IntToStr allocates, so the IDF heap manager must be active }
  SysUtils;

function waveshare_lcd_console_init: LongInt; cdecl; external;
procedure lcd_write(line: PChar); cdecl; external;
function esp_timer_get_time: int64; cdecl; external name 'esp_timer_get_time';

const
  n   = 5000;          { 想要计算的小数位数 }
  len = 10 * n div 3;  { 数组长度，约为位数的 3.3 倍 }

var
  i, j, k, q, x, nines, predigit: longint;
  a: array[1..len] of longint;
  t0, t1: int64;

begin
  if waveshare_lcd_console_init <> 0 then
    Halt(1);

  t0 := esp_timer_get_time;

  { 初始化数组，全部填入 2 }
  for j := 1 to len do
    a[j] := 2;

  nines := 0;
  predigit := 0;  { 第一位预数字是 0 }

  {lcd_write(PChar('Pi = '));}

  for j := 1 to n do
  begin
    q := 0;

    { 从右向左进行核心计算 }
    for i := len downto 1 do
    begin
      x := 10 * a[i] + q * i;
      a[i] := x mod (2 * i - 1);
      q := x div (2 * i - 1);
    end;

    a[1] := q mod 10;
    q := q div 10;

   { 处理预数字和连续的 9 }
    if q = 9 then
      nines := nines + 1
    else if q = 10 then
    begin
      {lcd_write(PChar(IntToStr(predigit + 1)));}
      for k := 1 to nines do
        {lcd_write(PChar('0'));  { 输出被“进位”影响的零 }}
        ;
      predigit := 0;
      nines := 0;
    end
    else
    begin
      {lcd_write(PChar(IntToStr(predigit)));}
      predigit := q;
      if nines <> 0 then
      begin
        for k := 1 to nines do
          {lcd_write(PChar('9'));}
          ;
        nines := 0;
      end;
    end;
  end;
  {lcd_write(PChar(IntToStr(predigit)));}
  t1 := esp_timer_get_time;
  write(PChar(''));
  writeln(PChar('Time: ' + IntToStr(t1 - t0) + ' us'));
end.
