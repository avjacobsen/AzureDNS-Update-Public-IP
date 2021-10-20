# Update-AzMyPublicIP.ps1

function Write-LogMessage {
    # Source: https://github.com/avjacobsen/Write-LogMessage
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline)]
        [String]
        $Message,
        [Parameter(Mandatory = $false)]
        [String]
        $MessageType = "INFO",
        [Parameter(Mandatory = $false)]
        [String]
        $Path = "",
        [Parameter(Mandatory = $false)]
        [Boolean]
        $Box = $false
    )
    if ($Path -eq "" -and $PSCommandPath -ne "") {
        # No path supplied but running from script. Setting path to script name.
        $Path = "$(Get-Date -Format "yyyy")$(Get-Date -Format "MM")$(Get-Date -Format "dd")_$((Get-Item $PSCommandPath).BaseName).log"
    }
    if ($Path -eq "" -and $PSCommandPath -eq "") {
        # No path supplied and not running from script. Logging to file skipped.
    }
    $MessagePrefix = "$(Get-Date -Format "yyyy").$(Get-Date -Format "MM").$(Get-Date -Format "dd") $(Get-Date -Format "HH"):$(Get-Date -Format "mm"):$(Get-Date -Format "ss") "
    $BoxedMessage = "* $Message *"
    for ($i = 0; $i -le ($BoxedMessage.Length - 1); $i++) { $BoxBar += '*' }
    if ($Path -ne "") {
        if ($Box) {
            Add-Content -Path $Path -Value "$($MessagePrefix)[$($MessageType)] $($BoxBar)"
            Add-Content -Path $Path -Value "$($MessagePrefix)[$($MessageType)] $($BoxedMessage)"
            Add-Content -Path $Path -Value "$($MessagePrefix)[$($MessageType)] $($BoxBar)"
        }
        else {
            Add-Content -Path $Path -Value "$($MessagePrefix)[$($MessageType)] $($Message)"
        }
    }
    if ($VerbosePreference -or $DebugPreference) {
        if ($Box) {
            Write-Host "$($MessagePrefix)[$($MessageType)] $($BoxBar)"
            Write-Host "$($MessagePrefix)[$($MessageType)] $($BoxedMessage)"
            Write-Host "$($MessagePrefix)[$($MessageType)] $($BoxBar)"
        }
        else {
            Write-Host "$($MessagePrefix)[$($MessageType)] $($Message)"
        }
    }
}
Write-LogMessage "Log started for $((Get-Item -Path $PSCommandPath).Name)."
Write-LogMessage "Log stopped."
