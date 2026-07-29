param(
    [string]$GodotExecutable = "godot"
)

$ErrorActionPreference = "Stop"
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

function Invoke-GodotStep {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Description,

        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    Write-Host "`n==> $Description"
    $output = & $GodotExecutable @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    $output | ForEach-Object { Write-Host $_ }

    if ($exitCode -ne 0) {
        throw "$Description failed with exit code $exitCode."
    }

    $combined = $output -join "`n"
    if ($combined -match "SCRIPT ERROR:" -or $combined -match "(?m)^ERROR:") {
        throw "$Description emitted a Godot parser or runtime error despite returning exit code 0."
    }
}

Push-Location $ProjectRoot
try {
    Invoke-GodotStep "Compile runtime scenes and editor plugins" @(
        "--headless", "--path", $ProjectRoot,
        "--script", "res://tools/compile_probe.gd"
    )

    Invoke-GodotStep "Import project" @(
        "--headless", "--path", $ProjectRoot,
        "--import"
    )

    Invoke-GodotStep "Validate campaign content" @(
        "--headless", "--path", $ProjectRoot,
        "--script", "res://tools/validate_content.gd"
    )

    Invoke-GodotStep "Smoke test world model and traversal" @(
        "--headless", "--path", $ProjectRoot,
        "--script", "res://tools/smoke_world_model.gd"
    )

    Invoke-GodotStep "Smoke test Encounter Studio and base combat" @(
        "--headless", "--path", $ProjectRoot,
        "--script", "res://tools/smoke_encounters.gd"
    )

    Invoke-GodotStep "Smoke test Combat Director zones and behaviour" @(
        "--headless", "--path", $ProjectRoot,
        "--script", "res://tools/smoke_combat_director.gd"
    )

    Invoke-GodotStep "Smoke test Companion Studio commands and discovery" @(
        "--headless", "--path", $ProjectRoot,
        "--script", "res://tools/smoke_companion_director.gd"
    )

    Invoke-GodotStep "Smoke test Item Forge inventory and crafting" @(
        "--headless", "--path", $ProjectRoot,
        "--script", "res://tools/smoke_item_forge.gd"
    )

    Write-Host "`nEpochbound project, campaign, world-model, encounter, Combat Director, Companion Studio and Item Forge validation passed."
}
finally {
    Pop-Location
}
