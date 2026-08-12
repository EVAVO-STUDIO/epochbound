param(
    [string]$GodotExecutable = "godot"
)

$ErrorActionPreference = "Stop"
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

function Get-TrackedDiffFingerprint {
    $diffOutput = & git diff --binary --no-ext-diff -- . 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to inspect tracked source changes."
    }
    $diffText = $diffOutput -join "`n"
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($diffText)
    $hasher = [System.Security.Cryptography.SHA256]::Create()
    try {
        return [Convert]::ToHexString($hasher.ComputeHash($bytes))
    }
    finally {
        $hasher.Dispose()
    }
}

function Assert-TrackedSourcesUnchanged {
    param(
        [Parameter(Mandatory = $true)] [string]$BaselineFingerprint,
        [Parameter(Mandatory = $true)] [string]$Description
    )
    $currentFingerprint = Get-TrackedDiffFingerprint
    if ($currentFingerprint -eq $BaselineFingerprint) {
        return
    }
    Write-Host "`nTracked source changed during: $Description"
    & git diff --stat -- . | ForEach-Object { Write-Host $_ }
    & git diff --name-only -- . | ForEach-Object { Write-Host " - $_" }
    throw "$Description modified tracked source files. Validation tests must restore exact source bytes."
}

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
    if ($combined -match "Trying to access a non-existing editor theme icon") {
        throw "$Description requested an editor icon that does not exist in the active Godot theme."
    }
    if ($combined -match "ObjectDB instances leaked at exit") {
        throw "$Description leaked Godot ObjectDB instances during headless shutdown."
    }
}

Push-Location $ProjectRoot
try {
    Write-Host "`n==> Validate Archive Hideaway live runtime contract"
    & python3 tools/check_hideaway_runtime_contract.py
    if ($LASTEXITCODE -ne 0) { throw "Archive Hideaway live runtime contract failed." }

    $Tests = @(
        @("Compile runtime scenes and editor plugins", "res://tools/compile_probe.gd"),
        @("Smoke test warning-safe editor plugin icon resolution", "res://tools/smoke_editor_plugin_icons.gd"),
        @("Compile Sprite Animation runtime editors and tests", "res://tools/compile_sprite_animation_probe.gd"),
        @("Compile player settings controls storage presentation and tests", "res://tools/compile_player_settings_probe.gd"),
        @("Compile strict localisation catalogues runtime and tests", "res://tools/compile_localisation_probe.gd"),
        @("Compile deterministic localisation layout utility and regressions", "res://tools/compile_localisation_layout_probe.gd"),
        @("Compile Archive Hideaway live runtime bridge", "res://tools/compile_hideaway_runtime_probe.gd"),
        @("Smoke test Archive Hideaway stewardship foundation", "res://tools/smoke_hideaway_stewardship.gd"),
        @("Smoke test playable Archive Hideaway refuge loop", "res://tools/smoke_hideaway_runtime.gd"),
        @("Compile regional supply runtime validators editors and tests", "res://tools/compile_supply_region_probe.gd"),
        @("Compile host-authoritative co-op PvP runtime validators and tests", "res://tools/compile_multiplayer_probe.gd"),
        @("Smoke test canonical runtime scene composition", "res://tools/smoke_runtime_scene_contract.gd"),
        @("Smoke test persistent player settings and accessibility", "res://tools/smoke_player_settings.gd"),
        @("Smoke test player settings crash recovery and modal freeze edges", "res://tools/smoke_player_settings_recovery_edges.gd"),
        @("Smoke test persistent keyboard and controller remapping", "res://tools/smoke_input_bindings.gd"),
        @("Smoke test strict localisation fallback pseudo locale and runtime switching", "res://tools/smoke_localisation.gd"),
        @("Smoke test fixed-viewport localisation layout safety", "res://tools/smoke_localisation_layout.gd"),
        @("Validate campaign content", "res://tools/validate_content.gd"),
        @("Run deterministic campaign production audit", "res://tools/audit_campaigns.gd"),
        @("Smoke test meaningful temporal shift consequences", "res://tools/smoke_temporal_shift_audit.gd"),
        @("Smoke test deterministic co-op and invasion session model", "res://tools/smoke_multiplayer_session_model.gd"),
        @("Smoke test player-local multiplayer connection setup and recovery", "res://tools/smoke_multiplayer_connection_profile.gd"),
        @("Smoke test bounded multiplayer snapshot transport across every map and era", "res://tools/smoke_multiplayer_snapshot_transport.gd"),
        @("Smoke test host-authoritative co-op PvP runtime and snapshots", "res://tools/smoke_multiplayer_runtime.gd"),
        @("Smoke test bounded unexpected-host restart recovery", "res://tools/smoke_multiplayer_host_restart_recovery.gd"),
        @("Smoke test malformed online policies areas and save isolation", "res://tools/smoke_multiplayer_validation_edges.gd"),
        @("Smoke test canonical long-form reference journey", "res://tools/smoke_canonical_journey.gd"),
        @("Smoke test repeated long-form progression endurance", "res://tools/smoke_long_form_progression.gd"),
        @("Smoke test world model and traversal", "res://tools/smoke_world_model.gd"),
        @("Smoke test Encounter Studio and base combat", "res://tools/smoke_encounters.gd"),
        @("Smoke test Combat Director target locking stagger interrupts and pressure budget", "res://tools/smoke_combat_director.gd"),
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
        @("Smoke test Merchant Economy and Supply Studio editor state", "res://tools/smoke_trade_studio.gd"),
        @("Smoke test malformed currencies merchants stock and economy saves", "res://tools/smoke_economy_validation_edges.gd"),
        @("Smoke test deterministic regional supply scarcity catch-up and saves", "res://tools/smoke_supply_regions.gd"),
        @("Smoke test malformed supply routes replenishment and saved cycles", "res://tools/smoke_supply_validation_edges.gd"),
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
        @("Smoke test warning-free reference campaign release readiness", "res://tools/smoke_campaign_audit.gd"),
        @("Smoke test Campaign Audit Studio editor state and export", "res://tools/smoke_campaign_audit_studio.gd"),
        @("Smoke test campaign audit blocker and warning detection", "res://tools/smoke_campaign_audit_edges.gd"),
        @("Smoke test multi-source progression affordability planning", "res://tools/smoke_progression_affordability.gd"),
        @("Smoke test deterministic economy balance simulation", "res://tools/smoke_economy_balance_simulation.gd"),
        @("Smoke test original 16-bit presentation profiles and overlay", "res://tools/smoke_presentation_runtime.gd"),
        @("Smoke test Presentation and Feel Studio editor state", "res://tools/smoke_presentation_studio.gd"),
        @("Smoke test malformed presentation colours camera values atmosphere and bindings", "res://tools/smoke_presentation_validation_edges.gd"),
        @("Smoke test original procedural music ambience and event feedback", "res://tools/smoke_audio_mood_runtime.gd"),
        @("Smoke test authored boss phase music stems", "res://tools/smoke_boss_music_stems.gd"),
        @("Smoke test Audio and Mood Studio editor state", "res://tools/smoke_audio_mood_studio.gd"),
        @("Smoke test malformed Audio and Mood synthesis ambience and bindings", "res://tools/smoke_audio_mood_validation_edges.gd"),
        @("Smoke test Audio and Mood scaffolding for new campaigns", "res://tools/smoke_audio_campaign_scaffold.gd"),
        @("Smoke test frame-based Sprite Animation runtime", "res://tools/smoke_sprite_animation_runtime.gd"),
        @("Smoke test animated terrain and movement-linked environmental responses", "res://tools/smoke_environment_animation.gd"),
        @("Smoke test projectile boss pause control hints and combat presentation ordering", "res://tools/smoke_combat_readability_overlay.gd"),
        @("Smoke test Sprite and Animation Studio editor state", "res://tools/smoke_sprite_animation_studio.gd"),
        @("Smoke test malformed Sprite Animation profiles atlases and paths", "res://tools/smoke_sprite_animation_validation_edges.gd"),
        @("Smoke test Sprite Animation scaffolding for new campaigns", "res://tools/smoke_sprite_campaign_scaffold.gd"),
        @("Smoke test hash-valid packages with invalid Sprite Animation data", "res://tools/smoke_sprite_package_validation.gd")
    )

    $TrackedSourceBaseline = Get-TrackedDiffFingerprint
    Invoke-GodotStep "Import project" @("--headless", "--path", $ProjectRoot, "--import")
    Assert-TrackedSourcesUnchanged $TrackedSourceBaseline "Import project"
    foreach ($Test in $Tests) {
        Invoke-GodotStep $Test[0] @("--headless", "--path", $ProjectRoot, "--script", $Test[1])
        Assert-TrackedSourcesUnchanged $TrackedSourceBaseline $Test[0]
    }
    Write-Host "`nEpochbound project and all seventeen authoring systems passed canonical runtime, long-form journey, repeated progression endurance with thirty-two map transitions and four destructive restorations, host-authoritative co-op, authored PvP invasions, player-local connection setup, bounded authenticated snapshot transport, acknowledged host shutdown with independent ENet process exit, player settings, persistent controls, strict localisation with English fallback and pseudo-localisation, measured localisation layout with deterministic wrapping and ellipsis, progression-demand, warning-free reference release readiness, warning-safe editor plugin icons, leak-free headless shutdown, meaningful temporal shifts, locked combat telegraphs, stagger interrupts, ordinary-enemy pressure budget, boss phase music stems, multi-source affordability, deterministic economy balance with Economy choices 4/4 recovery-safe, Archive Hideaway expedition stewardship, regional supply, scarcity, sprite-animation, environment and combat-readability validation without mutating tracked source."
}
finally {
    Pop-Location
}
