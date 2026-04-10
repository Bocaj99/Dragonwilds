@echo off
setlocal

set LOGFILE=C:\Users\Jacob\HarenaCpp\build.log
set SRCDIR=C:\Users\Jacob\HarenaCpp
set OUTDIR=C:\Users\Jacob\HarenaCpp\Output

echo Build started > "%LOGFILE%"

:: Set up compiler environment manually (avoids vcvarsall.bat locking issues)
set MSVC=C:\Program Files\Microsoft Visual Studio\18\Community\VC\Tools\MSVC\14.50.35717
set WINSDK=C:\Program Files (x86)\Windows Kits\10
set WINSDKVER=10.0.26100.0
set VSDIR=C:\Program Files\Microsoft Visual Studio\18\Community

set PATH=%MSVC%\bin\Hostx64\x64;%WINSDK%\bin\%WINSDKVER%\x64;%VSDIR%\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin;%VSDIR%\Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja;C:\Users\Jacob\.cargo\bin;%PATH%
set INCLUDE=%MSVC%\include;%WINSDK%\Include\%WINSDKVER%\ucrt;%WINSDK%\Include\%WINSDKVER%\shared;%WINSDK%\Include\%WINSDKVER%\um;%WINSDK%\Include\%WINSDKVER%\winrt
set LIB=%MSVC%\lib\x64;%WINSDK%\Lib\%WINSDKVER%\ucrt\x64;%WINSDK%\Lib\%WINSDKVER%\um\x64

echo === Checking tools === >> "%LOGFILE%"
where cl >> "%LOGFILE%" 2>&1
cl >> "%LOGFILE%" 2>&1
where cmake >> "%LOGFILE%" 2>&1
cmake --version >> "%LOGFILE%" 2>&1
where rustc >> "%LOGFILE%" 2>&1
rustc --version >> "%LOGFILE%" 2>&1
where ninja >> "%LOGFILE%" 2>&1

echo. >> "%LOGFILE%"
echo === CMake Configure === >> "%LOGFILE%"
cmake -S "%SRCDIR%" -B "%OUTDIR%" -G "Visual Studio 18 2026" -A x64 -DRust_COMPILER=C:/Users/Jacob/.rustup/toolchains/stable-x86_64-pc-windows-msvc/bin/rustc.exe -DRust_CARGO=C:/Users/Jacob/.rustup/toolchains/stable-x86_64-pc-windows-msvc/bin/cargo.exe >> "%LOGFILE%" 2>&1
echo CMake configure exit code: %ERRORLEVEL% >> "%LOGFILE%"

if %ERRORLEVEL% NEQ 0 (
    echo CMake configure FAILED - check build.log
    goto :end
)

echo. >> "%LOGFILE%"
echo === CMake Build === >> "%LOGFILE%"
cmake --build "%OUTDIR%" --config Game__Shipping__Win64 -- /m >> "%LOGFILE%" 2>&1
echo CMake build exit code: %ERRORLEVEL% >> "%LOGFILE%"

echo. >> "%LOGFILE%"
echo === Done === >> "%LOGFILE%"
dir /s /b "%OUTDIR%\*.dll" >> "%LOGFILE%" 2>&1

:end
echo.
echo Build log: %LOGFILE%
type "%LOGFILE%" | findstr /C:"==="  /C:"exit code" /C:"FAILED" /C:"SUCCESS" /C:".dll"
endlocal
