# Ensure .NET Environment for .env parsing
$envFile = ".env"
if (!(Test-Path $envFile)) {
    Write-Host "No .env file found. Exiting..."
    exit 1
}

# Parse .env file for SSH credentials and remote path
$envVars = Get-Content $envFile | ForEach-Object {
    if ($_ -match '^\s*([a-zA-Z_]+)\s*=\s*(.+)\s*$') {
        $key = $matches[1]
        $value = $matches[2]
        [PSCustomObject]@{ Key = $key; Value = $value }
    }
} | Where-Object { $_.Key -and $_.Value } | Group-Object -AsHashTable -AsString Key

# Extract variables
$sshIP = $envVars['SSH_IP']
$sshUser = $envVars['SSH_USER']
$sshPass = $envVars['SSH_PASS']
$remotePath = $envVars['REMOTE_PATH']

if (-not ($sshIP -and $sshUser -and $sshPass -and $remotePath)) {
    Write-Host "One or more environment variables are missing. Exiting..."
    exit 1
}

# Get current folder name for zip file
$folderName = Split-Path -Leaf (Get-Location)
$zipFileName = "$folderName.zip"

# Zip the folder excluding hidden files and folders
function Add-Zip {
    param (
        [string]$sourcePath,
        [string]$zipPath
    )
    Add-Type -Assembly "System.IO.Compression.FileSystem"
    [System.IO.Compression.ZipFile]::CreateFromDirectory($sourcePath, $zipPath, [System.IO.Compression.CompressionLevel]::Optimal, $false)
}

$sourcePath = Get-Location
$filesToInclude = Get-ChildItem -Recurse -File | Where-Object { -not ($_.Name -like '.*') }
$foldersToInclude = Get-ChildItem -Recurse -Directory | Where-Object { -not ($_.Name -like '.*') }

# Compress only non-hidden files and folders
$zipPath = "$($pwd.Path)\$zipFileName"
Add-Zip -sourcePath $sourcePath -zipPath $zipPath

# Install SSH module if not available
if (-not (Get-Command scp -ErrorAction SilentlyContinue)) {
    Install-Module -Name Posh-SSH -Force -AllowClobber -Scope CurrentUser
}

# Secure password handling for SCP
$secPassword = ConvertTo-SecureString $sshPass -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential ($sshUser, $secPassword)

# Send zip file to the remote server using SCP
try {
    # Establish SSH session
    $session = New-SSHSession -ComputerName $sshIP -Credential $cred
    if ($session) {
        # Transfer the file
        Write-Host "Transferring zip file to remote server..."
        Set-SCPFile -LocalFile $zipPath -RemotePath $remotePath -SessionId $session.SessionId -Force

        # Cleanup SSH session
        Remove-SSHSession -SessionId $session.SessionId
        Write-Host "File transferred successfully."
    }
} catch {
    Write-Host "Error occurred during SCP transfer: $_"
}
