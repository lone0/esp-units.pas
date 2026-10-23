program t_thread_create; {$mode objfpc}{$H+}
{ Expected: TDemoThread.Create fails LOUD - rtl/freertos/tthread.inc's
  SysCreate raises "freertos: TThread is a stub...". }
uses idfheap, sysutils, classes;
type
  TDemoThread = class(TThread)
  public
    constructor Create;
  end;

constructor TDemoThread.Create;
begin
  inherited Create(false);
end;

begin
  try
    TDemoThread.Create;
    writeln('thread created (NOT EXPECTED)');
  except
    on e: Exception do
      writeln('thread use blocked, as designed: ', e.ClassName, ': ', e.Message);
  end;
end.
