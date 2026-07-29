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

    Invoke-GodotStep "Smoke test Item Forge editor state" @(
        "--headless", "--path", $ProjectRoot,
        "--script", "res://tools/smoke_item_forge_editor.gd"
    )

    Invoke-GodotStep "Smoke test malformed item rewards and recipe unlocks" @(
        "--headless", "--path", $ProjectRoot,
        "--script", "res://tools/smoke_item_validation_edges.gd"
    )

    Invoke-GodotStep "Smoke test Story Studio branching and quest progression" @(
        "--headless", "--path", $ProjectRoot,
        "--script", "res://tools/smoke_story_studio.gd"
    )

    Invoke-GodotStep "Smoke test Story Studio editor graph and forms" @(
        "--headless", "--path", $ProjectRoot,
        "--script", "res://tools/smoke_story_studio_editor.gd"
    )

    Invoke-GodotStep "Smoke test malformed story graphs and quest records" @(
        "--headless", "--path", $ProjectRoot,
        "--script", "res://tools/smoke_story_validation_edges.gd"
    )

    Invoke-GodotStep "Smoke test save capture and exact restoration" @(
        "--headless", "--path", $ProjectRoot,
        "--script", "res://tools/smoke_save_profiles.gd"
    )

    Invoke-GodotStep "Smoke test save migration integrity and backup recovery" @(
        "--headless", "--path", $ProjectRoot,
        "--script", "res://tools/smoke_save_migrations.gd"
    )

    Invoke-GodotStep "Smoke test Save and State Studio inspector" @(
        "--headless", "--path", $ProjectRoot,
        "--script", "res://tools/smoke_save_state_studio.gd"
    )

    Write-Host "`nEpochbound project, campaign, world-model, encounter, Combat Director, Companion Studio, Item Forge, Story Studio and Save & State Studio validation passed."
}
finally {
    Pop-Location
}
