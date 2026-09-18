@echo off
rem where.cmd - mark the local folder to use for a session/branch.
rem     where.cmd -Want arena/01a0b237-browserskill
rem     where.cmd                 (list every clone)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0where.ps1" %*
