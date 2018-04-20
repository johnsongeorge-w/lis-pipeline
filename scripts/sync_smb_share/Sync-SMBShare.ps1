param(
    [parameter(Mandatory=$true)]
    [String] $LocalSharedStoragePath,
    [parameter(Mandatory=$true)]
    [String] $BaseSharedStoragePath,
    [parameter(Mandatory=$true)]
    [String] $ShareUser,
    [parameter(Mandatory=$true)]
    [String] $SharePassword
)

$ErrorActionPreference = "Stop"

$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
$scriptPathParent = (Get-Item $scriptPath ).Parent.FullName

. "$scriptPathParent\common_functions.ps1"

$LOCAL_TO_REMOTE_FOLDER_MAPPINGS = @{
    "stable-kernels" = "stable-kernels";
    "linux-next-kernels" = "upstream-kernel/linux-next";
    "net-next-kernels" = "upstream-kernel/net-next";
}

function Sync-SMBShare {
    param(
        [String] $LocalPath,
        [String] $SharedStoragePath,
        [String] $ShareUser,
        [String] $SharePassword,
        [Object] $DateLimit
    )

    if (!(Test-Path $LocalPath)) {
        throw "Path $LocalPath does not exist."
    }
    $shareLocalPath = Mount-SMBShare $SharedStoragePath $ShareUser $SharePassword
    if (!$shareLocalPath) {
        Write-Output "Share could not be mounted"
        return
    } else {
        $shareLocalPath = $shareLocalPath.Trim()
        Write-Output "Share has been mounted at mount point: $shareLocalPath"
    }
    $shareLocalPath = Resolve-Path "${shareLocalPath}\"
    $foldersToSync = Get-ChildItem -Path $shareLocalPath `
        | Where-Object { $_.PSIsContainer -and $_.CreationTime -gt $DateLimit}
    if ($foldersToSync) {
        foreach ($folderToSync in $foldersToSync) {
            $fullFolderToSyncPath = Join-Path $shareLocalPath $folderToSync
            $localFullFolderToSyncPath = Join-Path $LocalPath $folderToSync
            $dateLimitIncomplete = (Get-Date).AddDays(-1)
            if ((!(Test-Path $localFullFolderToSyncPath)) -or `
                 ((Get-Item $localFullFolderToSyncPath).LastWriteTime `
                   -gt $dateLimitIncomplete)) {
                Write-Output ("Syncing folder {0} to {1}" -f `
                    @($fullFolderToSyncPath, $localFullFolderToSyncPath))
                ROBOCOPY.exe $fullFolderToSyncPath $localFullFolderToSyncPath `
                    /MIR /COPY:DAT /DCOPY:DAT /R:1 /S 2>&1
                (Get-Item $localFullFolderToSyncPath).LastWriteTime = `
                    (Get-Item $fullFolderToSyncPath).LastWriteTime
            } else {
                Write-Output "Skip syncing folder $fullFolderToSyncPath to $LocalPath"
            }
        }
    } else {
        Write-Output "There are no folders to sync from $SharedStoragePath"
    }
}

function Main {
    # Note(avladu): Sync only folders that are max 2 months old
    $dateLimit = (Get-Date).AddMonths(-2)

    foreach ($localFolderToSync in $LOCAL_TO_REMOTE_FOLDER_MAPPINGS.keys) {
        try {
            $mappedFolder = $LOCAL_TO_REMOTE_FOLDER_MAPPINGS[$localFolderToSync]
            $localPath = Join-Path $LocalSharedStoragePath $localFolderToSync
            $sharedStoragePath = Join-Path $BaseSharedStoragePath $mappedFolder
            Write-Host "Syncing $sharedStoragePath to $localPath"
            Sync-SMBShare -LocalPath $localPath -SharedStoragePath $sharedStoragePath `
                -ShareUser $ShareUser -SharePassword $SharePassword `
                -DateLimit $dateLimit
        } catch {
            Write-Host "Failed to sync $localFolderToSync"
            Write-Host $_
        }
    }
}

Main