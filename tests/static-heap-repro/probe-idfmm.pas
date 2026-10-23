program probe_idfmm;

{$mode objfpc}{$H+}

{ Proves the FPC memory manager can be hot-routed to the IDF heap API
  (heap_caps_*), bypassing the freertos heapmgr static block.
  Sequence:
   1. GetMem from the DEFAULT manager (heapmgr static -Ch block), print
      address (expect ~0x3FC9Cxxx = __fpc_initialheap BSS region);
   2. install a heap_caps_-backed TMemoryManager;
   3. GetMem again via GetMem (expect a DIFFERENT region: the IDF
      internal-DRAM pool), verify MemSize;
   4. drive TStringList + ansistrings + a growing dynarray on the new
      manager (ReAllocMem cycles through heap_caps_realloc);
   5. exit teardown runs CLEAN by delegating: FreeMem/MemSize/ReAllocMem
      route pointers that live inside the __fpc_initialheap static block
      (allocated by the heapmgr manager BEFORE the swap) back to the
      captured static manager - finalization of unit-init objects like
      classes' TThreadList crosses the swap and must be freed by the
      manager that allocated them. New allocations all land in the IDF
      pool. For production: an idfheap unit placed FIRST in uses installs
      the manager before ANY other unit allocates, then no cross-manager
      blocks can exist at all (no delegation needed). }

uses classes, sysutils;

const
  MALLOC_CAP_8BIT    = 1 shl 2;   { esp_heap_caps.h, IDF 5.2.8 }
  MALLOC_CAP_DEFAULT = 1 shl 12;
  CAPS = MALLOC_CAP_8BIT or MALLOC_CAP_DEFAULT;

var
  initialheap: record end; external name '__fpc_initialheap';
  heapsize: ptruint; external name '__heapsize';
  StaticMgr: TMemoryManager;

function InStaticHeap(p: pointer): boolean;
  begin
    result := (ptruint(p) >= ptruint(@initialheap)) and
              (ptruint(p) < ptruint(@initialheap) + heapsize);
  end;

function  heap_caps_malloc(size, caps: ptruint): pointer; external name 'heap_caps_malloc';
procedure heap_caps_free(p: pointer); external name 'heap_caps_free';
function  heap_caps_realloc(p: pointer; size, caps: ptruint): pointer; external name 'heap_caps_realloc';
function  heap_caps_get_allocated_size(p: pointer): ptruint; external name 'heap_caps_get_allocated_size';

function IDFGetMem(size: ptruint): pointer;
  begin
    result := heap_caps_malloc(size, CAPS);
    if result = nil then
      RunError(203);
  end;

function IDFFreeMem(p: pointer): ptruint;
  begin
    if p = nil then
      result := 0
    else if InStaticHeap(p) then
      { pre-swap block: free with the manager that allocated it }
      result := StaticMgr.FreeMem(p)
    else
      begin
        heap_caps_free(p);
        result := 0;
      end;
  end;

function IDFFreeMemSize(p: pointer; size: ptruint): ptruint;
  begin
    if InStaticHeap(p) then
      result := StaticMgr.FreeMemSize(p, size)
    else
      begin
        result := heap_caps_get_allocated_size(p);
        heap_caps_free(p);
      end;
  end;

function IDFAllocMem(size: ptruint): pointer;
  begin
    result := heap_caps_malloc(size, CAPS);
    if result <> nil then
      fillchar(result^, size, 0);
  end;

function IDFReAlloc(var p: pointer; Size: ptruint): pointer;
  begin
    { mirror SysReAllocMem: the manager must write p in place - callers like
      TFPList.SetCapacity pass FList by reference and expect the update }
    if p = nil then
      begin
        result := heap_caps_malloc(Size, CAPS);
        if result = nil then
          if not ReturnNilIfGrowHeapFails then
            RunError(203);
        p := result;
      end
    else if InStaticHeap(p) then
      begin
        { static-block pointer: the owning manager must handle the free,
          even when Size = 0 (SetCapacity(0) reaches us with static FList) }
        result := StaticMgr.ReAllocMem(p, Size)
      end
    else if Size = 0 then
      begin
        heap_caps_free(p);
        p := nil;
        result := nil;
      end
    else
      begin
        result := heap_caps_realloc(p, Size, CAPS);
        if result = nil then
          if not ReturnNilIfGrowHeapFails then
            RunError(203);
        p := result;
      end;
  end;

function IDFMemSize(p: pointer): ptruint;
  begin
    if InStaticHeap(p) then
      result := StaticMgr.MemSize(p)
    else
      result := heap_caps_get_allocated_size(p);
  end;

var
  mgr: TMemoryManager;
  pStatic, pIdf: pointer;
  lst: TStringList;
  big: array of longint;
  i: smallint;
  s: SizeInt;
begin
  { 1. default manager (static block) }
  pStatic := GetMem(4096);

  { 2. install the IDF-backed manager; save the static one for delegation }
  GetMemoryManager(mgr);
  StaticMgr := mgr;
  mgr.GetMem := @IDFGetMem;
  mgr.FreeMem := @IDFFreeMem;
  mgr.FreeMemSize := @IDFFreeMemSize;
  mgr.AllocMem := @IDFAllocMem;
  mgr.ReAllocMem := @IDFReAlloc;
  mgr.MemSize := @IDFMemSize;
  SetMemoryManager(mgr);

  { 3. routed allocation + header size }
  pIdf := GetMem(4096);
  writeln('alloc @', hexstr(ptruint(pStatic), 8), ' static block');
  writeln('alloc @', hexstr(ptruint(pIdf), 8), ' IDF pool; MemSize=', IDFMemSize(pIdf));

  { 4. classes + strings workload on the new manager }
  lst := TStringList.Create;
  for i := 1 to 100 do
    lst.Add('value' + IntToStr(1000 + i));
  lst.Sort;
  s := Length(lst[99]);
  writeln('TStringList 100 items sorted; last length ', s);

  { dynamic array with real grow-through-ReAllocMem cycles }
  for i := 0 to 99 do
    begin
      SetLength(big, (i + 1) * 500);
      big[i] := i * i;
    end;
  writeln('dynarray 100 x 500 slots ok, big[99]=', big[99]);
  SetLength(big, 0);

  { 5. free IDF-routed allocations; pStatic stays live and is freed by the
      static manager at its own teardown, plus FreeMem of it now would
      delegate (demonstrate both): }
  lst.Free;
  FreeMem(pIdf);
  FreeMem(pStatic);   { exercises the delegation path back to heapmgr }

  writeln('idf-routed memory manager OK');
end.
