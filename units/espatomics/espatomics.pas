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
{$ENDIF}
{ Host targets compile without any uses clause: the TInterlockedEsp helper
  wraps the FreeRTOS-only TInterlocked baseline, and the leaf primitives
  use the System unit's Interlocked* routines directly. }

{$I espatomics_interface.inc}

implementation

{$IF defined(FREERTOS) and defined(CPUXTENSA)}
  {$I espatomics_backend_xtensa.inc}
{$ELSEIF defined(FREERTOS) and defined(CPURV_HAS_ATOMIC)}
  {$I espatomics_backend_rv32a.inc}
{$ELSE}
{$I espatomics_backend_stock.inc}
{$ENDIF}

{$I espatomics_impl.inc}

end.
