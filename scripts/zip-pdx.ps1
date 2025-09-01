# zip-pdx.ps1

# Get game name from pdxinfo
$name = (Get-Content source/pdxinfo | Select-String "^name=").ToString().Split("=")[1].Trim()

# Build paths
$src = "builds/$name.pdx"
$dst = "builds/$name.pdx.zip"

# Ensure source exists
if (-not (Test-Path $src)) {
    throw "PDX folder not found: $src"
}

# Remove existing zip if necessary
if (Test-Path $dst) {
    Remove-Item $dst -Force
}

# Create archive
#Compress-Archive -Path $src -DestinationPath $dst -Force

# Create archive with tar
# -a : choose format based on extension (.zip → zip format)
# -c : create new archive
# -f : specify archive file
# -C : change directory so that $src folder is top-level in the archive
tar -a -cf $dst -C (Split-Path $src -Parent) (Split-Path $src -Leaf)

Write-Output "Created: $dst"
