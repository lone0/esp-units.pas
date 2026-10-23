unit espatomics;

{ Experimental zero-overhead architecture split. }

{$mode objfpc}
{$H+}
{$modeswitch typehelpers}
{$modeswitch advancedrecords}

interface

{$IFDEF FREERTOS}
uses
  freertosinterlocked;
{$ELSE}
uses
  SyncObjs;
{$ENDIF}

{$I espatomics_interface.inc}

implementation

{$IF defined(FREERTOS) and defined(CPUXTENSA)}
  {$I espatomics_backend_xtensa.inc}
{$ELSEIF defined(FREERTOS) and defined(CPURV_HAS_ATOMIC)}
  {$I espatomics_backend_rv32a.inc}
{$ELSEIF defined(FREERTOS) and defined(CPUARM_HAS_LDREX) and defined(CPUARM_HAS_DMB)}
  {$I espatomics_backend_arm32.inc}
{$ELSE}
{$I espatomics_backend_stock.inc}
{$ENDIF}

{$I espatomics_impl.inc}

end.
