# Set strict mode to catch undeclared variables, etc.
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$findPattern    = "76 11 e8 ?? ?? ?? ?? a1 ?? ?? ff 00 c6 80 20 01 00 00 01"
$replacePattern = "76 11 90 90 90 90 90 90 90 90 90 90 90 90 90 90 90 90 90"

function Get-RegistryValueSilently {
    param (
        [string]$Path,
        [string]$Key
    )
    try {
        $value = (Get-Item $Path -ErrorAction SilentlyContinue).GetValue($Key)
        return $value
    } catch {
        # Silently handle errors, returning $null to indicate failure
        return $null
    }
}

function Find-GamePath {
    param (
        [string]$DefaultPath,
        [string]$SteamAppId,
        [string]$GogGameId
    )
    $steampath = Get-RegistryValueSilently -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Steam App $SteamAppId"  -Key "InstallLocation"
    $gogpath = Get-RegistryValueSilently -Path "HKLM:\SOFTWARE\WOW6432Node\GOG.com\Games\$GogGameId" -Key "path"

    if(Test-Path "$DefaultPath\noita.exe") {
        return $DefaultPath
    } elseif($steampath) {
        return $steampath
    } elseif($gogpath) {
        return $gogpath
    } else {
        return $null
    }
}

function Find-PatternInBytes {
    param (
        [byte[]]$Bytes,
        [string]$Pattern
    )

    $patternArray = $Pattern.Split(' ') | ForEach-Object { if ($_ -ne '??') { [convert]::ToByte($_, 16) } else { [byte]0 } }
    $wildcardArray = $Pattern.Split(' ') | ForEach-Object { if ($_ -eq '??') { $true } else { $false } }

    $locations = New-Object System.Collections.Generic.List[int]

    for ($i = 0; $i -le $Bytes.Length - $patternArray.Length; $i++) {
        $match = $true
        for ($j = 0; $j -lt $patternArray.Length; $j++) {
            if (-not $wildcardArray[$j] -and $Bytes[$i + $j] -ne $patternArray[$j]) {
                $match = $false
                break
            }
        }
        if ($match) {
            $locations.Add($i)
        }
    }

    return $locations
}
function Main {
    param (
        [string]$GamePath = ".",
        [string]$SteamAppId = "881100",
        [string]$GogGameId = "1310457090"
    )
    $finalGamePath = Find-GamePath -DefaultPath $GamePath -SteamAppId $SteamAppId -GogGameId $GogGameId
    if ((-not $finalGamePath) -or (-not (Test-Path "$finalGamePath\noita.exe"))) {
        Write-Error "Unable to locate the game through common installation paths. Please ensure the game is installed."
        exit
    }


    Write-Host "Game found at: $finalGamePath"

    # Write noita bytes to variable
    $noitaBytes = [System.IO.File]::ReadAllBytes("$finalGamePath\noita.exe")

    # Find the pattern in the noita bytes
    $locations = Find-PatternInBytes -Bytes $noitaBytes -Pattern $findPattern

    # Output locations in hexadecimal format
    foreach ($location in $locations) {
        $hexLocation = "0x{0:X}" -f $location
        Write-Host "Pattern found at location: $hexLocation"
    }

    # Check if exactly one location was found
    $locationsCount = ($locations | measure).Count
    if ($locationsCount -eq 0) {
        Write-Error "Error: Expected to find exactly one pattern, but found $($locationsCount). The patch may have already been applied."
        exit
    } elseif ($locationsCount -gt 1) {
        Write-Error "Error: Expected to find exactly one pattern, but found $($locationsCount)."
        exit
    }
    
    # Verify backup file doesn't exist
    $backupPath = "$finalGamePath\noita.exe.bak"
    if (Test-Path $backupPath) {
        $timestamp = Get-Date -Format "yyyyMMddHHmmss"
        $backupPath = "$finalGamePath\noita.exe.$timestamp.bak"
        Write-Host "Existing backup detected, creating a new backup with timestamp: $backupPath"
    }

    Write-Host "Backing up original 'noita.exe' to '$backupPath'."
    Copy-Item "$finalGamePath\noita.exe" $backupPath

    # Replace the pattern in the noita bytes
    $startIndex = $locations[0]
    $replacementBytes = $replacePattern.Split(' ') | ForEach-Object { [convert]::ToByte($_, 16) }

    for ($i = 0; $i -lt $replacementBytes.Length; $i++) {
        $noitaBytes[$startIndex + $i] = $replacementBytes[$i]
    }

    $confirmWriteBack = Read-Host "The pattern has been found and is ready to be replaced. Do you want to write the changes back to 'noita.exe'? (Y/N)"
    if ($confirmWriteBack -ne 'Y') {
        Write-Host "Operation cancelled by the user. No changes were made to 'noita.exe'."
        exit
    }

    # Write the modified noita bytes back to the file
    [System.IO.File]::WriteAllBytes("$finalGamePath\noita.exe", $noitaBytes)

    Write-Host "noita.exe modified successfully."

    # Exit with success
    exit 0
}

# Main entry point
Main -GamePath "." -SteamAppId "881100" -GogGameId "1310457090"
