{ c_bmi270 - Pascal binding (L1, C-ABI shadow) for the
  espressif/bmi270_sensor C component (IDF 6.1 precompiled archive).

  Layer grammar (units/README.md): `c_<C component short name>` = L1
  binding - hand-converted C headers only, `cdecl; external` functions
  keep their C names; Pascal-native services live in unprefixed L2
  units (see imuattitude.pas for the tilt-angle facade).

  Source: managed_components/espressif__bmi270_sensor (mosaico-s31 SDK
  tree)
    include/bmi270_api.h    component wrapper (create/del on an
                            i2c_master bus, config-file blob)
    include/bmi2_defs.h     the vendored Bosch SensorAPI surface used
                            here (sens data/config records, enum-ish
                            defines)

  The component ships per-IDF-version precompiled archives; link with
  the full path, e.g.
  --lib <sdk>/managed_components/espressif__bmi270_sensor/<ver>/<chip>/libbmi270_sensor.a
  (whole-archived by build.sh --lib).

  Layout facts (riscv32 ILP32, verified against the component headers):
    pointer 4 B, C int 4 B, C enum 4 B. -$PACKRECORDS C matches gcc
    padding (verified sizes: Tb2SensData = 40, Tb2SensCfg = 52).

  The discrete gesture classifier demo (imu_gesture.c) sits on this
  same API; it is event-based (shake/tilt/flip with cooldown) and not
  usable for continuous steering - the driver API is the reusable part. }

unit c_bmi270;

{$mode objfpc}{$H+}
{$packrecords C}
{$minenumsize 4}

interface

uses
  c_bmgr;   { esp_err_t and the stdint scalar surface }

{ ------------------------------------------------- wrapper entry points }

{ create the sensor on an i2c_master bus handle (borrowed: the bus
  lifecycle belongs to its owner - BMGR in this repo's apps); variant
  flags = BMI2_GYRO_CROSS_SENS_ENABLE or BMI2_CRT_RTOSK_ENABLE. }
function bmi270_sensor_create_from_master_bus_with_address(
  i2c_bus: pointer; i2c_addr: cuint8; handle_ret: ppvoid;
  config_file: pointer; variant_feature: cuint64): esp_err_t; cdecl; external;

{ int8_t return codes: BMI2_OK = 0 }
function bmi2_get_sensor_config(sens_cfg: pointer; n_sens: cuint8;
  dev: pointer): cint8; cdecl; external;
function bmi2_set_sensor_config(sens_cfg: pointer; n_sens: cuint8;
  dev: pointer): cint8; cdecl; external;
function bmi2_sensor_enable(sensors: pointer; n_sens: cuint8;
  dev: pointer): cint8; cdecl; external;
function bmi2_get_sensor_data(data: pointer; dev: pointer): cint8; cdecl; external;

{ const uint8_t bmi270_config_file[] - the sensor's config blob that
  ships inside the component archive; the symbol's address is the data }
var
  bmi270_config_file: cuint8; external;

{ ------------------------------------------------------ defines we use }

const
  BMI2_OK                       = 0;
  BMI2_ACCEL                    = 0;      { sensor type id }
  BMI2_ACC_ODR_100HZ            = $08;
  BMI2_ACC_RANGE_4G             = $01;
  BMI2_ACC_NORMAL_AVG4          = $02;
  BMI2_PERF_OPT_MODE            = $01;
  BMI2_GYRO_CROSS_SENS_ENABLE   = $02;
  BMI2_CRT_RTOSK_ENABLE         = $01;

{ ------------------------------------------------------ record subsets }

type
  { struct bmi2_sens_axes_data - 12 B }
  Tb2Axes = record
    x, y, z: cint16;
    virt_sens_time: cuint32;
  end;

  { struct bmi2_sens_data - 40 B }
  Pb2SensData = ^Tb2SensData;
  Tb2SensData = record
    acc, gyr: Tb2Axes;
    aux_data: array[0..7] of cuint8;
    sens_time: cuint32;
    status: cuint8;
  end;

  { struct bmi2_sens_config - 52 B: type@0, union@2 (largest member is
    step_counter_params[25] of u16). The acc member of that union:
    odr, bwp, filter_perf, range at union offsets 0..3 - exposed as
    u[] bytes here; the L2 pokes them after a get_sensor_config }
  Tb2SensCfg = record
    sens_type: cuint8;
    pad: cuint8;
    u: array[0..49] of cuint8;
  end;

implementation

end.
