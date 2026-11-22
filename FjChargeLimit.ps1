<#
.SYNOPSIS
  FUJITSU LIFEBOOK U9311/F (FMVU34021) のバッテリー充電上限を EC に設定・確認する。

.DESCRIPTION
  Fujitsu FUJ02E3 Device Driver に付属する fuj02e3-utility.dll の CallFuncMethod を使い、
  ACPI の \_SB.FEXT.FUNC(0x1006, 0x21, <cmd>, 0) を呼び出す
  (= DSDT の S006 にある EC バッテリー用メールボックス。EC の 0xE0-0xE8 番地)。

    cmd = 0x21                  現在の充電上限(%)を読む
    cmd = (pct * 0x100) + 0x20  充電上限を pct% に設定する

  Linux カーネルの fujitsu-laptop ドライバー (charge_control_end_threshold) と同じ方式。
  設定は EC に保持され、BIOS は起動時と復帰時に読み直す (\_SB.CMB1.GLCS)。
  管理者権限は不要。

  この機種の BIOS では、富士通の新しい API (充電上限 0x2002 / ピークシフト 0x2000 /
  スマートバッテリー 0x1015) と ACPI 標準の _BMC は非対応。使えるのはこの上限設定だけ。

  注意 (2026-11-22 に実機で確認したこと):
    - 残量 90% で充電中に上限を 80% にすると、すぐに充電が止まり、PC はアダプターの
      電源で動き続けた。バッテリーは放電もしなかった。
    - 上限 80% のまま残量 79% まで使い、コンセント側で差し直すと、アダプターは認識された
      が充電は始まらなかった。その状態で上限を 90% にすると充電が始まり、90% で止まった。
      上限を少し下回っただけでは再開せず、十分に下回ると再開する
      (1% 下では再開せず、11% 下では再開した)。
    - 差し直したアダプターが認識されないことがあったが、上限 100% でも起き、このスクリプト
      を使う前の記録にも同じ形があった。コンセント側で抜き差しすると直るので、
      アダプター側の問題とみられる。

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File .\FjChargeLimit.ps1
    現在の状態を表示する

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File .\FjChargeLimit.ps1 -Set 50
    上限を 50% にする (アダプターを差したまま実行する。上の注意を参照)

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File .\FjChargeLimit.ps1 -Set 100
    元に戻す (制限なし)
#>
param(
  [ValidateRange(50, 100)]
  [int]$Set
)
$ErrorActionPreference = 'Stop'

$key = 'HKLM:\SYSTEM\CurrentControlSet\Services\Fuj02e3DriverUtilityService\Parameters\Utility'
$dll = (Get-ItemProperty -Path $key -ErrorAction SilentlyContinue).DllPath
if (-not $dll -or -not (Test-Path $dll)) {
  throw 'fuj02e3-utility.dll not found. Fujitsu FUJ02E3 Device Driver is required.'
}

if (-not ('FjEc' -as [type])) {
  Add-Type -TypeDefinition @"
using System.Runtime.InteropServices;
public static class FjEc {
  [DllImport(@"$dll")]
  public static extern int CallFuncMethod(uint f, uint a, uint b, uint c, out uint r);
}
"@
}

function Invoke-EcBattery([uint32]$Cmd) {
  $r = [uint32]0
  $rc = [FjEc]::CallFuncMethod(0x1006, 0x21, $Cmd, 0, [ref]$r)
  if ($rc -ne 0) { throw "CallFuncMethod failed (rc=$rc)" }
  return $r
}

function Get-EcChargeLimit {
  $r = Invoke-EcBattery 0x21
  if ($r -band 0x80000000) { throw ('EC returned error 0x{0:X8}' -f $r) }
  return [int]($r -band 0xFF)
}

$before = Get-EcChargeLimit
if ($before -lt 1 -or $before -gt 100) { throw "Unexpected charge limit value from EC: $before" }

if ($PSBoundParameters.ContainsKey('Set')) {
  $resp = Invoke-EcBattery ([uint32]($Set * 0x100 + 0x20))
  if ($resp -eq 0) { Write-Warning "EC rejected $Set% (response 0). Nothing was changed." }
  elseif ($resp -band 0x80000000) { Write-Warning ('EC error 0x{0:X8}' -f $resp) }
  Start-Sleep -Milliseconds 300
  $after = Get-EcChargeLimit
  'Charge limit: {0}% -> {1}%  (EC response 0x{2:X})' -f $before, $after, $resp
  if ($after -lt 100) {
    Write-Warning '残量が上限を少し下回っただけでは充電は再開されません (11% 下回ったときは再開を確認)。満充電にしたいときは -Set 100 にしてください。'
  }
}
else {
  'Charge limit: {0}%' -f $before
}

$bs = Get-CimInstance -Namespace root\wmi -ClassName BatteryStatus | Select-Object -First 1
$fc = (Get-CimInstance -Namespace root\wmi -ClassName BatteryFullChargedCapacity | Select-Object -First 1).FullChargedCapacity
$pct = if ($fc) { [math]::Round(100 * $bs.RemainingCapacity / $fc) } else { '?' }
'Battery: {0}%  AC={1}  Charging={2}  Discharging={3}  ChargeRate={4}mW  DischargeRate={5}mW' -f $pct, $bs.PowerOnline, $bs.Charging, $bs.Discharging, $bs.ChargeRate, $bs.DischargeRate
