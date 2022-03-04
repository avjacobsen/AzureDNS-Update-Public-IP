function Get-AzCredential {
    param([PSCustomObject]$Config)
    if ($null -eq $Config) { $Config = Get-Config }
    $Credential = New-Object System.Management.Automation.PSCredential ($Config.azure.username, ($Config.azure.password | ConvertTo-SecureString))
    return $Credential
}
function Get-ConfigPath {
    param([Parameter(Mandatory = $false)][string]$Path, [Parameter(Mandatory = $false)][string]$Extension)
    while (($Extension -ne "") -and ($Extension[0] -eq ".")) { $Extension = $Extension.Substring(1) }
    if ($Extension -eq "") { $Extension = "json" }
    if ($Path -eq "") {
        if ($PSCommandPath -ne "") {
            $PathFolder = Get-Item (Get-Item $PSCommandPath).Directory
            $Path = "$($PathFolder)\$((Get-Item $PSCommandPath).BaseName).$($Extension)"
        }
        else {
            if ($Path -notlike "*.$($Extension)") {
                $Path = "config.$($Extension)"
            }
            else {
                $Path = "config.json"
            }
        }
    }
    else {
        if ($Path -notlike "*.$($Extension)") {
            $Path = "$($Path).$($Extension)"
        }
        else {
            $Path = $Path
        }
    }
    return $Path
}
function Get-Config {
    param([string]$Path)
    if ($Path -eq "") {
        $Path = Get-ConfigPath -Path $Path
    }
    if ((Test-Path -Path $Path)) {
        Write-LogMessage "Importing config: $($Path)." -Verbose
        $Config = Get-Content -Path $Path -Encoding UTF8 | ConvertFrom-Json
    }
    else {
        Write-LogMessage "Get-Config: File not found. Creating config file." -Verbose
        $Config = @{
            "azure" = @{
                "username"            = $(Read-Host -Prompt "Azure UserName")
                "password"            = $(Read-Host -AsSecureString -Prompt "Password" | ConvertFrom-SecureString)
                "subscription_id"     = $(Read-Host -Prompt "Azure Subscription Id")
                "resource_group_name" = $(Read-Host -Prompt "Resource Group Name")
                "zone_name"           = $(Read-Host -Prompt "Zone Name")
                "a_record_to_update"  = $(Read-Host -Prompt "Record Name (without zone name)")
                "last_record_value"   = ""
            }
        }
        Write-LogMessage "Saving config to $Path" -Verbose
        $Config | ConvertTo-Json | Set-Content -Path $Path -Encoding UTF8
    }
    return $Config
}
function Get-Count {
    param($Object)
    if ($null -eq $Object) { return 0 }
    else {
        if ($null -eq $Object.Count) { return 1 }
        else { return $Object.Count }
    }
}
function Set-Config {
    param([string]$Path, $Config)
    if ($Path -eq "") {
        $Path = Get-ConfigPath -Path $Path
    }
    Write-LogMessage "Saving config to $Path" -Verbose
    $Config | ConvertTo-Json | Set-Content -Path $Path -Encoding UTF8
}
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
        $Path = ""
    )
    if ($Path -eq "" -and $PSCommandPath -ne "") {
        # No path supplied but running from script. Setting path to script name.
        $Path = "$(Get-Date -Format "yyyy")$(Get-Date -Format "MM")$(Get-Date -Format "dd")_$((Get-Item $PSCommandPath).BaseName).log"
    }
    $MessagePrefix = "$(Get-Date -Format "yyyy").$(Get-Date -Format "MM").$(Get-Date -Format "dd") $(Get-Date -Format "HH"):$(Get-Date -Format "mm"):$(Get-Date -Format "ss") "
    if ($Path -ne "") {
        $AddContentSuccessful = $false
        do {
            try {
                Add-Content -Path $Path -Value "$($MessagePrefix)[$($MessageType)] $($Message)"
                $AddContentSuccessful = $true
            }
            catch {
                $AddContentSuccessful = $false
            }
        } until ($AddContentSuccessful)
    }
    if ($VerbosePreference) {
        Write-Verbose "$($MessagePrefix)[$($MessageType)] $($Message)"
    }
    if ($DebugPreference) {
        Write-Debug "$($MessagePrefix)[$($MessageType)] $($Message)"
    }
}

try {
    $Config = Get-Config
    $Current_Record = Resolve-DnsName -Type A -Name "$($Config.azure.a_record_to_update).$($Config.azure.zone_name)"
    $UpdateRequired = $false
    if ($null -eq $Current_Record) {
        Write-Host "No current record found." -Verbose
        $UpdateRequired = $true
    }
    else {
        $Current_Record_Value = $Current_Record.IPAddress
        Write-LogMessage "Current value for DNS record $($Config.azure.a_record_to_update).$($Config.azure.zone_name): $($Current_Record_Value)" -Verbose
        if ($Current_Record_Value -eq $Config.azure.last_record_value) {
            Write-LogMessage "No update required." -Verbose
        }
        else {
            Write-LogMessage "Update required." -Verbose
            $UpdateRequired = $true
            $Config.azure.last_record_value = $Current_Record_Value
            Set-Config -Config $Config
        }
    }
    if ($UpdateRequired) {
        Write-LogMessage "Connecting to Azure..." -Verbose
        $AzAccount = Connect-AzAccount -Credential (Get-AzCredential -Config $Config) -Subscription ($Config.azure.subscription_id)
        Write-LogMessage "Connected to $($AzAccount.Context.Subscription.Name) as $($AzAccount.Context.Account.Id)." -Verbose
        Write-LogMessage "Getting resource group..." -Verbose
        $AzResourceGroup = Get-AzResourceGroup
        Write-LogMessage "Resource Group ID: $($AzResourceGroup.ResourceId)" -Verbose
        Write-LogMessage "Getting DNS Zone..." -Verbose
        $AzDNSZone = Get-AzDnsZone -Name $Config.azure.zone_name -ResourceGroupName $AzResourceGroup.ResourceGroupName
        Write-LogMessage "DNS Zone: $($AzDNSZone.Name)" -Verbose
        Write-LogMessage "Getting record sets..." -Verbose
        $RecordSets = Get-AzDnsRecordSet -ZoneName $AzDNSZone.Name -ResourceGroupName $AzResourceGroup.ResourceGroupName
        Write-LogMessage "Found $(Get-Count -Object $RecordSets) records." -Verbose
        Write-LogMessage "Making sure CNAME for $($Config.azure.a_record_to_update).$($Config.azure.zone_name) doesn't already exist..." -Verbose
        $RecordSet = $RecordSets | Where-Object { $_.Name -eq $Config.azure.a_record_to_update } | Where-Object { $_.RecordType -eq "CNAME" }
        if ($null -ne $RecordSet) { Write-LogMessage "CNAME record exists. Aborting." -Verbose; exit } else { Write-LogMessage "CNAME record not present." -Verbose }
        Write-LogMessage "Determining public IP via https://api.myip.com..." -Verbose
        $MyIP = ((Invoke-WebRequest -UseBasicParsing -Uri "https://api.myip.com").Content | ConvertFrom-Json).ip
        if ($null -eq $MyIP) { Write-LogMessage "Can't determine public ip." -Verbose }
        else { Write-LogMessage "Public IP is $MyIP" -Verbose }
        Write-LogMessage "Locating A record: $($Config.azure.a_record_to_update).$($Config.azure.zone_name)..." -Verbose
        $RecordSet = $RecordSets | Where-Object { $_.Name -eq $Config.azure.a_record_to_update } | Where-Object { $_.RecordType -eq "A" }
        if ($null -eq $RecordSet) {
            Write-LogMessage "No previous record found. Creating..." -Verbose
            $Records = @()
            $Records += New-AzDnsRecordConfig -IPv4Address $MyIP
            $NewDNSRecordSet = New-AzDnsRecordSet -Name $Config.azure.a_record_to_update -RecordType A -ResourceGroupName $AzResourceGroup.ResourceGroupName -ZoneName $Config.azure.zone_name -Ttl 300 -DnsRecords $Records
            if ($null -eq $NewDNSRecordSet) { Write-LogMessage "Failed." -Verbose; exit }
            else {
                Write-LogMessage "Record created." -Verbose
            }
        }
        else {
            Write-LogMessage "Record already found. Updating..." -Verbose
            $Record = New-AzDnsRecordConfig -IPv4Address $MyIP
            $RecordSet.Records.Clear()
            $RecordSet.Records = $Record
            $NewDNSRecordSet = Set-AzDnsRecordSet -RecordSet $RecordSet
            if ($null -eq $NewDNSRecordSet) { Write-LogMessage "Failed." -Verbose; exit }
            else {
                Write-LogMessage "Record updated." -Verbose
            }
        }
    }
}
catch {
    Write-LogMessage $Error[0] -Verbose -MessageType "ERROR"
    exit
}
