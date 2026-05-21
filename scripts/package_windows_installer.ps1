param(
  [string]$BundleDir = "build\windows\x64\runner\Release",
  [string]$OutputDir = "dist"
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$bundlePath = Resolve-Path (Join-Path $repoRoot $BundleDir)
$outputPath = Join-Path $repoRoot $OutputDir
$pubspecPath = Join-Path $repoRoot "pubspec.yaml"

$versionMatch = Select-String -Path $pubspecPath -Pattern '^version:\s*(\S+)'
if (-not $versionMatch) {
  throw "Could not read version from $pubspecPath"
}
$version = $versionMatch.Matches[0].Groups[1].Value
$versionInfo = "0.0.0.0"
if ($version -match '^(\d+)\.(\d+)\.(\d+)\+(\d+)$') {
  $versionInfo = "$($Matches[1]).$($Matches[2]).$($Matches[3]).$($Matches[4])"
} elseif ($version -match '^(\d+)\.(\d+)\.(\d+)$') {
  $versionInfo = "$($Matches[1]).$($Matches[2]).$($Matches[3]).0"
}

$exePath = Join-Path $bundlePath "prism_plurality.exe"
if (-not (Test-Path -LiteralPath $exePath)) {
  throw "Windows release bundle is missing $exePath. Run flutter build windows --release first."
}

New-Item -ItemType Directory -Force $outputPath | Out-Null

$zip = Join-Path $outputPath "Prism-$version-windows-x64.zip"
if (Test-Path -LiteralPath $zip) {
  Remove-Item -LiteralPath $zip -Force
}
Compress-Archive -Path (Join-Path $bundlePath "*") -DestinationPath $zip -CompressionLevel Optimal
$zipHash = (Get-FileHash -Algorithm SHA256 $zip).Hash.ToLower()
"$zipHash  $(Split-Path $zip -Leaf)" | Out-File -Encoding ascii "$zip.sha256"

$iscc = $env:INNO_SETUP_ISCC
if ([string]::IsNullOrWhiteSpace($iscc)) {
  $defaultIscc = "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe"
  if (Test-Path -LiteralPath $defaultIscc) {
    $iscc = $defaultIscc
  } else {
    $innoRoots = @()
    if (-not [string]::IsNullOrWhiteSpace(${env:ProgramFiles(x86)})) {
      $innoRoots += ${env:ProgramFiles(x86)}
    }
    if (-not [string]::IsNullOrWhiteSpace($env:ProgramFiles)) {
      $innoRoots += $env:ProgramFiles
    }
    $discoveredIscc = $innoRoots |
      ForEach-Object { Get-ChildItem -Path $_ -Directory -Filter "Inno Setup *" -ErrorAction SilentlyContinue } |
      ForEach-Object { Join-Path $_.FullName "ISCC.exe" } |
      Where-Object { Test-Path -LiteralPath $_ } |
      Select-Object -First 1
    $iscc = if ($discoveredIscc) { $discoveredIscc } else { "ISCC.exe" }
  }
}

$iss = Join-Path $repoRoot "packaging\windows\prism.iss"
$isccArgs = @(
  $iss,
  "/DAppVersion=$version",
  "/DAppVersionInfo=$versionInfo",
  "/DBundleDir=$bundlePath",
  "/DOutputDir=$outputPath"
)

$signToolName = $env:PRISM_INNO_SIGNTOOL_NAME
$signToolCommand = $env:PRISM_INNO_SIGNTOOL_COMMAND
if ([string]::IsNullOrWhiteSpace($signToolName) -xor [string]::IsNullOrWhiteSpace($signToolCommand)) {
  throw "Set both PRISM_INNO_SIGNTOOL_NAME and PRISM_INNO_SIGNTOOL_COMMAND, or neither."
}
if (-not [string]::IsNullOrWhiteSpace($signToolName)) {
  $isccArgs += "/DSignToolName=$signToolName"
  $isccArgs += "/S$signToolName=$signToolCommand"
}

& $iscc @isccArgs
if ($LASTEXITCODE -ne 0) {
  throw "Inno Setup compiler failed with exit code $LASTEXITCODE"
}

$setup = Join-Path $outputPath "Prism-$version-windows-x64-setup.exe"
if (-not (Test-Path -LiteralPath $setup)) {
  throw "Expected installer was not created: $setup"
}
$setupHash = (Get-FileHash -Algorithm SHA256 $setup).Hash.ToLower()
"$setupHash  $(Split-Path $setup -Leaf)" | Out-File -Encoding ascii "$setup.sha256"

Get-ChildItem -LiteralPath $outputPath
