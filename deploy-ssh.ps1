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

# Access SSH and destination environment variables
$sshIP = $env:SSH_IP
$sshUser = $env:SSH_USER
$remotePath = $env:REMOTE_PATH
$destFolderName = $env:DEST_FOLDER_NAME

if (-not $sshIP -or -not $sshUser -or -not $remotePath -or -not $destFolderName) {
    Write-Host "One or more required environment variables are missing. Exiting..."
    exit 1
}

# Determine the folder the script is in
$sourceFolder = (Get-Location).Path

# Ensure the destination folder is properly constructed
$remoteDestPath = "${remotePath}/${destFolderName}"

# Print paths for debugging
Write-Host "Source folder: $sourceFolder"
Write-Host "Remote destination: $remoteDestPath"

# Properly quote the paths to handle spaces in folder names
$quotedSourceFolder = '"' + $sourceFolder + '/."'  # Quotes around the local source folder path and the '.' to indicate current folder content
$quotedRemoteDestPath = "${sshUser}@${sshIP}:${remoteDestPath}"  # Destination path with single quotes around the remote path

# Construct the SCP command to recursively copy the contents of the folder
$scpCommand = "scp -r $quotedSourceFolder $quotedRemoteDestPath"

# Print the SCP command for debugging purposes
Write-Host "Running SCP command: $scpCommand"

try {
    # Create remote directory if it doesn't exist
    $createDirCommand = "ssh $sshUser@$sshIP 'rm -rf ${remoteDestPath} && mkdir ${remoteDestPath}'"
    Write-Host "Recreating mod directory: $createDirCommand"
    Invoke-Expression $createDirCommand

    # Use Start-Process to execute the SCP command
    Start-Process "scp" -ArgumentList "-r", "$sourceFolder/*", "$quotedRemoteDestPath" -Wait -NoNewWindow
    Write-Host "Files transferred successfully to $remoteDestPath on $sshIP."
} catch {
    Write-Host "Error occurred during SCP transfer: $_"
}
