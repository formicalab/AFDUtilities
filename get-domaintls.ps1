[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, HelpMessage = "Specify the subscription filter, for example *PRODUZIONE* filters all subscriptions containing PRODUZIONE in the name")]
    [string]$SubscriptionFilter = $null
)

Set-StrictMode -Version Latest

# find all subscriptions where name contains some specific strings
$subscriptions = Get-AzSubscription | Where-Object { $_.Name -like $SubscriptionFilter }
#$subscriptions = Get-AzSubscription | where { $_.Name -like "*Flaz*"  }

# loop on all subscriptions
foreach ($subscription in $subscriptions) {
    # set current subscription
    $subscriptionName = $subscription.Name
    Set-AzContext -SubscriptionName $subscriptionName | Out-Null

    # get AFD profiles
    Write-Host "Subscription: $subscriptionName, getting AFD profiles..."
    $afdProfiles = Get-AzFrontDoorCdnProfile

    # loop on all profiles, for each one get all custom domains and check their tls settings
    foreach ($afdProfile in $afdProfiles) {
        $afdProfileName = $afdProfile.Name
        $resourceGroupName = $afdProfile.ResourceGroupName

        # get all custom domains
        Write-Host -NoNewline "Checking custom domains for profile ${afdProfileName}: "
        $customDomains = Get-AzFrontDoorCdnCustomDomain -ProfileName $afdProfileName -ResourceGroupName $resourceGroupName

        # output the custom domains and their tls settings
        foreach ($customDomain in $customDomains) {
            $tls = $customDomain.TlsSetting.MinimumTlsVersion
            if ($tls -ne 'TLS12')
            {
                Write-Host "FOUND Custom Domain: $($customDomain.HostName) with min TLS: $tls"
            }
            else {
                Write-Host "." -NoNewline
            }
        }

        Write-Host
    }
}
