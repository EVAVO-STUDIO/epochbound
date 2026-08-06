# Headless Runtime Cleanup Contract

Epochbound's executable smoke tests instantiate the complete playable scene, including three procedural `AudioStreamGenerator` players for Music, Ambience, and SFX. Godot releases each `AudioStreamGeneratorPlayback` asynchronously after its owning player is stopped and freed. Exiting a headless test immediately after `runtime.free()` can therefore report `ObjectDB instances leaked at exit` even though the runtime node left the scene tree.

The supported cleanup boundary is `tools/headless_runtime_cleanup.gd`. Full-scene tests must call:

```gdscript
await HeadlessRuntimeCleanup.release(self, runtime)
```

The helper performs a bounded sequence:

1. Stop processing on the `AudioMood` controller.
2. Stop, pause, and detach the Music, Ambience, and SFX streams without calling `clear_buffer()` on an active playback.
3. Remove and free the complete runtime tree.
4. Hold a fixed 30-frame settling window, a 0.25-second SceneTree timer, and two final frames so Godot's audio server can release playback references before process shutdown.

This delay exists only in the headless test harness. It does not change gameplay timing, save data, networking, package contents, or release runtime behaviour.

## Fail-closed release policy

- All full-scene smoke tests preload the shared cleanup helper.
- Static validation pins the expected cleanup entrypoints and forbids the old direct-success-path disposal pattern.
- `scripts/validate.ps1` fails when any Godot step logs `ObjectDB instances leaked at exit`.
- The complete compile probe loads the cleanup helper directly.
- Exact-main validation records `headlessCleanupValidation: passed` in the bounded schema-2.1 receipt.

New full-runtime smoke tests must use the same helper rather than adding arbitrary sleeps, suppressing warnings, or clearing active generator buffers.
