Set-StrictMode -Version Latest

$subscriptionName = "POSTE-DIGITAL-PRODUZIONE"
$resourceGroupName = "DIGITAL-POSTEBUSINESS-FE-PROD-WE"
$afdProfileName = "pdmzbusinessfd01azwe"

# set current subscription
Set-AzContext -SubscriptionName $subscriptionName | Out-Null

# get AFD profile
$afdProfile = Get-AzFrontDoorCdnProfile -name $afdProfileName -ResourceGroupName $resourceGroupName

# get AFD endpoint(s)
$afdEndpoints = Get-AzFrontDoorCdnEndpoint -ProfileName $afdProfileName -ResourceGroupName $resourceGroupName

Write-Host "AFD Profile: $($afdProfile.Name)"
if ($afdEndpoints -is [array]) {
    Write-Host "AFD Endpoints: $($afdEndpoints.Count)"
    foreach ($endpoint in $afdEndpoints) {
        Write-Host "Endpoint: $($endpoint.Name)"
    }

    # we don't support multiple endpoints yet
    Write-Host "ERROR: Multiple endpoints are not supported yet"
    exit 1
}
else {
    Write-Host "AFD Endpoints: $($afdEndpoints.Name)"
}

# get all routes
$routes = Get-AzFrontDoorCdnRoute -EndpointName $endpoint.Name -ProfileName $afdprofileName -ResourceGroupName $resourceGroupName

# get all custom domains
$customDomains = Get-AzFrontDoorCdnCustomDomain -ProfileName $afdprofileName -ResourceGroupName $resourceGroupName

# get all origin groups
$originGroups = Get-AzFrontDoorCdnOriginGroup -ProfileName $afdprofileName -ResourceGroupName $resourceGroupName

# get all the rule sets
$ruleSets = Get-AzFrontDoorCdnRuleSet -ProfileName $afdprofile.Name -ResourceGroupName $resourceGroupName

# create a hashtable of origin groups, each with a list of origins
$originGroupOrigins = @{}
$numOrigins = 0
foreach ($originGroup in $originGroups) {
    $origins = Get-AzFrontDoorCdnOrigin -OriginGroupName $originGroup.Name -ProfileName $afdprofileName -ResourceGroupName $resourceGroupName
    $originGroupOrigins[$originGroup.Name] = $origins
    if ($origins -is [array]) {
        $numOrigins += $origins.Count
    }
    else {
        $numOrigins += 1
    }
}

Write-Host "Overall, there are $($routes.Count) routes, $($customDomains.Count) custom domains, $($originGroups.Count) origin groups, $($ruleSets.Count), and $($numOrigins) origins"

# prepare an array of objects with Route, Hostnames, PatternsToMatch, ForwardingProtocol, HttpsRedirect, RuleSet, OriginGroup, Origins
$dump = @()

foreach ($route in $routes) {

    # find the custom domains for this route
    $hostnames = @()
    foreach ($routeDomain in $route.CustomDomain) {
        foreach ($customDomain in $customDomains) {
            if (($routeDomain.Id -eq $customDomain.Id) -and ($routeDomain.IsActive -eq $true)) {
                $hostnames += $customDomain.HostName
            }
        }
    }

    # find the origin group for this route
    $originGroup = $null
    foreach ($og in $originGroups) {
        if ($route.OriginGroupId -eq $og.Id) {
            $originGroup = $og
            break
        }
    }
    # list all the origins for this origin group
    $origins = @()
    if ($originGroupOrigins.ContainsKey($originGroup.Name)) {
        $origins = $originGroupOrigins[$originGroup.Name].HostName
    }
    # sort the origins
    $origins = $origins | Sort-Object

    # find the rule set for this route
    $ruleSet = $null
    foreach ($rs in $ruleSets) {
        if ($route.RuleSet.Id -eq $rs.Id) {
            $ruleSet = $rs
            break
        }
    }

    # put all the data in the hashtable
    $dump += [PSCustomObject]@{
        Route = $route.Name
        Hostnames = $hostnames -join ', '
        PatternsToMatch = $route.PatternsToMatch -join ', '
        ForwardingProtocol = $route.ForwardingProtocol
        HttpsRedirect = $route.HttpsRedirect
        RuleSet = $ruleSet.Name
        OriginGroup = $originGroup.Name
        Origins = $origins -join ', '
    }

}

# sort the dump by the Origins column, then by the Route column
$dump = $dump | Sort-Object -Property Origins, Route

# output the data
$dump | Format-Table -AutoSize

# output the data to a CSV file
$dump | Export-Csv -Path "afddump.csv" -NoTypeInformation