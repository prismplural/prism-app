param(
  [string]$BundleDir = "build\windows\x64\runner\Release",
  [string]$OutputDir = "dist",
  [string]$VCRedistPath = $env:PRISM_VC_REDIST_X64_PATH,
  [string]$VCRedistUrl = $env:PRISM_VC_REDIST_X64_URL
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

if ([string]::IsNullOrWhiteSpace($VCRedistUrl)) {
  $VCRedistUrl = "https://aka.ms/vc14/vc_redist.x64.exe"
}

$redistDir = Join-Path $repoRoot "build\windows\redist"
New-Item -ItemType Directory -Force $redistDir | Out-Null
$vcRedistInstallerPath = Join-Path $redistDir "vc_redist.x64.exe"

if ([string]::IsNullOrWhiteSpace($VCRedistPath)) {
  $VCRedistPath = $vcRedistInstallerPath
  Write-Host "Downloading Microsoft Visual C++ Redistributable from $VCRedistUrl"
  Invoke-WebRequest -Uri $VCRedistUrl -OutFile $VCRedistPath -UseBasicParsing
} else {
  if (-not [System.IO.Path]::IsPathRooted($VCRedistPath)) {
    $VCRedistPath = Join-Path $repoRoot $VCRedistPath
  }
  $VCRedistPath = (Resolve-Path -LiteralPath $VCRedistPath).ProviderPath
}

if (-not (Test-Path -LiteralPath $VCRedistPath)) {
  throw "Visual C++ Redistributable not found at $VCRedistPath"
}

if (-not [StringComparer]::OrdinalIgnoreCase.Equals(
    [System.IO.Path]::GetFullPath($VCRedistPath),
    [System.IO.Path]::GetFullPath($vcRedistInstallerPath))) {
  Copy-Item -LiteralPath $VCRedistPath -Destination $vcRedistInstallerPath -Force
  $VCRedistPath = $vcRedistInstallerPath
}

$vcRedistVersionInfo = (Get-Item -LiteralPath $VCRedistPath).VersionInfo
$vcRedistVersionParts = @(
  $vcRedistVersionInfo.FileMajorPart,
  $vcRedistVersionInfo.FileMinorPart,
  $vcRedistVersionInfo.FileBuildPart,
  $vcRedistVersionInfo.FilePrivatePart
)
if ($vcRedistVersionParts[0] -le 0) {
  throw "Could not read Visual C++ Redistributable file version from $VCRedistPath"
}
$vcRedistVersion = $vcRedistVersionParts -join "."
Write-Host "Bundling Microsoft Visual C++ Redistributable x64 $vcRedistVersion"

$zip = Join-Path $outputPath "Prism-$version-windows-x64-portable.zip"
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
  "/DOutputDir=$outputPath",
  "/DVCRedistPath=$VCRedistPath",
  "/DVCRedistMajor=$($vcRedistVersionParts[0])",
  "/DVCRedistMinor=$($vcRedistVersionParts[1])",
  "/DVCRedistBld=$($vcRedistVersionParts[2])",
  "/DVCRedistRbld=$($vcRedistVersionParts[3])"
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

$setup = Join-Path $outputPath "Prism-$version-windows-x64-install.exe"
if (-not (Test-Path -LiteralPath $setup)) {
  throw "Expected installer was not created: $setup"
}
$setupHash = (Get-FileHash -Algorithm SHA256 $setup).Hash.ToLower()
"$setupHash  $(Split-Path $setup -Leaf)" | Out-File -Encoding ascii "$setup.sha256"

Get-ChildItem -LiteralPath $outputPath
