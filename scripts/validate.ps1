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

    Invoke-GodotStep "Smoke test loadout stats capability gates and restoration" @(
        "--headless", "--path", $ProjectRoot,
        "--script", "res://tools/smoke_loadout_runtime.gd"
    )

    Invoke-GodotStep "Smoke test Loadout Studio editor state" @(
        "--headless", "--path", $ProjectRoot,
        "--script", "res://tools/smoke_loadout_studio.gd"
    )

    Invoke-GodotStep "Smoke test malformed equipment capabilities and gates" @(
        "--headless", "--path", $ProjectRoot,
        "--script", "res://tools/smoke_equipment_validation_edges.gd"
    )

    Invoke-GodotStep "Smoke test merchant transactions and durable economy" @(
        "--headless", "--path", $ProjectRoot,
        "--script", "res://tools/smoke_economy_runtime.gd"
    )

    Invoke-GodotStep "Smoke test Merchant and Economy Studio editor state" @(
        "--headless", "--path", $ProjectRoot,
        "--script", "res://tools/smoke_trade_studio.gd"
    )

    Invoke-GodotStep "Smoke test malformed currencies merchants stock and economy saves" @(
        "--headless", "--path", $ProjectRoot,
        "--script", "res://tools/smoke_economy_validation_edges.gd"
    )

    Invoke-GodotStep "Smoke test Arsenal ranged combat and durable magazines" @(
        "--headless", "--path", $ProjectRoot,
        "--script", "res://tools/smoke_arsenal_runtime.gd"
    )

    Invoke-GodotStep "Smoke test Arsenal Studio editor state" @(
        "--headless", "--path", $ProjectRoot,
        "--script", "res://tools/smoke_arsenal_studio.gd"
    )

    Invoke-GodotStep "Smoke test malformed ranged weapons ammunition enemies and saves" @(
        "--headless", "--path", $ProjectRoot,
        "--script", "res://tools/smoke_arsenal_validation_edges.gd"
    )

    Invoke-GodotStep "Smoke test Boss phases patterns reinforcements and outcomes" @(
        "--headless", "--path", $ProjectRoot,
        "--script", "res://tools/smoke_boss_runtime.gd"
    )

    Invoke-GodotStep "Smoke test Boss and Phase Studio editor state" @(
        "--headless", "--path", $ProjectRoot,
        "--script", "res://tools/smoke_boss_studio.gd"
    )

    Invoke-GodotStep "Smoke test malformed boss arenas phases patterns rewards and reinforcements" @(
        "--headless", "--path", $ProjectRoot,
        "--script", "res://tools/smoke_boss_validation_edges.gd"
    )

    Invoke-GodotStep "Smoke test cinematic playback skip and durable completion" @(
        "--headless", "--path", $ProjectRoot,
        "--script", "res://tools/smoke_cinematic_runtime.gd"
    )

    Invoke-GodotStep "Smoke test Cinematic and Timeline Studio editor state" @(
        "--headless", "--path", $ProjectRoot,
        "--script", "res://tools/smoke_cinematic_studio.gd"
    )

    Invoke-GodotStep "Smoke test malformed cinematic maps steps targets effects and checkpoints" @(
        "--headless", "--path", $ProjectRoot,
        "--script", "res://tools/smoke_cinematic_validation_edges.gd"
    )

    Write-Host "`nEpochbound project and all twelve authoring systems passed complete cinematic-aware validation."
}
finally {
    Pop-Location
}
