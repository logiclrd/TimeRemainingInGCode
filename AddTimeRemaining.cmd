@echo off

set ScriptPath=%~dp0%AddTimeRemaining.ps1

powershell -File %ScriptPath% -InputFilePath %*
