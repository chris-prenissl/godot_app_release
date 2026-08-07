# Export a Godot project and ship the artifact with fastlane. Windows twin of
# release.sh, covering the Android targets only — iOS needs macOS and Xcode.
# Run with -Help for the full description.
#
# NOTE: this script is provided untested — the plugin is developed on macOS.
# Please report problems at the repository listed in plugin.cfg.

[CmdletBinding(DefaultParameterSetName = "Run")]
param(
    [Parameter(ParameterSetName = "Run", Mandatory = $true, Position = 0)][string]$EnvFile,
    [Parameter(ParameterSetName = "Run", Position = 1)][string]$LogPath,
    [Parameter(ParameterSetName = "Help", Mandatory = $true)][switch]$Help
)

$ErrorActionPreference = "Stop"
$script:LockDir = $null
$script:LockHeld = $false

function Show-Usage {
    @'
release.ps1 — export a Godot project and ship the artifact with fastlane.
Windows twin of release.sh; Android targets only, since iOS needs macOS and Xcode.

USAGE
  powershell -ExecutionPolicy Bypass -File release.ps1 <run.env path> [log path]
  powershell -ExecutionPolicy Bypass -File release.ps1 -Help

ARGUMENTS
  <run.env path>   Required. The generated environment file describing one run.
  [log path]       Optional. Where to write the log. Defaults to
                   <project>\<LOGS_DIR>\release_<TARGET_ID>_<timestamp>.log

DESCRIPTION
  Everything this script needs comes from the run.env file, so there are no
  project-specific constants in here. The App Release plugin writes that file
  into <project>\.release_tools\ each time you confirm a release in the editor,
  which means running this by hand repeats the last release the panel set up.

  The version name and build number are patched into export_presets.cfg by the
  plugin before this script starts, so editing VERSION or BUILD in run.env
  changes what fastlane reports but NOT what Godot actually exports.

  iOS targets are refused here. Run those from a Mac with Xcode installed.

BUILD MODES  (BUILD_MODE in run.env)
  GODOT_EXPORT               Godot produces the final artifact.
  REGENERATE_NATIVE_PROJECT  Reinstall the Android build template, then export.
  PCK_ONLY                   Refresh only the PCK, then build the existing
                             Gradle project with gradlew.

EXIT STATUS
  0   success
  1   a phase failed, or the run was rejected (iOS target, lock already held)

  The status is also written to "<log path>.exit" on every exit path; the
  editor panel polls for that file to decide when the run is over.

FILES
  <project>\.release_tools\run.env   this script's only input
  <project>\<LOGS_DIR>\              logs, plus the .release.lock directory
  <project>\fastlane\                Gemfile and lanes used by the upload step

EXAMPLE
  powershell -ExecutionPolicy Bypass -File addons\app_release\scripts\release.ps1 `
      .release_tools\run.env logs\manual.log
'@ | Write-Output
}

function Write-Log([string]$Message) {
    Write-Output $Message
    if ($script:LogPath) { Add-Content -LiteralPath $script:LogPath -Value $Message }
}

function Stop-WithError([string]$Message) {
    Write-Log "ERROR: $Message"
    throw $Message
}

function Import-RunEnv([string]$Path) {
    $values = @{}
    foreach ($line in Get-Content -LiteralPath $Path) {
        if ($line -match '^\s*#' -or $line -notmatch '=') { continue }
        $key, $raw = $line -split '=', 2
        $raw = $raw.Trim()
        if ($raw.StartsWith('"') -and $raw.EndsWith('"')) {
            $raw = $raw.Substring(1, $raw.Length - 2)
        }
        $raw = $raw -replace '\\(["$`\\])', '$1'
        $values[$key.Trim()] = $raw
    }
    return $values
}

function Get-Required([hashtable]$Values, [string]$Key) {
    $value = $Values[$Key]
    if ([string]::IsNullOrWhiteSpace($value)) {
        Stop-WithError "$Key is not set in $EnvFile. Check the target's configuration in release_config.tres."
    }
    return $value
}

if ($Help -or $EnvFile -in @('-h', '--help', '-?', '/?')) {
    Show-Usage
    exit 0
}

$exitCode = 1
try {
    $env_ = Import-RunEnv $EnvFile
    foreach ($key in $env_.Keys) { Set-Item -Path "env:$key" -Value $env_[$key] }

    $root = Get-Required $env_ "PROJECT_ROOT"
    $targetId = Get-Required $env_ "TARGET_ID"
    $platform = Get-Required $env_ "PLATFORM"
    $lane = Get-Required $env_ "LANE"
    $preset = Get-Required $env_ "EXPORT_PRESET"
    $buildMode = Get-Required $env_ "BUILD_MODE"
    $artifactRel = Get-Required $env_ "ARTIFACT_PATH"
    $version = Get-Required $env_ "VERSION"
    $build = Get-Required $env_ "BUILD"

    if ($platform -eq "ios") {
        Stop-WithError "iOS releases require macOS with Xcode installed. Android targets do run on this machine."
    }

    if ($env_["EXTRA_PATH"]) { $env:PATH = $env_["EXTRA_PATH"] }

    $logsDir = if ($env_["LOGS_DIR"]) { $env_["LOGS_DIR"] } else { "logs" }
    $logsRoot = Join-Path $root $logsDir
    New-Item -ItemType Directory -Force -Path $logsRoot | Out-Null
    if (-not $LogPath) {
        $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $LogPath = Join-Path $logsRoot "release_${targetId}_$stamp.log"
    }
    $script:LogPath = $LogPath
    Remove-Item -LiteralPath "$LogPath.exit" -ErrorAction SilentlyContinue

    $script:LockDir = Join-Path $logsRoot ".release.lock"
    if (Test-Path -LiteralPath $script:LockDir) {
        $lockPid = Get-Content -LiteralPath (Join-Path $script:LockDir "pid") -ErrorAction SilentlyContinue
        if ($lockPid -and (Get-Process -Id $lockPid -ErrorAction SilentlyContinue)) {
            Stop-WithError "another release is already running (pid $lockPid). Wait for it, or stop it from the Godot Release panel."
        }
        Write-Log "Removing stale lock from pid $lockPid"
        Remove-Item -LiteralPath $script:LockDir -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path $script:LockDir | Out-Null
    Set-Content -LiteralPath (Join-Path $script:LockDir "pid") -Value $PID
    $script:LockHeld = $true

    Write-Log "=== RELEASE $targetId STARTED $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ==="
    Write-Log "Project:    $root"
    Write-Log "Target:     $($env_['TARGET_LABEL']) ($($env_['STORE']))"
    Write-Log "Preset:     $preset [$platform]"
    Write-Log "Build mode: $buildMode"
    Write-Log "Version:    $version (build $build)"

    $debugBuild = $env_["DEBUG_BUILD"] -eq "1"
    Write-Log $(if ($debugBuild) { "Build type: debug" } else { "Build type: release" })

    $notesFile = $env_["RELEASE_NOTES_FILE"]
    if ($notesFile -and (Test-Path -LiteralPath $notesFile)) {
        Write-Log "Release notes ($notesFile):"
        Get-Content -LiteralPath $notesFile | ForEach-Object { Write-Log "  | $_" }
        if ($env_["PLAY_CHANGELOGS_DIR"]) {
            $changelogs = Join-Path $root $env_["PLAY_CHANGELOGS_DIR"]
            New-Item -ItemType Directory -Force -Path $changelogs | Out-Null
            Copy-Item -LiteralPath $notesFile -Destination (Join-Path $changelogs "$build.txt") -Force
        }
        if ($env_["RELEASE_NOTES_DIR"]) {
            $archive = Join-Path $root $env_["RELEASE_NOTES_DIR"]
            New-Item -ItemType Directory -Force -Path $archive | Out-Null
            $body = "# $version (build $build)`n`n" + (Get-Content -LiteralPath $notesFile -Raw) + "`n"
            Set-Content -LiteralPath (Join-Path $archive "$version-$build.md") -Value $body
            Write-Log "Notes archived: $($env_['RELEASE_NOTES_DIR'])\$version-$build.md"
        }
    }

    $godot = $env_["GODOT_BIN"]
    if (-not $godot) { Stop-WithError "GODOT_BIN is not set. Set a Godot binary override in release_config.tres." }
    Write-Log "Godot: $godot"

    $artifact = Join-Path $root $artifactRel
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $artifact) | Out-Null
    $exportFlag = if ($debugBuild) { "--export-debug" } else { "--export-release" }

    switch ($buildMode) {
        "REGENERATE_NATIVE_PROJECT" {
            Write-Log "Reinstalling the Android build template"
            & $godot --headless --path $root --install-android-build-template 2>&1 | ForEach-Object { Write-Log $_ }
            if ($LASTEXITCODE -ne 0) { Stop-WithError "installing the Android build template failed ($LASTEXITCODE)" }
        }
        "PCK_ONLY" {
            $pck = Join-Path $root (Get-Required $env_ "PCK_PATH")
            $nativeProject = Join-Path $root (Get-Required $env_ "NATIVE_PROJECT_PATH")
            $gradleTask = Get-Required $env_ "GRADLE_TASK"

            Write-Log "Exporting pack only -> $($env_['PCK_PATH'])"
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $pck) | Out-Null
            & $godot --headless --path $root --export-pack $preset $pck 2>&1 | ForEach-Object { Write-Log $_ }
            if ($LASTEXITCODE -ne 0) { Stop-WithError "the Godot pack export failed ($LASTEXITCODE)" }

            if (-not (Test-Path -LiteralPath (Join-Path $nativeProject "gradlew.bat"))) {
                Stop-WithError "no gradlew.bat in $nativeProject. Install the Android build template from the Godot editor."
            }
            Write-Log "gradlew $gradleTask"
            Push-Location $nativeProject
            try {
                & ".\gradlew.bat" $gradleTask 2>&1 | ForEach-Object { Write-Log $_ }
                if ($LASTEXITCODE -ne 0) { Stop-WithError "gradle failed ($LASTEXITCODE)" }
            } finally { Pop-Location }

            $extension = [System.IO.Path]::GetExtension($artifactRel)
            $built = Get-ChildItem -Path (Join-Path $nativeProject "build\outputs") -Filter "*$extension" -Recurse -File |
                Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if (-not $built) { Stop-WithError "gradle produced no *$extension under $nativeProject\build\outputs" }
            Write-Log "Gradle output: $($built.FullName)"
            Copy-Item -LiteralPath $built.FullName -Destination $artifact -Force
        }
    }

    if ($buildMode -ne "PCK_ONLY") {
        Write-Log "Exporting preset `"$preset`" ($exportFlag) -> $artifactRel"
        & $godot --headless --path $root $exportFlag $preset $artifact 2>&1 | ForEach-Object { Write-Log $_ }
        if ($LASTEXITCODE -ne 0) { Stop-WithError "the Godot export failed ($LASTEXITCODE)" }
    }

    if (-not (Test-Path -LiteralPath $artifact)) {
        Stop-WithError "expected artifact missing after export: $artifact"
    }
    Write-Log "Export done: $artifact ($([math]::Round((Get-Item $artifact).Length / 1MB, 1)) MB)"

    $env:ARTIFACT_PATH_ABS = $artifact

    switch ([System.IO.Path]::GetExtension($artifact)) {
        ".apk" { $env:APK_PATH = $artifact }
        ".aab" { $env:AAB_PATH = $artifact }
    }

    Push-Location $root
    try {
        if (-not (Test-Path -LiteralPath "Gemfile")) {
            Stop-WithError "no Gemfile in $root. Press `"Install release scripts`" in the Release panel's Setup tab."
        }
        & bundle check 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Log "Installing ruby gems (bundle install)..."
            & bundle install 2>&1 | ForEach-Object { Write-Log $_ }
            if ($LASTEXITCODE -ne 0) { Stop-WithError "bundle install failed ($LASTEXITCODE)" }
        }
        Write-Log "Running fastlane $platform $lane"
        & bundle exec fastlane $platform $lane 2>&1 | ForEach-Object { Write-Log $_ }
        if ($LASTEXITCODE -ne 0) { Stop-WithError "fastlane failed ($LASTEXITCODE)" }
    } finally { Pop-Location }

    $exitCode = 0
} catch {
    $exitCode = 1
    if ($script:LogPath) { Add-Content -LiteralPath $script:LogPath -Value $_.Exception.Message }
} finally {
    if ($script:LockHeld -and $script:LockDir) {
        Remove-Item -LiteralPath $script:LockDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    $stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $verdict = if ($exitCode -eq 0) { "SUCCEEDED $stamp" } else { "FAILED (exit $exitCode) $stamp" }
    if ($script:LogPath) {
        Add-Content -LiteralPath $script:LogPath -Value "=== RELEASE $($env:TARGET_ID) $verdict ==="
        Add-Content -LiteralPath $script:LogPath -Value "Log: $script:LogPath"
        Set-Content -LiteralPath "$script:LogPath.exit" -Value $exitCode
    }
    exit $exitCode
}
