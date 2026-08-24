@echo off
REM ---- THE DAILY POST, as Task Scheduler runs it. ----
REM
REM PURE ASCII, DELIBERATELY. The first version of this file carried the same
REM warning glyphs and em dashes as the rest of the repo, and cmd.exe reads a .cmd
REM in the console OEM codepage, not UTF-8. Those bytes got mangled, several REM
REM lines stopped being REM lines, and cmd tried to EXECUTE the fragments:
REM     'M' is not recognized as an internal or external command
REM seven times, before stumbling on to the python line by luck. A batch file is not
REM a source file; keep it to characters cmd cannot misread.
REM
REM A WRAPPER RATHER THAN THE COMMAND INLINE: schtasks takes the whole command as one
REM quoted /TR string, so a python path with spaces plus a script path with spaces
REM plus a redirect needs three levels of nested quoting that different parsers
REM disagree about. This file has none of that and can be run by hand to debug.
REM
REM AND IT LOGS. An unattended post that fails silently is worse than no automation:
REM the maker would believe clips were going out. Every run appends.
REM
REM Set STICKSPIRE_DAILY_DRY=1 to rehearse this exact command without uploading.

setlocal
set REPO=%~dp0..
set LOG=%REPO%\content\daily_post.log

echo. >> "%LOG%"
echo ======== %DATE% %TIME% ======== >> "%LOG%"
"C:\Python314\python.exe" "%REPO%\python-tools\daily_post.py" --live >> "%LOG%" 2>&1
echo exit=%ERRORLEVEL% >> "%LOG%"
endlocal
