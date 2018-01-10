<#
.SYNOPSIS
Stops, starts and sets account passwords for services related to System Center Operations Manager.

.DESCRIPTION
Stops, starts and sets account passwords for services related to System Center Operations Manager.

.PARAMETER ManagementGroup
Specifies a Management Group which must be configured in the associated configuration file.

.PARAMETER Role
Specifies the server role for the services that are to be updated.  Must be one of the following values:
 -ManagementServer
 -SQLServer
 -ReportingServices
 -Orchestrator
 -ALL

.PARAMETER ServerName
(Optional) Specifies the servername hosting the services to be managed.

.PARAMETER Action
Specifies whether to start, stop or change the credential for a service.  Must be one of the following values:
 -Start
 -Stop
 -Restart
 -ChangePassword
 -Verify

.EXAMPLES
  .\Manage-ServiceCredsByGroup.ps1 -ManagementGroup "FOO" -RoleName "ManagementServer" -Action "Stop"
  .\Manage-ServiceCredsByGroup.ps1 -ManagementGroup "FOO" -RoleName "ManagementServer" -Action "ChangePassword"
  .\Manage-ServiceCredsByGroup.ps1 -ManagementGroup "FOO" -RoleName "ManagementServer" -Action "Start"

.NOTES
THIS SOFTWARE IS PROVIDED AS-IS.  THERE IS NO WARRANTY EITHER EXPRESSED OR IMPLIED

.HISTORY
2017/01/24    HMS    Added parameter to specify servername; added StopSequence and StartSequence to Role and Server elements

#>
[CmdletBinding(SupportsShouldProcess=$true)]
param (
	[Parameter(Mandatory=$true)]
	[string]$ManagementGroup,
	[Parameter(Mandatory=$true)]
	[ValidateSet("ManagementServer","SQLServer","ReportingServices","Orchestrator","ALL")]  
	[string]$RoleName,
	[Parameter(Mandatory=$false)]
	[string]$ServerName,
	[Parameter(Mandatory=$true)]
	[ValidateSet("Stop","Start","Restart","ChangePassword","Verify")]  
	[string]$Action,
	[Parameter(Mandatory=$false)] 
	[string]$ConfigFile="OpsMgrConfig.config"
)

If(Test-Path $ConfigFile){
    [xml]$config= Get-content $ConfigFile
} else {
    Throw "Configuration file is missing!"
}

# Extract the list of servers and services based on parameters provided
If($RoleName -eq "ALL") {
    [string]$xPathRole = "/configuration/ManagementGroup[@name=""$managementGroup""]/roles/role[@active='True']"
} Else {
    [string]$xPathRole = "/configuration/ManagementGroup[@name=""$managementGroup""]/roles/role[@name=""$RoleName"" and @active='True']"
}
# [string]$xPath = "/configuration/ManagementGroup[""$managementGroup""]/servers/server[@role=""$RoleName"" and @active='True']"
$roles = $config.SelectNodes($xPathRole)

# Build a reusable array $tempTop of the services which can be sorted as necessary
$tempTop = @()

foreach($role in $roles){
    [string]$myRole = $role.name
    If($ServerName.Length -gt 0){
        [string]$xPathServer = "/configuration/ManagementGroup[@name=""$managementGroup""]/roles/role[@name=""$myRole"" and @active='True']/servers/server[@name=""$ServerName"" and @active='True']"
    } Else {
        [string]$xPathServer = "/configuration/ManagementGroup[@name=""$managementGroup""]/roles/role[@name=""$myRole"" and @active='True']/servers/server[@active='True']"
    }
    $servers = $config.SelectNodes($xPathServer)

    foreach($server in $servers){
        # write-host $server.GetAttribute("name")
        $myServerName=$server.name
        $services=$config.SelectNodes("/configuration/ManagementGroup[@name=""$managementGroup""]/roles/role[@name=""$myRole"" and @active='True']/servers/server[@name=""$myServerName"" and @active='True']/services/service")

        foreach($service in $services){
            # Write-Host $service.GetAttribute("name")
            $temp = New-Object PSObject
            Add-Member -InputObject $temp -MemberType NoteProperty -Name Role -Value $role.GetAttribute("name")
            Add-Member -InputObject $temp -MemberType NoteProperty -Name roleStopSequence -Value $role.GetAttribute("stopSequence")
            Add-Member -InputObject $temp -MemberType NoteProperty -Name roleStartSequence -Value $role.GetAttribute("startSequence")
            Add-Member -InputObject $temp -MemberType NoteProperty -Name Server -Value $server.GetAttribute("name")
            Add-Member -InputObject $temp -MemberType NoteProperty -Name serverStopSequence -Value $server.GetAttribute("stopSequence")
            Add-Member -InputObject $temp -MemberType NoteProperty -Name serverStartSequence -Value $server.GetAttribute("startSequence")
            Add-Member -InputObject $temp -MemberType NoteProperty -Name Service -Value $service.GetAttribute("name")
            Add-Member -InputObject $temp -MemberType NoteProperty -Name serviceStopSequence -Value $service.GetAttribute("stopSequence")
            Add-Member -InputObject $temp -MemberType NoteProperty -Name serviceStartSequence -Value $service.GetAttribute("startSequence")
            Add-Member -InputObject $temp -MemberType NoteProperty -Name credential -Value $service.GetAttribute("credential")
            $tempTop += $temp
        }
    }

}

If($Action -eq "Stop"){
    # $tempTop | Sort-Object Server, stopSequence | Select Server, Service, stopSequence
    $sortedServices = $tempTop | Sort-Object roleStopSequence, serverStopSequence, serviceStopSequence
    foreach($item in $sortedServices){
        $msg = "Attempting to stop service {0} on server {1}" -f $item.Service,$item.Server
        write-host $msg
        if($item.Server -match $env:COMPUTERNAME){
            Stop-Service $item.Service
        } Else {
            get-service $item.Service -ComputerName $item.Server | Stop-Service 
        }
    }

} elseIf($Action -eq "Start") {
    # $tempTop | Sort-Object Server, startSequence | Select Server, Service, startSequence
    $sortedServices = $tempTop | Sort-Object roleStartSequence, serverStartSequence, serviceStartSequence
    foreach($item in $sortedServices){
        $msg = "Attempting to start service {0} on server {1}" -f $item.Service,$item.Server
        write-host $msg
        if($item.Server -match $env:COMPUTERNAME){
            Start-Service $item.Service
        } Else {
            get-service $item.Service -ComputerName $item.Server | Start-Service 
        }
    }

} elseIf($Action -eq "Restart") {

    $sortedServices = $tempTop | Sort-Object roleStopSequence, serverStopSequence, serviceStopSequence
    foreach($item in $sortedServices){
        $msg = "Attempting to stop service {0} on server {1}" -f $item.Service,$item.Server
        write-host $msg
        if($item.Server -match $env:COMPUTERNAME){
            Stop-Service $item.Service
        } Else {
            get-service $item.Service -ComputerName $item.Server | Stop-Service 
        }
    }

    Write-Host ""

    # $tempTop | Sort-Object Server, startSequence | Select Server, Service, startSequence
    $sortedServices = $tempTop | Sort-Object roleStartSequence, serverStartSequence, serviceStartSequence
    foreach($item in $sortedServices){
        $msg = "Attempting to start service {0} on server {1}" -f $item.Service,$item.Server
        write-host $msg
        if($item.Server -match $env:COMPUTERNAME){
            Start-Service $item.Service
        } Else {
            get-service $item.Service -ComputerName $item.Server | Start-Service 
        }
    }

} elseIf($Action -eq "ChangePassword") {
    # $tempTop | Sort-Object Server, startSequence | Select Server, Service, startSequence
    $sortedServices = $tempTop | Sort-Object roleStartSequence, serverStartSequence, serviceStartSequence

#    TODO: Collect each service account credential only once
#    $credentials = $tempTop | Select -uniq credential 
#
#    foreach($credential in $credentials){
#        If($credential -ne "LocalSystem"){
#            $newCredential = Get-Credential -UserName $credential -Message "Enter password for user account"
#        }
#    }

    foreach($item in $sortedServices){
        If($item.credential -ne "LocalSystem"){
            # Get the new credential
            $newCredential = Get-Credential -UserName $item.credential -Message "Enter password for user account"
            $msg = "Attempting to change password for service {0} on server {1}" -f $item.Service,$item.Server
            write-host $msg

            # Retrieve the service from the remote server using WMI to validate that the current Start Account matches the UserName of the provided credential
            [string]$wmiQuery = "SELECT StartName, State FROM Win32_Service WHERE Name='" + $item.Service + "'"
            $objService=get-wmiObject -query $wmiQuery -ComputerName $item.Server
            [string]$serviceState = $objService.State
            [string]$currentAccount=$objService.StartName

            If($serviceState -ne "Stopped"){
                # If the service is not in a stopped state, we probably don't want to change the password
                $msg="Service {0} on server {1} is currently {2}; unable to change service account password!" -f $item.Service, $item.Server, $serviceState
                write-host $msg
            } Else {
                If($currentAccount -eq $newCredential.UserName){
                    .\Set-ServiceCredential.ps1 -ServiceName $item.Service -ComputerName $item.Server -ServiceCredential $newCredential -confirm:$false -WhatIf:([bool]$WhatIfPreference.IsPresent)
                } Else {
                    $msg = "Cannot change the Service Account for service {0}.  Current Account: {1}.  New credential account: {2}" -f $item.Service, $currentAccount, $newCredential.UserName
                    write-host $msg
                }
            }
        } Else {
            $msg="Service {0} on server {1} uses a managed service account or a system account; no password to change." -f $item.Service, $item.Server
            Write-Host $msg
        }
    }
    

} elseIf($Action -eq "Verify") {
    # Verify that the credentials in the configuration file match the Start Accounts for the configured services
    $sortedServices = $tempTop | Sort-Object roleStartSequence, serverStartSequence, serviceStartSequence

    foreach($item in $sortedServices){
        # Retrieve the service from the remote server using WMI to validate that the current Start Account matches the UserName of the provided credential
        [string]$wmiQuery = "SELECT StartName FROM Win32_Service WHERE Name='" + $item.Service + "'"
        $objService=get-wmiObject -query $wmiQuery -ComputerName $item.Server
        [string]$currentAccount=$objService.StartName

        If($currentAccount.SubString($currentAccount.Length-1,1) -eq "$"){
            # Account ending in $ is Managed Service Account; don't change it
            $msg="READY: Service {0} on Server {1} uses a managed service account {2}" -f $item.Service, $item.Server, $currentAccount
        } ElseIf ($item.Credential -eq "LocalSystem"){
            # Need a better test here, but we don't want to mess with local system account
            $msg="READY: Service {0} on Server {1} uses a system account {2}" -f $item.Service, $item.Server, $currentAccount
        } Else {
            # Verify that the service account name matches the service account name in the configuration file
            If($currentAccount -eq $item.credential){
                $msg="READY: Service {0} on Server {1} using account {2} is verified to match configuration file!" -f $item.Service, $item.Server, $item.Credential
            } Else {
                $msg="ERROR: Service {0} on Server {1} using account {2} does not match configuration file: {3}!" -f $item.Service, $item.Server, $currentAccount, $item.Credential
            }

        }        
        write-host $msg
    }

}

