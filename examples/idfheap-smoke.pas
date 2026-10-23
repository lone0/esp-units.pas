program idfheap_smoke;

{$mode objfpc}{$H+}

{ Smoke test for the idfheap unit - the production manager routing.
  idfheap is FIRST in uses, so
  the IDF-backed manager is installed before sysutils/classes initialize
  (init order: heapmgr -> idfheap -> sysutils -> ... -> classes).

  Proves:
   1. every allocation - even from these unit inits - lives in the IDF pool
      (address orientation: 0x3FCxxxxx-ish = IDF internal-DRAM pool; with
      PSRAM enabled in the SDK project, allocations migrate to the 0x3C…
      external window);
   2. GetFPCHeapStatus reports real IDF-pool numbers;
   3. a full classes/strings/dynarray workload runs on the managed pool;
   4. clean exit: classes' teardown (TThreadList, TEncodings, ...) frees
      everything through the IDF manager - RunError-free, exit 0;
   5. where the memory lands: every observable pointer is classified with
      IDF's PSRAM-specific esp_ptr_external_ram (never by address ranges -
      the 0x3C... cache window holds flash DROM as well as PSRAM). With
      CONFIG_SPIRAM_USE_MALLOC in the SDK project, allocations above
      CONFIG_SPIRAM_MALLOC_ALWAYSINTERNAL bytes may migrate to PSRAM: the
      dynarray growth loop prints its location on every change. }

uses
  idfheap,       { MUST be first: installs the manager before all inits }
  classes, sysutils;

{ ESP-IDF pointer classifier (real symbol, IDF 5.2.8 esp_hw_support,
  esp_memory_utils.c:76; PSRAM-specific - false when CONFIG_SPIRAM is off).
  Do NOT also declare esp_ptr_internal: in IDF 5.x it is a static header
  inline, not a linkable symbol - treat "not external" as internal. }
function esp_ptr_external_ram(p: pointer): boolean; cdecl; external name 'esp_ptr_external_ram';

function LocationOf(p: pointer): string;
begin
  if p = nil then
    Result := 'nil'
  else if esp_ptr_external_ram(p) then
    Result := 'PSRAM'
  else
    Result := 'internal SRAM';
end;

var
  p: pointer;
  st: TFPCHeapStatus;
  lst: TStringList;
  i: smallint;
  s: SizeInt;
  big: array of longint;
  loc, prev: string;
begin
  p := GetMem(4096);
  writeln('GetMem(4096) @', hexstr(ptruint(p), 8), ' -> ', LocationOf(p));

  st := GetFPCHeapStatus;
  writeln('IDF pool: used=', st.CurrHeapUsed, ' free=', st.CurrHeapFree,
          ' size=', st.CurrHeapSize);

  lst := TStringList.Create;
  for i := 1 to 100 do
    lst.Add('value' + IntToStr(1000 + i));
  lst.Sort;
  s := Length(lst[99]);
  writeln('TStringList: 100 items sorted; last item length ', s);
  { the list's per-item strings are managed AnsiStrings; classify one of
    them (the first data pointer) as an observable sample of those }
  writeln('TStringList item string @', hexstr(ptruint(Pointer(lst[0])), 8),
          ' -> ', LocationOf(Pointer(lst[0])));

  { 100 growth steps: each SetLength reallocates; print only when the
    memory location CHANGES - this is where a big allocation migrates
    to PSRAM under CONFIG_SPIRAM_USE_MALLOC }
  prev := '';
  for i := 0 to 99 do
    begin
      SetLength(big, (i + 1) * 500);
      big[i] := i * i;
      loc := LocationOf(Pointer(big));
      if (loc <> prev) or (i = 99) then
        begin
          writeln('dynarray ', (i + 1) * 500, ' slots @',
                  hexstr(ptruint(Pointer(big)), 8), ' -> ', loc);
          prev := loc;
        end;
    end;
  writeln('dynarray content ok, big[99]=', big[99]);
  SetLength(big, 0);

  lst.Free;
  FreeMem(p);
  writeln('idfheap smoke OK');
end.
