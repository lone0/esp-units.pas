{ upstream provenance: FPCSource-esp-idf tests/webtbs/tw40838.pp }
{ uses adapted: upstream picks cthreads/athreads per platform via $if; this
  tree gets idfheap + fthreads (the BeginThread stack-size 0 is kept as
  upstream - it exercises the manager's default-stack handling) }
{ %TARGET=win32,win64,wince,linux,freebsd,netbsd,openbsd,darwin,amiga,morphos,aros }
program tw40838;

{$mode objfpc} {$modeswitch anonymousfunctions}

uses
  idfheap,
  fthreads;

var
	oldmm, newmm: TMemoryManager;
	th: TThreadID;
        initcalled, donecalled: Boolean;
begin
	GetMemoryManager(oldmm);
	newmm := oldmm;
	newmm.InitThread := procedure begin initcalled := True; {writeln('InitThread called');} if Assigned(oldmm.InitThread) then oldmm.InitThread; end;
	newmm.DoneThread := procedure begin donecalled := True; {writeln('DoneThread called');} if Assigned(oldmm.DoneThread) then oldmm.DoneThread; end;
	newmm.RelocateHeap := procedure begin writeln('RelocateHeap called'); if Assigned(oldmm.RelocateHeap) then oldmm.RelocateHeap; end;
	SetMemoryManager(newmm);

	th := BeginThread(
		function(param: pointer): PtrInt
		begin
			freemem(getmem(0));
			result := 0;
		end);
	WaitForThreadTerminate(th, 0);
	CloseThread(th);

        if not initcalled then
        	Halt(1);
        if not donecalled then
                Halt(2);
end.
