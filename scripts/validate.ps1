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

    & $GodotExecutable --headless --path $ProjectRoot --script "res://tools/smoke_world_model.gd"
    if ($LASTEXITCODE -ne 0) {
        throw "World-model smoke testing failed with exit code $LASTEXITCODE."
    }

    & $GodotExecutable --headless --path $ProjectRoot --script "res://tools/smoke_encounters.gd"
    if ($LASTEXITCODE -ne 0) {
        throw "Encounter Studio and combat smoke testing failed with exit code $LASTEXITCODE."
    }

    Write-Host "Epochbound project, campaign, world-model and encounter validation passed."
}
finally {
    Pop-Location
}
