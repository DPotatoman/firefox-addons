# Publishes a signed add-on build for Firefox auto-update: copies the .xpi into <Slug>/,
# points the add-on's updates.json entry at it (with its SHA-256), drops older builds
# of that add-on, then commits and pushes. GitHub Pages serves the result.
# usage: publish.ps1 -AddonId <gecko id> -Slug <folder> -Version <x.y.z> -Xpi <signed .xpi>
param(
  [Parameter(Mandatory)] [string] $AddonId,
  [Parameter(Mandatory)] [string] $Slug,
  [Parameter(Mandatory)] [string] $Version,
  [Parameter(Mandatory)] [string] $Xpi
)
$ErrorActionPreference = 'Stop'
$site = $PSScriptRoot
$base = 'https://dpotatoman.github.io/firefox-addons'

$dir = Join-Path $site $Slug
New-Item -ItemType Directory -Force $dir | Out-Null
$name = Split-Path $Xpi -Leaf
Get-ChildItem $dir -File -Filter *.xpi | Where-Object Name -ne $name | Remove-Item
Copy-Item $Xpi (Join-Path $dir $name) -Force
$hash = (Get-FileHash (Join-Path $dir $name) -Algorithm SHA256).Hash.ToLower()

# updates.json is rewritten with node so its formatting stays stable (and BOM-free). The entry
# goes through the environment: PowerShell 5.1 mangles quotes in native-command arguments.
$json = Join-Path $site 'updates.json'
$env:UPDATE_ENTRY = @{ version = $Version; update_link = "$base/$Slug/$name"; update_hash = "sha256:$hash" } | ConvertTo-Json -Compress
& node -e @"
const fs = require('fs');
const file = process.argv[1];
const data = JSON.parse(fs.readFileSync(file, 'utf8'));
data.addons[process.argv[2]] = { updates: [JSON.parse(process.env.UPDATE_ENTRY)] };
fs.writeFileSync(file, JSON.stringify(data, null, 2) + '\n');
"@ $json $AddonId
if ($LASTEXITCODE -ne 0) { throw 'Could not update updates.json' }

Push-Location $site
try {
  git add -A
  git commit -q -m "$Slug $Version"
  git push -q origin HEAD:main
  if ($LASTEXITCODE -ne 0) { throw "git push failed (exit $LASTEXITCODE). Does github.com/DPotatoman/firefox-addons exist?" }
  "Published $Slug $Version to $base/$Slug/$name (Firefox picks it up within a day)"
} finally { Pop-Location }
