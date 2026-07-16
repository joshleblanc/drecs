$gccDir = 'C:\msys64\ucrt64\bin'
$env:Path = $gccDir + ';' + $env:Path
Set-Location 'C:\source\dragonruby\drecs\ext'
& cmd.exe /c build.bat