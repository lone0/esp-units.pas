unit espatomics;

{ Experimental zero-overhead architecture split. }

{$mode objfpc}
{$H+}
{$modeswitch advancedrecords}

interface

{ The unit has no uses clause on any target: the leaf primitives are
  self-contained (RV32A assembler leaves, stock backend maps to
  the System unit's Interlocked* routines, which exist on every target). }

{$I espatomics_interface.inc}

implementation

{$IF defined(FREERTOS) and defined(CPUXTENSA)}
  {$I espatomics_backend_xtensa.inc}
{$ELSEIF defined(FREERTOS) and defined(CPURV_HAS_ATOMIC)}
  {$I espatomics_backend_rv32a.inc}
{$ELSE}
{$I espatomics_backend_stock.inc}
{$ENDIF}

end.
