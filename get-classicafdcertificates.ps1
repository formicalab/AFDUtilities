#Requires -PSEdition Core
using module Az.Accounts

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false, HelpMessage = 'Specify the subscription filter, for example *PRODUZIONE* filters all subscriptions containing PRODUZIONE in the name')]
    [string]$SubscriptionFilter,

    [Parameter(Mandatory = $false, HelpMessage = 'Specify the CSV file to export results, if not specified results will be displayed in the console only')]
    [string]$ExportCsvPath
)

Set-StrictMode -Version 1           # esnure no uninitialized variables are used
$ErrorActionPreference = 'Stop'     # stop on errors

if (-not $SubscriptionFilter) {
    # default filter to find all subscriptions
    $SubscriptionFilter = '*'
}   

# find all subscriptions where name contains some specific strings
$subscriptions = Get-AzSubscription | Where-Object { $_.Name -like $SubscriptionFilter }

# prepare result collection
$results = @()

# loop on all subscriptions
foreach ($subscription in $subscriptions) {
    # set current subscription
    $subscriptionName = $subscription.Name
    Set-AzContext -SubscriptionName $subscriptionName | Out-Null

    # get classic Front Door instances
    Write-Host "Subscription: $subscriptionName, getting Front Door (classic) instances... " -NoNewline
    $afdInstances = Get-AzFrontDoor

    if (-not $afdInstances) {
        Write-Host "No Front Door (classic) instances found in subscription: $subscriptionName"
        continue
    }
    else {
        Write-Host "$($afdInstances.Count) instances found; processing... "
    }

    # get the endpoints for each instance
    foreach ($afdInstance in $afdInstances) {
        $afdName = $afdInstance.Name

        # get all endpoints
        Write-Host "`tInstance ${afdName}: " -NoNewline
        $endpoints = $afdInstance | Get-AzFrontDoorFrontendEndpoint

        if (-not $endpoints) {
            Write-Host 'No endpoints found'
            continue
        }
        else {
            Write-Host "$($endpoints.Count) endpoint(s) found; processing... " -NoNewline
        }
    
        # loop through endpoints and collect certificate information
        $found = 0
        foreach ($ep in $endpoints) {

            $CustomHttpsProvisioningState = $ep.CustomHttpsProvisioningState
            $certificateSource = $ep.CertificateSource
            if ($certificateSource -eq 'FrontDoor') {
                $found++
            }
            if ($ep.Vault) {
                $keyVaultSecretName = $ep.secretName
                $keyVaultName = ($ep.vault -split ('/'))[-1]
            }
            else {
                $keyVaultSecretName = $null
                $keyVaultName = $null
            }
            $minimumTlsVersion = $ep.minimumTlsVersion
        }

        if ($found -eq 0) {
            Write-Host -ForegroundColor Green "No managed certificates found."
        }
        else {
            Write-Host -ForegroundColor Yellow "Found $found endpoint(s) with managed certificates"
        }

        $result = [PSCustomObject]@{
            SubscriptionName             = $subscriptionName
            FrontDoorName                = $afdName
            FrontendEndpointName         = $ep.name
            HostName                     = $ep.hostName
            CustomHttpsProvisioningState = $CustomHttpsProvisioningState
            CertificateSource            = $certificateSource
            KeyVaultSecretName           = $keyVaultSecretName
            KeyVaultName                 = $keyVaultName
            MinimumTlsVersion            = $minimumTlsVersion
        }

        $results += $result
    }
}

# Output to console
$results | Format-Table

if ($ExportCsvPath) {
    # Export results to CSV if a path is specified
    $results | Export-Csv -Path $ExportCsvPath -NoTypeInformation
    Write-Host "Results exported to $ExportCsvPath"
}
