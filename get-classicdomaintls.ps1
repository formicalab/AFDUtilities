Set-StrictMode -Version Latest

# find all subscriptions where name contains some specific strings
Write-Host "Getting subscriptions..."
$subscriptions = Get-AzSubscription | where { $_.Name -like "*PRODUZIONE*" }
#$subscriptions = Get-AzSubscription | where { $_.Name -like "*Flaz*"  }

# loop on all subscriptions
foreach ($subscription in $subscriptions) {
    # set current subscription
    $subscriptionName = $subscription.Name
    Set-AzContext -SubscriptionName $subscriptionName | Out-Null

    # get AFD instances
    Write-Host "Subscription: $subscriptionName, getting AFD instances..."
    $afdInstances = Get-AzFrontDoor

    # loop on all instances, for each one get all custom domains and check their tls settings
    foreach ($afdInstance in $afdInstances) {
        $afdInstanceName = $afdInstance.Name

        # get all endpoints
        Write-Host "Checking endpoints for instance ${afdInstanceName}:"
        $endpoints = $afdInstance | Get-AzFrontDoorFrontendEndpoint

        # output the custom domains and their tls settings
        foreach ($endpoint in $endpoints) {
            $tls = $endpoint.MinimumTlsVersion
            if ($tls -eq '1.0')
            {
                Write-Host -ForegroundColor Red "`tFOUND Endpoint: $($endpoint.HostName) with min TLS: $tls"
            }
            else {
                Write-Host "`t$($endpoint.HostName) (${tls})"
            }
        }
    }
}
