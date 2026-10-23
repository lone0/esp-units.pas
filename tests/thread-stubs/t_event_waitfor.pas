program t_event_waitfor; {$mode objfpc}{$H+}
{ Expected: TEvent.Create fails LOUD - SyncObjs raises ESyncObjectException
  because the RTL's BasicEventCreate benign-stub returns nil. }
uses idfheap, sysutils, syncobjs;
var E: TEvent;
begin
  try
    E := TEvent.Create(nil, true, false, 'demo');
    writeln('TEvent created (NOT EXPECTED)');
    E.WaitFor;
  except
    on e: Exception do
      writeln('thread use blocked, as designed: ', e.ClassName, ': ', e.Message);
  end;
end.
