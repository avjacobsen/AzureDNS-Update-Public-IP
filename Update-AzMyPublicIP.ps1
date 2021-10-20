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

function Update-Config {
    # Creates and returns config aswell as saving to disk with encrypted credentials.
    $ConfigFile = "$((Get-Item -Path $PSCommandPath).Directory.FullName)\$((Get-Item -Path $PSCommandPath).BaseName).json"
    Write-LogMessage "Update-Config started."
    Write-LogMessage "Locate config file: $ConfigFile"
    if (Test-Path $ConfigFile) {
        Write-LogMessage "Found config file. Importing..."
        $Config = Get-Content -Path $ConfigFile | ConvertFrom-Json
    }
    else {
        Write-LogMessage "Config file not found. Requesting config from user..."
        $UserName = Read-Host -Prompt "AzureDNS User Name"
        $HashedSecureString = (Read-Host -AsSecureString -Prompt "Password" | ConvertFrom-SecureString)
        $TenantId = Read-Host -Prompt "Azure Tenant Id"
        $ResourceGroupName = Read-Host -Prompt "Azure Resource Group Name"
        $ZoneName = Read-Host -Prompt "DNS Zone"
        $ARecordToUpdate = Read-Host -Prompt "A-record to update [homewanip]"
        if ($ARecordToUpdate -eq "") { $ARecordToUpdate = "homewanip" }
        $Config = @{"Account" = $UserName; "Password" = $HashedSecureString; "TenantId" = $TenantId; "ResourceGroupName" = $ResourceGroupName; "ZoneName" = $ZoneName; "ARecordToUpdate" = $ARecordToUpdate }
        Write-LogMessage "Saving config file: $ConfigFile"
        $Config | ConvertTo-Json | Set-Content -Path $ConfigFile
    }
    Write-LogMessage "Account: $($Config.Account)"
    Write-LogMessage "Tenant: $($Config.TenantId)"
    Write-LogMessage "Resource Group: $($Config.ResourceGroupName)"
    Write-LogMessage "DNS Zone: $($Config.ZoneName)"
    Write-LogMessage "A-record to update: $($Config.ARecordToUpdate)"
    return $Config
}

function Connect-ToAzure {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        $RunningConfig
    )
    Write-LogMessage "Connecting to Azure..."
    $AzureAccessToken = $null
    while ($AzureAccessToken -eq $null) {
        Write-LogMessage "Checking access token..."
        $AzureAccessToken = Get-AzAccessToken -ErrorAction SilentlyContinue
        if ($null -eq $AzureAccessToken) {
            Write-LogMessage "No token found. Connecting..."
            $Credential = New-Object System.Management.Automation.PSCredential ($RunningConfig.Account, ($RunningConfig.Password | ConvertTo-SecureString))
            $AzureProfile = Connect-AzAccount -Credential $Credential
            if ($null -eq $AzureProfile) {
                Write-LogMessage "Failed to connect to Azure."
                return $null
            }
            else {
                $AzureAccessToken = $null
            }
        }
        else {
            if ($AzureAccessToken.UserId -eq $RunningConfig.Account -and $AzureAccessToken.TenantId -eq $RunningConfig.TenantId) {
                Write-LogMessage "Matching token found."
                return $AzureAccessToken
            }
            else {
                Write-LogMessage "Token mismatch. Disconnecting from azure..."
                Disconnect-AzAccount
                $AzureAccessToken = $null
            }
        }
    }
}

function Update-MyPublicIP {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        $RunningConfig
    )

}

Write-LogMessage "Log started for $((Get-Item -Path $PSCommandPath).Name)."
$RunningConfig = Update-Config
$AzureToken = Connect-ToAzure -RunningConfig $RunningConfig
if ($null -eq $AzureToken) { exit } else { Write-LogMessage "$($AzureToken.UserId) connected to Azure." }

Write-LogMessage "Getting tenant info..."
$AzTenant = Get-AzTenant
Write-LogMessage "Getting resource group info..."
$AzResourceGroup = Get-AzResourceGroup
Write-LogMessage "Getting DNS Zone info..."
$AzDNSZone = Get-AzDnsZone -Name $RunningConfig.ZoneName -ResourceGroupName $AzResourceGroup.ResourceGroupName
Write-LogMessage "Getting record sets..."
$RecordSets = Get-AzDnsRecordSet -ZoneName $AzDNSZone.Name -ResourceGroupName $AzResourceGroup.ResourceGroupName
Write-LogMessage "Making sure CNAME doesn't already exist..."
$RecordSet = $RecordSets | Where-Object { $_.Name -eq $RunningConfig.ARecordToUpdate } | Where-Object { $_.RecordType -eq "CNAME" }
if ($null -ne $RecordSet) { Write-LogMessage "CNAME record exists. Aborting."; exit }
Write-LogMessage "Locating A record..."
$MyIP = ((Invoke-WebRequest -UseBasicParsing -Uri "https://api.myip.com").Content | ConvertFrom-Json).ip
if ($null -eq $MyIP) { Write-LogMessage "Can't determine public ip." }
else { Write-LogMessage "Public IP is $MyIP" }
$RecordSet = $RecordSets | Where-Object { $_.Name -eq $RunningConfig.ARecordToUpdate } | Where-Object { $_.RecordType -eq "A" }
if ($null -eq $RecordSet) {
    Write-LogMessage "No record found. Creating..."
    $Records = @()
    $Records += New-AzDnsRecordConfig -IPv4Address $MyIP
    $NewDNSRecordSet = New-AzDnsRecordSet -Name $RunningConfig.ARecordToUpdate -RecordType A -ResourceGroupName $AzResourceGroup.ResourceGroupName -ZoneName $RunningConfig.ZoneName -Ttl 300 -DnsRecords $Records
    if ($null -eq $NewDNSRecordSet) { Write-LogMessage "Failed."; exit }
    else {
        Write-LogMessage "Record created."
    }
}
else {
    Write-LogMessage "Record already found. Updating..."
    $Records = @()
    $Records += New-AzDnsRecordConfig -IPv4Address $MyIP
    $RecordSet.Records = $Records
    $NewDNSRecordSet = Set-AzDnsRecordSet -RecordSet $RecordSet
    if ($null -eq $NewDNSRecordSet) { Write-LogMessage "Failed."; exit }
    else {
        Write-LogMessage "Record updated."
    }
}