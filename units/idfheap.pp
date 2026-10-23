unit idfheap;

{$mode objfpc}{$H+}

{ Installs an IDF heap_caps_*-backed TMemoryManager at unit initialization -
  the production form of the manager routing demonstrated by probe-idfmm.

  USAGE: put this unit FIRST in the program's uses clause:

      program myapp;
      uses
        idfheap,        { MUST be first }
        classes, sysutils, ...;

  Then every allocation from the very first unit initialization onward
  (sysutils' format settings / exceptions, classes' TEncoding singletons and
  TThreadList, ansistrings, dynamic arrays, the program's own GetMem) comes
  from IDF's MALLOC_CAP_8BIT|MALLOC_CAP_DEFAULT pools - internal SRAM first,
  SPIRAM as overflow when CONFIG_SPIRAM_USE_MALLOC is enabled. No RTL,
  compiler or fpc.cfg changes; opting out is just removing the uses entry.

  Why this unit also USES heapmgr (order, not symbols - see the comment
  there): FPC initializes used units before their users. Without the
  reference, heapmgr would only be reached via sysutils' own uses list,
  which is initialized AFTER this unit when it is listed first - and
  heapmgr's initialization calls SetMemoryManager(static manager), which
  would overwrite ours. Referencing heapmgr directly pins the order to
  heapmgr -> idfheap -> sysutils -> classes.

  Semantics:
   - RunError(203) on allocation failure, like the default manager;
   - pointers inside the static __fpc_initialheap block (the window between
     heapmgr's and our initialization is empty in practice, but the block
     exists as long as -Ch is in effect) are delegated back to the captured
     static manager - nothing in this build can free an IDF-heap pointer
     with the wrong manager;
   - GetHeapStatus/GetFPCHeapStatus return real IDF-pool numbers instead of
     the static manager's zeros;
   - the static 64 KiB -Ch block still exists in BSS (cfg is global) but
     stays unused; pass a smaller -Ch per program if every BSS byte counts. }

interface

implementation

uses
  { init-order semantics only - see the unit comment. FPC initializes the
    units used here before this unit, guaranteeing heapmgr's static-heap
    manager is installed first, and our initialization then overrides it. }
  heapmgr;

const
  MALLOC_CAP_8BIT    = 1 shl 2;   { esp_heap_caps.h, IDF 5.2.8 }
  MALLOC_CAP_DEFAULT = 1 shl 12;
  CAPS = MALLOC_CAP_8BIT or MALLOC_CAP_DEFAULT;

type
  { multi_heap_info_t (multi_heap.h); size_t = 4 bytes on xtensa }
  TMultiHeapInfo = record
    TotalFreeBytes,
    TotalAllocatedBytes,
    LargestFreeBlock,
    MinimumFreeBytes,
    AllocatedBlocks,
    FreeBlocks,
    TotalBlocks: dword;
  end;

var
  { static heap block bounds; both symbols are emitted per-program by the
    compiler for freertos targets (__heapsize carries the actual -Ch value) }
  initialheap: record end; external name '__fpc_initialheap';
  heapsize: ptruint; external name '__heapsize';

  { manager in effect at our initialization (= heapmgr's static manager);
    kept for delegation of its few potential pre-install blocks }
  StaticMgr: TMemoryManager;
  Mgr: TMemoryManager;

function InStaticHeap(p: pointer): boolean; inline;
  begin
    result := (ptruint(p) >= ptruint(@initialheap)) and
              (ptruint(p) < ptruint(@initialheap) + heapsize);
  end;

function  heap_caps_malloc(size, caps: ptruint): pointer; external name 'heap_caps_malloc';
procedure heap_caps_free(p: pointer); external name 'heap_caps_free';
function  heap_caps_realloc(p: pointer; size, caps: ptruint): pointer; external name 'heap_caps_realloc';
function  heap_caps_calloc(n, size, caps: ptruint): pointer; external name 'heap_caps_calloc';
function  heap_caps_get_allocated_size(p: pointer): ptruint; external name 'heap_caps_get_allocated_size';
procedure heap_caps_get_info(var info: TMultiHeapInfo; caps: ptruint); external name 'heap_caps_get_info';

function IDFGetMem(Size: PtrUInt): pointer;
  begin
    result := heap_caps_malloc(Size, CAPS);
    if result = nil then
      if not ReturnNilIfGrowHeapFails then
        RunError(203);
  end;

function IDFFreeMem(p: pointer): PtrUInt;
  begin
    if p = nil then
      result := 0
    else if InStaticHeap(p) then
      { static-block pointer: the manager that allocated it must free it }
      result := StaticMgr.FreeMem(p)
    else
      begin
        heap_caps_free(p);
        result := 0;
      end;
  end;

function IDFFreeMemSize(p: pointer; Size: PtrUInt): PtrUInt;
  begin
    if InStaticHeap(p) then
      result := StaticMgr.FreeMemSize(p, Size)
    else
      begin
        result := heap_caps_get_allocated_size(p);
        heap_caps_free(p);
      end;
  end;

function IDFAllocMem(Size: PtrUInt): pointer;
  begin
    { heap_caps_calloc zero-fills, which satisfies AllocMem's contract }
    result := heap_caps_calloc(1, Size, CAPS);
    if (result = nil) and (Size <> 0) then
      if not ReturnNilIfGrowHeapFails then
        RunError(203);
  end;

function IDFReAlloc(var p: pointer; Size: PtrUInt): pointer;
  begin
    { FPC's manager contract (heaph.inc: function(var p:pointer;Size:sizeint):
      pointer): the GLOBAL ReAllocMem wrapper just passes p by reference - the
      manager itself must update p in place (TFPList.SetCapacity relies on
      this: "ReallocMem(FList, n)" expects FList to end up pointing at the
      new block). Mirror SysReAllocMem exactly: every branch updates p and
      returns the same value. }
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
        { static-block pointer: the manager that owns it must handle the
          free - StaticMgr.ReAllocMem(p, 0) frees it, whatever Size is }
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
        { on grow failure IDF keeps the original block and returns nil }
        if result = nil then
          if not ReturnNilIfGrowHeapFails then
            RunError(203);
        p := result;
      end;
  end;

function IDFMemSize(p: pointer): PtrUInt;
  begin
    if InStaticHeap(p) then
      result := StaticMgr.MemSize(p)
    else if p = nil then
      result := 0
    else
      result := heap_caps_get_allocated_size(p);
  end;

function IDFGetHeapStatus: THeapStatus;
  var
    info: TMultiHeapInfo;
  begin
    fillchar(result, sizeof(result), 0);
    heap_caps_get_info(info, CAPS);
    result.TotalAddrSpace := info.TotalAllocatedBytes + info.TotalFreeBytes;
    result.TotalCommitted := result.TotalAddrSpace;
    result.TotalAllocated := info.TotalAllocatedBytes;
    result.TotalFree := info.TotalFreeBytes;
    result.FreeBig := info.LargestFreeBlock;
  end;

function IDFGetFPCHeapStatus: TFPCHeapStatus;
  var
    info: TMultiHeapInfo;
  begin
    fillchar(result, sizeof(result), 0);
    heap_caps_get_info(info, CAPS);
    result.MaxHeapSize := info.TotalAllocatedBytes + info.TotalFreeBytes;
    result.CurrHeapUsed := info.TotalAllocatedBytes;
    result.CurrHeapFree := info.TotalFreeBytes;
    result.CurrHeapSize := result.MaxHeapSize;
  end;

initialization
  { heapmgr's SetMemoryManager runs before this (uses heapmgr above);
    capture it, then override the allocation slots with IDF-backed ones }
  GetMemoryManager(Mgr);
  StaticMgr := Mgr;
  Mgr.GetMem := @IDFGetMem;
  Mgr.FreeMem := @IDFFreeMem;
  Mgr.FreeMemSize := @IDFFreeMemSize;
  Mgr.AllocMem := @IDFAllocMem;
  Mgr.ReAllocMem := @IDFReAlloc;
  Mgr.MemSize := @IDFMemSize;
  Mgr.GetHeapStatus := @IDFGetHeapStatus;
  Mgr.GetFPCHeapStatus := @IDFGetFPCHeapStatus;
  SetMemoryManager(Mgr);

finalization
  { nothing to do: the IDF heap lives for the whole device lifetime and
    there are no unit-internal allocations to release (finalization runs
    before heapmgr's, and any static-block objects are freed through the
    delegation above) }
end.
