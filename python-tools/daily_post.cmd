@echo off
REM ── THE DAILY POST, as Task Scheduler runs it.
REM
REM ⚠ A WRAPPER RATHER THAN THE COMMAND INLINE, and not for tidiness. schtasks takes the
REM whole command as ONE quoted /TR string, so a python path with spaces plus a script
REM path with spaces plus a redirect needs three levels of nested quoting that Windows
REM parses differently depending on who is doing the parsing. A .cmd file has none of
REM that problem and can be read and run by hand when it misbehaves.
REM
REM ⚠ AND IT LOGS. An unattended post that fails silently is worse than no automation:
REM the maker would believe clips were going out. Every run appends, so the log is the
REM record of what this thing has actually done.

setlocal
set REPO=%~dp0..
set LOG=%REPO%\content\daily_post.log

echo. >> "%LOG%"
echo ======== %DATE% %TIME% ======== >> "%LOG%"
"C:\Python314\python.exe" "%REPO%\python-tools\daily_post.py" --live >> "%LOG%" 2>&1
echo exit=%ERRORLEVEL% >> "%LOG%"
endlocal
