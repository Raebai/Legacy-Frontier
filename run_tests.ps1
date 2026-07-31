<#
.SYNOPSIS
    Run every headless Godot test suite in godot-project/tools/.

.DESCRIPTION
    Thin wrapper around python-tools/run_all_tests.py so the suite can be run
    from the repo root without remembering the path. All arguments are passed
    straight through.

.EXAMPLE
    .\run_tests.ps1
    .\run_tests.ps1 --list
    .\run_tests.ps1 --filter climb --verbose
    .\run_tests.ps1 --jobs 4 --timeout 90
#>

$ErrorActionPreference = "Stop"
$runner = Join-Path $PSScriptRoot "python-tools\run_all_tests.py"

& python $runner @args
exit $LASTEXITCODE
