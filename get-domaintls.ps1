Set-StrictMode -Version Latest

# find all subscriptions where name contains 'PRODUZIONE' or 'DMZ'
$subscriptions = Get-AzSubscription | where { $_.Name -like "*PRODUZIONE*" -or $_.Name -like "*DMZ*" -or $_.Name -like "*POSTE-DIGITAL*" }

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
                Write-Host "ERROR: Custom Domain: $($customDomain.HostName) TLS: $tls"
            }
            else {
                Write-Host "." -NoNewline
            }
        }

        Write-Host
    }
}
