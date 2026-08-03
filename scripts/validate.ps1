param(
    [string]$GodotExecutable = "godot"
)

$ErrorActionPreference = "Stop"
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

function Invoke-GodotStep {
    param(
        [Parameter(Mandatory = $true)] [string]$Description,
        [Parameter(Mandatory = $true)] [string[]]$Arguments
    )
    Write-Host "`n==> $Description"
    $output = & $GodotExecutable @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    $output | ForEach-Object { Write-Host $_ }
    if ($exitCode -ne 0) { throw "$Description failed with exit code $exitCode." }
    $combined = $output -join "`n"
    if ($combined -match "SCRIPT ERROR:" -or $combined -match "(?m)^ERROR:") {
        throw "$Description emitted a Godot parser or runtime error despite returning exit code 0."
    }
}

Push-Location $ProjectRoot
try {
    $Tests = @(
        @("Compile runtime scenes and editor plugins", "res://tools/compile_probe.gd"),
        @("Compile Sprite Animation runtime editors and tests", "res://tools/compile_sprite_animation_probe.gd"),
        @("Compile player settings runtime storage presentation and tests", "res://tools/compile_player_settings_probe.gd"),
        @("Smoke test canonical runtime scene composition", "res://tools/smoke_runtime_scene_contract.gd"),
        @("Smoke test persistent player settings and accessibility", "res://tools/smoke_player_settings.gd"),
        @("Smoke test player settings crash recovery and modal freeze edges", "res://tools/smoke_player_settings_recovery_edges.gd"),
        @("Validate campaign content", "res://tools/validate_content.gd"),
        @("Run deterministic campaign production audit", "res://tools/audit_campaigns.gd"),
        @("Smoke test world model and traversal", "res://tools/smoke_world_model.gd"),
        @("Smoke test Encounter Studio and base combat", "res://tools/smoke_encounters.gd"),
        @("Smoke test Combat Director zones and behaviour", "res://tools/smoke_combat_director.gd"),
        @("Smoke test Companion Studio commands and discovery", "res://tools/smoke_companion_director.gd"),
        @("Smoke test Item Forge inventory and crafting", "res://tools/smoke_item_forge.gd"),
        @("Smoke test Item Forge editor state", "res://tools/smoke_item_forge_editor.gd"),
        @("Smoke test malformed item rewards and recipe unlocks", "res://tools/smoke_item_validation_edges.gd"),
        @("Smoke test Story Studio branching and quest progression", "res://tools/smoke_story_studio.gd"),
        @("Smoke test Story Studio editor graph and forms", "res://tools/smoke_story_studio_editor.gd"),
        @("Smoke test malformed story graphs and quest records", "res://tools/smoke_story_validation_edges.gd"),
        @("Smoke test save capture and exact restoration", "res://tools/smoke_save_profiles.gd"),
        @("Smoke test save migration integrity and backup recovery", "res://tools/smoke_save_migrations.gd"),
        @("Smoke test Save and State Studio inspector", "res://tools/smoke_save_state_studio.gd"),
        @("Smoke test loadout stats capability gates and restoration", "res://tools/smoke_loadout_runtime.gd"),
        @("Smoke test Loadout Studio editor state", "res://tools/smoke_loadout_studio.gd"),
        @("Smoke test malformed equipment capabilities and gates", "res://tools/smoke_equipment_validation_edges.gd"),
        @("Smoke test merchant transactions and durable economy", "res://tools/smoke_economy_runtime.gd"),
        @("Smoke test Merchant and Economy Studio editor state", "res://tools/smoke_trade_studio.gd"),
        @("Smoke test malformed currencies merchants stock and economy saves", "res://tools/smoke_economy_validation_edges.gd"),
        @("Smoke test Arsenal ranged combat and durable magazines", "res://tools/smoke_arsenal_runtime.gd"),
        @("Smoke test Arsenal Studio editor state", "res://tools/smoke_arsenal_studio.gd"),
        @("Smoke test malformed ranged weapons ammunition enemies and saves", "res://tools/smoke_arsenal_validation_edges.gd"),
        @("Smoke test Boss phases patterns reinforcements and outcomes", "res://tools/smoke_boss_runtime.gd"),
        @("Smoke test Boss and Phase Studio editor state", "res://tools/smoke_boss_studio.gd"),
        @("Smoke test malformed boss arenas phases patterns rewards and reinforcements", "res://tools/smoke_boss_validation_edges.gd"),
        @("Smoke test cinematic playback skip and durable completion", "res://tools/smoke_cinematic_runtime.gd"),
        @("Smoke test Cinematic and Timeline Studio editor state", "res://tools/smoke_cinematic_studio.gd"),
        @("Smoke test malformed cinematic maps steps targets effects and checkpoints", "res://tools/smoke_cinematic_validation_edges.gd"),
        @("Smoke test deterministic campaign packaging and installation", "res://tools/smoke_campaign_packages.gd"),
        @("Smoke test Package and Release Studio editor state", "res://tools/smoke_package_studio.gd"),
        @("Smoke test malformed archive paths scripts and hashes", "res://tools/smoke_package_validation_edges.gd"),
        @("Smoke test hash-valid packages with invalid current content", "res://tools/smoke_package_current_validation.gd"),
        @("Smoke test deterministic campaign production audit", "res://tools/smoke_campaign_audit.gd"),
        @("Smoke test Campaign Audit Studio editor state and export", "res://tools/smoke_campaign_audit_studio.gd"),
        @("Smoke test campaign audit blocker and warning detection", "res://tools/smoke_campaign_audit_edges.gd"),
        @("Smoke test multi-source progression affordability planning", "res://tools/smoke_progression_affordability.gd"),
        @("Smoke test original 16-bit presentation profiles and overlay", "res://tools/smoke_presentation_runtime.gd"),
        @("Smoke test Presentation and Feel Studio editor state", "res://tools/smoke_presentation_studio.gd"),
        @("Smoke test malformed presentation colours camera values atmosphere and bindings", "res://tools/smoke_presentation_validation_edges.gd"),
        @("Smoke test original procedural music ambience and event feedback", "res://tools/smoke_audio_mood_runtime.gd"),
        @("Smoke test Audio and Mood Studio editor state", "res://tools/smoke_audio_mood_studio.gd"),
        @("Smoke test malformed Audio and Mood synthesis ambience and bindings", "res://tools/smoke_audio_mood_validation_edges.gd"),
        @("Smoke test Audio and Mood scaffolding for new campaigns", "res://tools/smoke_audio_campaign_scaffold.gd"),
        @("Smoke test frame-based Sprite Animation runtime", "res://tools/smoke_sprite_animation_runtime.gd"),
        @("Smoke test animated terrain and movement-linked environmental responses", "res://tools/smoke_environment_animation.gd"),
        @("Smoke test projectile boss pause and combat presentation ordering", "res://tools/smoke_combat_readability_overlay.gd"),
        @("Smoke test Sprite and Animation Studio editor state", "res://tools/smoke_sprite_animation_studio.gd"),
        @("Smoke test malformed Sprite Animation profiles atlases and paths", "res://tools/smoke_sprite_animation_validation_edges.gd"),
        @("Smoke test Sprite Animation scaffolding for new campaigns", "res://tools/smoke_sprite_campaign_scaffold.gd"),
        @("Smoke test hash-valid packages with invalid Sprite Animation data", "res://tools/smoke_sprite_package_validation.gd")
    )

    Invoke-GodotStep "Import project" @("--headless", "--path", $ProjectRoot, "--import")
    foreach ($Test in $Tests) {
        Invoke-GodotStep $Test[0] @("--headless", "--path", $ProjectRoot, "--script", $Test[1])
    }
    Write-Host "`nEpochbound project and all seventeen authoring systems passed canonical runtime, player settings, progression-demand, multi-source affordability, sprite-animation, environment and combat-readability validation."
}
finally {
    Pop-Location
}
