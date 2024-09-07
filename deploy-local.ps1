# Load .env file into environment variables
$envFile = ".env"
if (!(Test-Path $envFile)) {
    Write-Host "No .env file found. Exiting..."
    exit 1
}

# Read each line of the .env file and set it as an environment variable
Get-Content $envFile | ForEach-Object {
    if ($_ -match '^\s*([a-zA-Z_]+)\s*=\s*"?([^"]+)"?\s*$') {
        [System.Environment]::SetEnvironmentVariable($matches[1], $matches[2])
    }
}

# Now you can access the LOCAL_DEST_PATH and ZIP_NAME environment variables directly
$localDestPath = $env:LOCAL_DEST_PATH
$zipName = $env:ZIP_NAME

if (-not $localDestPath) {
    Write-Host "LOCAL_DEST_PATH is not set or missing in the .env file. Exiting..."
    exit 1
}

# If ZIP_NAME is defined, use it; otherwise, use the current folder name
if (-not $zipName) {
    $folderName = Split-Path -Leaf (Get-Location)
    $zipName = "$folderName.zip"
} else {
    # Check if ZIP_NAME already ends with .zip, if not, add .zip extension
    if (-not $zipName.EndsWith(".zip")) {
        $zipName = "$zipName.zip"
    }
}

# Full zip file path in the current directory
$zipPath = "$($pwd.Path)\$zipName"

# Check if the zip file already exists and delete it if necessary
if (Test-Path $zipPath) {
    Write-Host "Zip file $zipPath already exists. Deleting it..."
    Remove-Item $zipPath -Force
}

# Zip the folder excluding hidden files and folders
function Add-Zip {
    param (
        [string]$sourcePath,
        [string]$zipPath,
        [array]$includeItems
    )
    Add-Type -Assembly "System.IO.Compression.FileSystem"

    # Create a temporary directory for zipping the filtered files
    $tempDir = New-TemporaryFile | Remove-Item -Force -Confirm:$false
    $tempDir = [System.IO.Path]::GetTempPath() + [System.IO.Path]::GetRandomFileName()
    New-Item -ItemType Directory -Path $tempDir | Out-Null

    # Copy filtered files and folders to temp directory
    foreach ($item in $includeItems) {
        $destination = Join-Path -Path $tempDir -ChildPath ($item.FullName.Substring($sourcePath.Length + 1))
        $destinationDir = Split-Path $destination -Parent
        if (!(Test-Path $destinationDir)) {
            New-Item -ItemType Directory -Path $destinationDir | Out-Null
        }
        Copy-Item $item.FullName -Destination $destination -Recurse
    }

    # Create zip from temp directory
    [System.IO.Compression.ZipFile]::CreateFromDirectory($tempDir, $zipPath, [System.IO.Compression.CompressionLevel]::Optimal, $false)

    # Cleanup
    Remove-Item $tempDir -Recurse -Force
}

$sourcePath = (Get-Location).Path

# Get all files and folders excluding those that start with "." (dot)
$itemsToInclude = Get-ChildItem -Recurse | Where-Object { 
    -not ($_.Name -like '.*') -and -not ($_.FullName -match '\\\..*') 
}

# Compress only non-hidden files and folders
Add-Zip -sourcePath $sourcePath -zipPath $zipPath -includeItems $itemsToInclude

# Check if destination path exists
if (!(Test-Path $localDestPath)) {
    Write-Host "The destination path $localDestPath does not exist. Creating it..."
    New-Item -ItemType Directory -Path $localDestPath -Force
}

# Construct full destination path
$destZipPath = Join-Path -Path $localDestPath -ChildPath $zipName

# Move the zip file to the destination, overwrite if necessary
try {
    Write-Host "Moving zip file to $localDestPath..."
    Move-Item -Path $zipPath -Destination $destZipPath -Force
    Write-Host "File moved successfully to $destZipPath."
} catch {
    Write-Host "Error occurred during file move: $_"
}
