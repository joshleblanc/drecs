Add-Type @"
using System;
using System.Runtime.InteropServices;
public class WinKey {
    [DllImport("user32.dll")]
    public static extern bool PostMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);
    public const uint WM_KEYDOWN = 0x0100;
    public const uint WM_KEYUP = 0x0101;
}
"@

Get-Process dragonruby -ErrorAction SilentlyContinue | Stop-Process -Force
Set-Location 'C:\source\dragonruby'
Remove-Item 'C:\source\dragonruby\native_boids_log.txt' -ErrorAction SilentlyContinue
$proc = Start-Process '.\dragonruby.exe' -ArgumentList 'drecs','--sample','native_boids' -PassThru -NoNewWindow
Start-Sleep -Seconds 4

$proc.Refresh()
$mainWindow = (Get-Process -Id $proc.Id).MainWindowHandle
# Press + 5 times (5000 -> 10000), then - 5 times (10000 -> 5000), then + 5 times (5000 -> 10000), then - 10 times (10000 -> 0)
foreach ($phase in @('+', '+', '+', '+', '+', '-', '-', '-', '-', '-', '+', '+', '+', '+', '+', '-', '-', '-', '-', '-', '-', '-', '-', '-', '-')) {
  $vk = if ($phase -eq '+') { 0xBB } else { 0xBD }
  [WinKey]::PostMessage($mainWindow, [WinKey]::WM_KEYDOWN, [IntPtr]$vk, [IntPtr]0) | Out-Null
  Start-Sleep -Milliseconds 80
  [WinKey]::PostMessage($mainWindow, [WinKey]::WM_KEYUP, [IntPtr]$vk, [IntPtr]0) | Out-Null
  Start-Sleep -Milliseconds 120
}

Start-Sleep -Seconds 6
if (-not $proc.HasExited) { Stop-Process -Id $proc.Id -Force }
if (Test-Path 'C:\source\dragonruby\native_boids_log.txt') {
  Get-Content 'C:\source\dragonruby\native_boids_log.txt'
}