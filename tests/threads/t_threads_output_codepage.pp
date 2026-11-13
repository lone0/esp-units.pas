{ upstream provenance: FPCSource-esp-idf tests/webtbs/tw34163.pp }
{ PLANNED FAILURE (subsystem not implemented): the freertos RTL never
  initializes per-thread stdio (FPC_HAS_FEATURE_CONSOLEIO off in
  rtl/freertos/system.cfg, so InitThread skips SysInitStdio) and consoleio's
  OpenIO does not assign CodePage - the worker reads 771 ($0303, the TLS
  FillByte(3) residue) instead of DefaultSystemCodePage. }
program tw34163;

{$mode objfpc}

uses
  idfheap,
  fthreads,
{$ifdef windows}
  Windows,
{$endif windows}
  SysUtils;

var
  lCodePage: TSystemCodePage;

function ThreadFunc(aParam: pointer): ptrint;

begin
  lCodePage:=TextRec(Output).CodePage;
  ThreadFunc:=0;
end;


{$ifdef windows}
{ Thread entry for CreateThread, initialized by the RTL TLS callback }
function WinThreadFunc(aParam: pointer): DWORD; stdcall;

begin
  lCodePage:=TextRec(Output).CodePage;
  WinThreadFunc:=0;
end;
{$endif windows}


{ Fails when lCodePage, set by a thread started without GetStandardCodePageProc, is not DefaultSystemCodePage }
procedure Check(const aMsg: shortstring);

begin
  if lCodePage<>DefaultSystemCodePage then
    begin
      writeln(aMsg, ' must use DefaultSystemCodePage for Output, got ', lCodePage);
      halt(1);
    end;
end;


var
  lOld, lNew: TUnicodeStringManager;
  lThread: TThreadID;
{$ifdef windows}
  lHandle: THandle;
  lWinID: DWORD;
{$endif windows}

begin
  GetUnicodeStringManager(lOld);
  lNew:=lOld;
  lNew.GetStandardCodePageProc:=nil;
  SetUnicodeStringManager(lNew);

  lCodePage:=0;
  lThread:=BeginThread(@ThreadFunc,nil);
  WaitForThreadTerminate(lThread,0);
  CloseThread(lThread);
  SetUnicodeStringManager(lOld);
  Check('BeginThread');

{$ifdef windows}
  SetUnicodeStringManager(lNew);
  lCodePage:=0;
  lHandle:=CreateThread(nil,0,@WinThreadFunc,nil,0,lWinID);
  WaitForSingleObject(lHandle,INFINITE);
  CloseHandle(lHandle);
  SetUnicodeStringManager(lOld);
  Check('CreateThread');
{$endif windows}
  writeln('ok');
end.
