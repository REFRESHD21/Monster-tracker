@echo off
setlocal
where gradle >nul 2>nul
if %errorlevel%==0 (gradle %* & exit /b)
set "GRADLE_CACHE=%USERPROFILE%\.gradle\monster-bootstrap"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; $d=$env:GRADLE_CACHE; New-Item -ItemType Directory -Force $d | Out-Null; if (!(Test-Path ($d+'\gradle-8.9\bin\gradle.bat'))) { Invoke-WebRequest https://services.gradle.org/distributions/gradle-8.9-bin.zip -OutFile ($d+'\gradle.zip'); $expected=(Invoke-WebRequest https://services.gradle.org/distributions/gradle-8.9-bin.zip.sha256).Content.Trim(); $actual=(Get-FileHash ($d+'\gradle.zip') -Algorithm SHA256).Hash.ToLower(); if($actual -ne $expected) {throw 'Gradle checksum mismatch'}; Expand-Archive -Force ($d+'\gradle.zip') $d }"
if errorlevel 1 exit /b 1
call "%GRADLE_CACHE%\gradle-8.9\bin\gradle.bat" %*
