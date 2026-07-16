Get-Process dragonruby -ErrorAction SilentlyContinue | Stop-Process -Force
Set-Location 'C:\source\dragonruby'
$proc = Start-Process '.\dragonruby.exe' -ArgumentList 'drecs','--sample','native_boids' -PassThru -NoNewWindow
Start-Sleep -Seconds 6
# Send '+' keypress via SendKeys — actually DR samples read keyboard from $gtk.inputs.keyboard.
# We can simulate by sending the VK_OEM_PLUS key, but SendKeys is unreliable. Instead, just
# let it boot and capture what happens after the spawn.
Start-Sleep -Seconds 4
if (-not $proc.HasExited) { Stop-Process -Id $proc.Id -Force }
if (Test-Path 'C:\source\dragonruby\native_boids_log.txt') {
  Get-Content 'C:\source\dragonruby\native_boids_log.txt' -Tail 20
}