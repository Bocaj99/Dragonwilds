@echo off
setlocal

set LOGFILE=C:\Users\Jacob\HarenaCpp\build.log
set SRCDIR=C:\Users\Jacob\HarenaCpp
set OUTDIR=C:\Users\Jacob\HarenaCpp\Output

echo Build started > %LOGFILE%

call "C:\Program Files\Microsoft Visual Studio\18\Community\VC\Auxiliary\Build\vcvarsall.bat" x64 >> %LOGFILE% 2>&1

set PATH=C:\Users\Jacob\.cargo\bin;%PATH%

echo. >> %LOGFILE%
echo === Checking tools === >> %LOGFILE%
where rustc >> %LOGFILE% 2>&1
rustc --version >> %LOGFILE% 2>&1
where cmake >> %LOGFILE% 2>&1
cmake --version >> %LOGFILE% 2>&1
where ninja >> %LOGFILE% 2>&1

echo. >> %LOGFILE%
echo === CMake Configure === >> %LOGFILE%
cmake -S %SRCDIR% -B %OUTDIR% -G Ninja -DCMAKE_BUILD_TYPE=Release >> %LOGFILE% 2>&1
echo CMake configure exit code: %ERRORLEVEL% >> %LOGFILE%

echo. >> %LOGFILE%
echo === CMake Build === >> %LOGFILE%
cmake --build %OUTDIR% --config Release >> %LOGFILE% 2>&1
echo CMake build exit code: %ERRORLEVEL% >> %LOGFILE%

echo. >> %LOGFILE%
echo === Done === >> %LOGFILE%
dir /s /b %OUTDIR%\*.dll >> %LOGFILE% 2>&1

endlocal
