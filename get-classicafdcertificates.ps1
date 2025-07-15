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
$subscriptions = Get-AzSubscription -WarningAction SilentlyContinue | Where-Object { $_.Name -like $SubscriptionFilter }

# prepare result collection
$results = @()

# loop on all subscriptions
foreach ($subscription in $subscriptions) {
    # set current subscription
    $subscriptionId = $subscription.Id
    $subscriptionName = $subscription.Name
    Set-AzContext -SubscriptionId $subscriptionId -WarningAction SilentlyContinue | Out-Null

    # get classic Front Door instances
    Write-Host "Subscription: $subscriptionName, getting Front Door (classic) instances... " -NoNewline
    $afdInstances = Get-AzFrontDoor

    if (-not $afdInstances) {
        Write-Host "No Front Door (classic) instances found in subscription: $subscriptionName"
    } else {
        Write-Host "$($afdInstances.Count) instances found; processing... "
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

    # get the endpoints for each instance


    # get classic CDN instances
    Write-Host "Subscription: $subscriptionName, getting CDN (classic) instances... " -NoNewline
    $cdnInstances = Get-AzCdnProfile

    if (-not $cdnInstances) {
        Write-Host "No CDN (classic) instances found in subscription: $subscriptionName"
    } else {
        Write-Host "$($cdnInstances.Count) instances found; processing... "
        # get the endpoints for each instance
        foreach ($cdnInstance in $cdnInstances) {
            $cdnName = $cdnInstance.Name

            # get all endpoints
            Write-Host "`tInstance ${cdnName}: " -NoNewline
            $endpoints = Get-AzCdnEndpoint -ProfileName $cdnInstance.Name -ResourceGroupName $cdnInstance.ResourceGroupName -WarningAction SilentlyContinue

            if (-not $endpoints) {
                Write-Host 'No endpoints found'
                continue
            } else {
                Write-Host "$($endpoints.Count) endpoint(s) found; processing... " -NoNewline
            }
        
            # loop through endpoints and collect certificate information
            $found = 0
            foreach ($ep in $endpoints) {

                $customDomain = Get-AzCdnCustomDomain -EndpointName $ep.Name -ProfileName $cdnInstance.Name -ResourceGroupName $cdnInstance.ResourceGroupName

                $CustomHttpsProvisioningState = $customDomain.CustomHttpsProvisioningState
                $certificateSource = $customDomain.CustomHttpsParameter.CertificateSource
                if ($certificateSource -eq 'Cdn') {
                    $found++
                    $minimumTlsVersion = $customDomain.CustomHttpsParameter.MinimumTlsVersion
                }
                if ($customDomain.CustomHttpsParameter.CertificateSourceParameterVaultName) {
                    $keyVaultSecretName = $customDomain.CustomHttpsParameter.CertificateSourceParameterSecretName
                    $keyVaultName = $customDomain.CustomHttpsParameter.CertificateSourceParameterVaultName
                    $minimumTlsVersion = $customDomain.CustomHttpsParameter.CertificateSourceParameterVaultName
                }
                else {
                    $keyVaultSecretName = $null
                    $keyVaultName = $null
                }
                
            }

            if ($found -eq 0) {
                Write-Host -ForegroundColor Green "No managed certificates found."
            }
            else {
                Write-Host -ForegroundColor Yellow "Found $found endpoint(s) with managed certificates"
            }

            $result = [PSCustomObject]@{
                SubscriptionName             = $subscriptionName
                CDNName                      = $cdnName
                CDNEndpointName              = $ep.name
                HostName                     = $customDomain.hostName
                CustomHttpsProvisioningState = $CustomHttpsProvisioningState
                CertificateSource            = $certificateSource
                KeyVaultSecretName           = $keyVaultSecretName
                KeyVaultName                 = $keyVaultName
                MinimumTlsVersion            = $minimumTlsVersion
            }

            $results += $result
        }
    }

}

# Output to console
$results | Format-Table

if ($ExportCsvPath) {
    # Export results to CSV if a path is specified
    $results | Export-Csv -Path $ExportCsvPath -NoTypeInformation
    Write-Host "Results exported to $ExportCsvPath"
}
 