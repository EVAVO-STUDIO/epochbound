param(
    [string]$GodotExecutable = "godot"
)

$ErrorActionPreference = "Stop"
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

Push-Location $ProjectRoot
try {
    & $GodotExecutable --headless --path $ProjectRoot --import
    if ($LASTEXITCODE -ne 0) {
        throw "Godot import or script parsing failed with exit code $LASTEXITCODE."
    }

    & $GodotExecutable --headless --path $ProjectRoot --script "res://tools/validate_content.gd"
    if ($LASTEXITCODE -ne 0) {
        throw "Campaign content validation failed with exit code $LASTEXITCODE."
    }

    Write-Host "Epochbound project and campaign validation passed."
}
finally {
    Pop-Location
}
