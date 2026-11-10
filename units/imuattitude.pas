{ imuattitude - Pascal-native tilt-angle facade (L2) over the BMI270
  accelerometer, for hand-held tilt applications.

  Semantics (the API contract - read before deciding to "fix" either
  formula; both shapes were paid for on hardware):

    rollDeg  lateral lean, RELATIVE TO THE POSE THE BOARD WAS IN AT
             InitBmi270 time. InitBmi270 averages 16 ax samples as the
             lateral
             baseline (ax0), which removes both the chip's zero-g
             offset and whatever the resting surface tilts - so
             "however you prop it at power-on IS centered".
    tiltDeg  ABSOLUTE angle from gravity: 0 = lying flat (screen up),
             90 = vertical. NOT calibrated - "flat" and "vertical" are
             gravity-defined absolutes, not pose-relative.

    The roll formula atan2(ax, sqrt(ay^2+az^2)) keeps the denominator
    positive for ANY orientation. atan2(ax, az) - the "obvious" form -
    blows up to +-180 deg whenever az < 0 (board face-down or propped
    past vertical): a stationary board then steered at full rate.

  Measurement config: accelerometer only, +-4G / 100 Hz (the official
  BSP defaults, same as imu_gesture.c) - thresholds built on these
  angles are tuned against that range.

  Honest boundary: this unit provides roll+pitch ONLY (accelerometer).
  Yaw needs gyro/magnetometer fusion and is NOT provided - no promises,
  no stubs. A different chip (QMI8658 and friends cannot reuse the
  BMI270 driver - registers/protocol/firmware all differ) means a new
  L1 binding plus re-checking the two formulas; the unit's semantics
  are chip-agnostic by construction.

  Lifecycle: none by design. Firmware-style apps create at boot and
  use forever; InitBmi270 failure just leaves imu = nil and Read returns
  false - the caller decides its own fallback (an app-level wander
  simulation, a safe halt, ...).

  InitBmi270 depends on esp_board_manager for the bus handle (borrowed -
  BMGR owns the bus lifecycle, the repo's standing pattern); a future
  non-BMGR variant takes a bus handle directly.

  Uses: c_bmgr (bus handle), c_bmi270 (L1 binding). Link the
  precompiled component archive - see c_bmi270.pas for the path. }

unit imuattitude;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  c_bmgr;

type
  TImuAttitude = record
    imu: pointer;              { opaque bmi270 handle; nil = not opened }
    ax0: double;               { lateral baseline (g): the boot pose }
    function InitBmi270(periph_name: PChar; addr: cuint8): boolean;
      { open on the BMGR periph named periph_name ('i2c_master' on the
        ESP-Mosaico), config accel +-4G/100Hz, enable, sample the
        lateral baseline. False = sensor unusable (imu = nil). }
    function Read(out rollDeg, tiltDeg: double): boolean;
      { one I2C read + the two formulas. False = read failed (values
        undefined); retry on the next call. }
  end;

implementation

uses
  c_bmi270, Math;

const
  G_PER_COUNT = 4.0 / 32768.0;      { +-4G range, int16 counts }

{ FreeRTOS pacing for InitBmi270's baseline sampling (ms == ticks at the
  anchors' FREERTOS_HZ=1000) }
procedure vTaskDelay(ticks: cuint32); cdecl; external;

function TImuAttitude.InitBmi270(periph_name: PChar; addr: cuint8): boolean;
var
  bus: pointer;
  cfg: Tb2SensCfg;
  d: Tb2SensData;
  en: cuint8;
  k: integer;
begin
  Result := false;
  imu := nil;
  ax0 := 0;
  bus := nil;
  if (esp_board_manager_get_periph_handle(periph_name, @bus) <> ESP_OK) or
     (bus = nil) then
    exit;
  if bmi270_sensor_create_from_master_bus_with_address(
       bus, addr, @imu, @bmi270_config_file,
       BMI2_GYRO_CROSS_SENS_ENABLE or BMI2_CRT_RTOSK_ENABLE) <> ESP_OK then
    exit;

  fillchar(cfg, sizeof(cfg), 0);
  cfg.sens_type := BMI2_ACCEL;
  en := BMI2_ACCEL;
  if bmi2_get_sensor_config(@cfg, 1, imu) <> BMI2_OK then
    exit;
  cfg.u[0] := BMI2_ACC_ODR_100HZ;      { odr }
  cfg.u[1] := BMI2_ACC_NORMAL_AVG4;    { bwp }
  cfg.u[2] := BMI2_PERF_OPT_MODE;      { filter_perf }
  cfg.u[3] := BMI2_ACC_RANGE_4G;       { range }
  if (bmi2_set_sensor_config(@cfg, 1, imu) <> BMI2_OK) or
     (bmi2_sensor_enable(@en, 1, imu) <> BMI2_OK) then
    exit;

  { lateral baseline: however the board rests at power-on IS centered }
  for k := 1 to 16 do
  begin
    if bmi2_get_sensor_data(@d, imu) = BMI2_OK then
      ax0 := ax0 + d.acc.x * G_PER_COUNT;
    vTaskDelay(10)
  end;
  ax0 := ax0 / 16;
  Result := true
end;

function TImuAttitude.Read(out rollDeg, tiltDeg: double): boolean;
var
  d: Tb2SensData;
  ax, ay, az: double;
begin
  Result := false;
  rollDeg := 0;
  tiltDeg := 0;
  if (imu = nil) or (bmi2_get_sensor_data(@d, imu) <> BMI2_OK) then
    exit;
  ax := d.acc.x * G_PER_COUNT - ax0;
  ay := d.acc.y * G_PER_COUNT;
  az := d.acc.z * G_PER_COUNT;
  { see the header: denominator must stay positive for any orientation }
  rollDeg := arctan2(ax, sqrt(ay*ay + az*az)) * 180 / pi;
  tiltDeg := arctan2(sqrt(ax*ax + ay*ay), az) * 180 / pi;
  Result := true
end;

end.
