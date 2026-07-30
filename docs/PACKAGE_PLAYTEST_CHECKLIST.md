# Package & Release Manual Playtest Checklist

## Export

- Open the Package tab and select each source campaign.
- Confirm release metadata loads without changing existing values.
- Reject malformed semantic versions, blank licences and invalid package names.
- Export the same unchanged campaign twice and confirm identical SHA-256 values.
- Confirm the output filename contains package name and version.
- Confirm exported packages appear in the editor list.

## Inspection

- Inspect a valid package and review title, version, file count and size.
- Confirm a truncated ZIP is rejected.
- Confirm modified hashes, undeclared entries and missing entries are rejected.
- Confirm case collisions, traversal paths, scripts and native libraries are rejected.

## Installation

- Install a valid custom campaign and launch it from the campaign browser.
- Attempt installation again without replacement and confirm refusal.
- Enable replacement and confirm the validated replacement succeeds.
- Force a failed promotion and confirm the existing campaign is restored.
- Confirm a package cannot shadow a built-in campaign ID.
- Confirm staging and backup directories do not remain after success.

## Cross-platform

- Export and inspect on Windows.
- Inspect the same package in Linux CI.
- Confirm archive paths use forward slashes.
- Confirm filename casing and expanded-size limits behave consistently.

## Regression

```powershell
.\scripts\validate.ps1 -GodotExecutable "C:\Path\To\Godot_v4.6.2-stable_win64.exe"
```

Confirm package runtime, editor and malformed-archive tests pass alongside the inherited gameplay suite.
