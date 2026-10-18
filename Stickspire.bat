@echo off
title Stickspire build session
cd /d "%~dp0"
echo Starting the Stickspire PC session in %cd%
echo (reads CLAUDE.md, then docs/PC-SESSION.md, and works the PC queue)
echo.
claude "Read CLAUDE.md, then read docs/PC-SESSION.md and follow it exactly, starting at step 1."
pause
