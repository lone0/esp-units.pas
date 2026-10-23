program probe_idfheap;
{ Documents that the IDF heap API (heap_caps_*) - the one that can hand out
  PSRAM blocks once CONFIG_SPIRAM is enabled - is ALREADY LINKED into every
  FPC-freertos binary via espidf_50200's {$linklib heap,static}: a Pascal
  program just declares the externals and calls them. The default Pascal
  allocator (heapmgr static block, -Ch) is untouched by this. }

uses idfheap;

const
  MALLOC_CAP_8BIT     = 1 shl 2;   { from esp_heap_caps.h (IDF 5.2.8) }
  MALLOC_CAP_SPIRAM   = 1 shl 10;
  MALLOC_CAP_INTERNAL = 1 shl 11;
  MALLOC_CAP_DEFAULT  = 1 shl 12;

function  heap_caps_malloc(size, caps: ptruint): pointer; external name 'heap_caps_malloc';
procedure heap_caps_free(p: pointer); external name 'heap_caps_free';
function  heap_caps_get_free_size(caps: ptruint): ptruint; external name 'heap_caps_get_free_size';
function  heap_caps_get_largest_free_block(caps: ptruint): ptruint; external name 'heap_caps_get_largest_free_block';

var
  buf: pointer;
  internal_free, spiram_free, largest: ptruint;
begin
  internal_free := heap_caps_get_free_size(MALLOC_CAP_INTERNAL or MALLOC_CAP_8BIT);
  spiram_free   := heap_caps_get_free_size(MALLOC_CAP_SPIRAM or MALLOC_CAP_8BIT);
  largest       := heap_caps_get_largest_free_block(MALLOC_CAP_INTERNAL or MALLOC_CAP_8BIT);
  writeln('idf internal free=', internal_free shr 10, 'KB largest=', largest shr 10, 'KB');
  writeln('idf SPIRAM    free=', spiram_free, 'B (0 means CONFIG_SPIRAM is off)');

  { real allocation from the IDF-managed pool - independent of -Ch heap }
  buf := heap_caps_malloc(65536, MALLOC_CAP_8BIT);
  if buf <> nil then
    begin
      writeln('idf alloc ok @', hexstr(ptruint(buf), 8), ' (64KB)');
      heap_caps_free(buf);
      writeln('idf free ok');
    end
  else
    writeln('idf alloc FAILED');
end.
