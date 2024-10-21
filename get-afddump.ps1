Set-StrictMode -Version Latest

$subscriptionName = "PRODUZIONE"
$resourceGroupName = "RGNAME"
$afdProfileName = "profilename"

# set current subscription
Set-AzContext -SubscriptionName $subscriptionName | Out-Null

# get AFD profile
write-host "Getting AFD profile: $afdProfileName"
$afdProfile = Get-AzFrontDoorCdnProfile -name $afdProfileName -ResourceGroupName $resourceGroupName

# get AFD endpoint(s)
Write-Host "Getting AFD endpoints for profile: $afdProfileName"
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
    $afdEndpoint = $afdEndpoints
    Write-Host "AFD Endpoints: $($afdEndpoint.Name)"
}

# get all routes
Write-Host "Getting routes for endpoint: $($afdEndpoint.Name) in profile: $afdProfileName"
$routes = Get-AzFrontDoorCdnRoute -EndpointName $afdEndpoint.Name -ProfileName $afdProfileName -ResourceGroupName $resourceGroupName

# get all custom domains
Write-Host "Getting custom domains for profile: $afdProfileName"
$customDomains = Get-AzFrontDoorCdnCustomDomain -ProfileName $afdProfileName -ResourceGroupName $resourceGroupName

# get all origin groups
Write-Host "Getting origin groups for profile: $afdProfileName"
$originGroups = Get-AzFrontDoorCdnOriginGroup -ProfileName $afdProfileName -ResourceGroupName $resourceGroupName

# get all the rule sets
Write-Host "Getting rule sets for profile: $($afdProfile.Name)"
$ruleSets = Get-AzFrontDoorCdnRuleSet -ProfileName $afdProfile.Name -ResourceGroupName $resourceGroupName

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
                $tls = $customDomain.TlsSetting.MinimumTlsVersion
                $hostnames += $customDomain.HostName + ' (' + $tls + ')'
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
    if ($route.RuleSet -and $route.RuleSet.Id)
    {
        $routeRuleSetId = $route.RuleSet.Id
        foreach ($rs in $ruleSets) {
            if ($routeRuleSetId -eq $rs.Id) {
                $ruleSet = $rs
                break
            }
        }    
    }

    # put all the data in the hashtable
    $dump += [PSCustomObject]@{
        Route = $route.Name
        Hostnames = $hostnames -join ', '
        PatternsToMatch = $route.PatternsToMatch -join ', '
        ForwardingProtocol = $route.ForwardingProtocol
        HttpsRedirect = $route.HttpsRedirect
        RuleSet = if ($null -ne $ruleSet) { $ruleSet.Name } else { '---' }
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