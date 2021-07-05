@echo off

set ScriptPath=%~dp0%AddTimeRemaining.ps1

powershell -ExecutionPolicy Bypass -File %ScriptPath% -InputFilePath %*
