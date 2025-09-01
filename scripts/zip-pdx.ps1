# zip-pdx.ps1

# Get game name from pdxinfo
$name = (Get-Content source/pdxinfo | Select-String "^name=").ToString().Split("=")[1].Trim()

# Build paths
$src = "builds/$name.pdx"
$dst = "builds/$name.zip"

# Ensure source exists
if (-not (Test-Path $src)) {
    throw "PDX folder not found: $src"
}

# Remove existing zip if necessary
if (Test-Path $dst) {
    Remove-Item $dst -Force
}

# Create archive
Compress-Archive -Path $src -DestinationPath $dst -Force

Write-Output "Created: $dst"
