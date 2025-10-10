#Requires -PSEdition Core
using module Az.Accounts

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, HelpMessage = 'Name of the Front Door Standard/Premium profile to inspect')]
    [string]$FrontDoorName,

    [Parameter(Mandatory = $false, HelpMessage = 'Path to export CSV results (optional)')]
    [string]$ExportCsvPath,

    [Parameter(Mandatory = $false, HelpMessage = 'API version to use for Front Door REST calls (override if needed)')]
    [string]$ApiVersion = '2024-02-01'
)

Set-StrictMode -Version 1
$ErrorActionPreference = 'Stop'

$results = @()

# Get current context
$context = Get-AzContext
if (-not $context) {
    throw "Not logged in to Azure. Please run Connect-AzAccount first."
}

Write-Host "Looking for Front Door profile: $FrontDoorName..."

# Find the Front Door Standard/Premium resource
$fd = Get-AzResource -Name $FrontDoorName -ResourceType "Microsoft.Cdn/profiles" -ErrorAction SilentlyContinue

if (-not $fd) {
    throw "Front Door profile '$FrontDoorName' not found in current subscription."
}

$fdName = $fd.Name
$rgName = $fd.ResourceGroupName
$subscriptionId = $context.Subscription.Id

Write-Host "Found: $fdName in resource group: $rgName"
Write-Host "Retrieving custom domains..."

# Get custom domains via REST API
try {
    $pathDomains = "/subscriptions/$subscriptionId/resourceGroups/$rgName/providers/Microsoft.Cdn/profiles/$fdName/customDomains?api-version=$ApiVersion"
    $domainsResp = Invoke-AzRest -Path $pathDomains -Method GET -ErrorAction Stop
    $domains = ($domainsResp.Content | ConvertFrom-Json).value
}
catch {
    throw "Failed to query custom domains for ${fdName}: $($_.Exception.Message)"
}

if (-not $domains -or $domains.Count -eq 0) {
    Write-Host "No custom domains found for $fdName" -ForegroundColor Yellow
}
else {
    Write-Host "Found $($domains.Count) custom domain(s). Processing..."

    foreach ($d in $domains) {
        # Initialize fields
        $certSource = $null
        $provisioningState = $null
        $expiryDate = $null
        $keyVaultName = $null
        $keyVaultSecretName = $null
        $validationState = $null
        $subject = $null
        
        $domainName = $d.properties.hostName
        if (-not $domainName) { $domainName = $d.name }

        # Get provisioning state
        if ($d.properties.provisioningState) { $provisioningState = $d.properties.provisioningState }
        if ($d.properties.domainValidationState) { $validationState = $d.properties.domainValidationState }

        # Get TLS settings
        if ($d.properties.tlsSettings) {
            $tls = $d.properties.tlsSettings
            if ($tls.certificateType) { 
                $certSource = switch ($tls.certificateType) {
                    'ManagedCertificate' { 'Managed' }
                    'CustomerCertificate' { 'KeyVault' }
                    default { $tls.certificateType }
                }
            }
            
            # Fetch certificate details from secret
            if ($tls.secret -and $tls.secret.id) {
                $secretId = $tls.secret.id
                
                try {
                    Write-Host "  Fetching certificate details for: $domainName..." -NoNewline
                    $secretPath = "$secretId`?api-version=$ApiVersion"
                    $secretResp = Invoke-AzRest -Path $secretPath -Method GET -ErrorAction Stop
                    $secret = ($secretResp.Content | ConvertFrom-Json)
                    
                    if ($secret.properties -and $secret.properties.parameters) {
                        $params = $secret.properties.parameters
                        
                        if ($params.expirationDate) { 
                            $expiryDate = $params.expirationDate 
                        }
                        if ($params.subject) {
                            $subject = $params.subject
                        }
                        
                        # For Customer Certificates, extract Key Vault details
                        if ($params.type -eq 'CustomerCertificate' -and $params.secretSource -and $params.secretSource.id) {
                            $kvSecretId = $params.secretSource.id
                            if ($kvSecretId -match '/vaults/([^/]+)/') { $keyVaultName = $matches[1] }
                            if ($kvSecretId -match '/secrets/([^/]+)') { $keyVaultSecretName = $matches[1] }
                        }
                    }
                    Write-Host " OK" -ForegroundColor Green
                }
                catch {
                    Write-Host " Failed" -ForegroundColor Yellow
                }
            }
        }

        # Add warning indicators for non-success states
        $provisioningDisplay = $provisioningState
        if ($provisioningState -and $provisioningState -ne 'Succeeded') {
            $provisioningDisplay = "⚠️ $provisioningState"
        }
        
        $validationDisplay = $validationState
        if ($validationState -and $validationState -ne 'Approved') {
            $validationDisplay = "⚠️ $validationState"
        }

        # Check expiration date and add indicators
        $expiryDisplay = $expiryDate
        $expiryStatus = 'OK'
        if ($expiryDate) {
            try {
                # Handle both string and DateTime objects
                if ($expiryDate -is [DateTime]) {
                    $expiryDateTime = $expiryDate
                } else {
                    $expiryDateTime = [DateTime]::Parse($expiryDate)
                }
                
                # Format the date using locale settings
                $formattedDate = $expiryDateTime.ToString()
                
                $now = Get-Date
                $daysUntilExpiry = ($expiryDateTime - $now).Days
                
                if ($daysUntilExpiry -lt 0) {
                    $expiryDisplay = "🔴 $formattedDate (EXPIRED)"
                    $expiryStatus = 'EXPIRED'
                }
                elseif ($daysUntilExpiry -le 30) {
                    $expiryDisplay = "⚠️ $formattedDate (expires in $daysUntilExpiry days)"
                    $expiryStatus = 'WARNING'
                }
                else {
                    $expiryDisplay = $formattedDate
                }
            }
            catch {
                # If date parsing fails, use the original value
            }
        }

        $result = [PSCustomObject]@{
            Domain             = $domainName
            CertificateType    = $certSource
            ProvisioningState  = $provisioningDisplay
            ValidationState    = $validationDisplay
            Subject            = $subject
            ExpirationDate     = $expiryDisplay
            ExpirationStatus   = $expiryStatus
            KeyVaultName       = $keyVaultName
            KeyVaultSecretName = $keyVaultSecretName
        }

        $results += $result
    }
}

# Output
if ($results.Count -eq 0) {
    Write-Host "No certificate information found." -ForegroundColor Yellow
}
else {
    Write-Host "`nCertificate Details:" -ForegroundColor Green
    Write-Host ""
    
    # Display column headers
    Write-Host ("{0,-50} {1,-12} {2,-25} {3,-20} {4,-50} {5,-35} {6,-20} {7}" -f "Domain", "CertType", "ProvisioningState", "ValidationState", "Subject", "ExpirationDate", "KeyVaultName", "KeyVaultSecretName") -ForegroundColor Cyan
    Write-Host ("{0,-50} {1,-12} {2,-25} {3,-20} {4,-50} {5,-35} {6,-20} {7}" -f "------", "--------", "-----------------", "---------------", "-------", "--------------", "------------", "------------------") -ForegroundColor Cyan
    
    # Display results with color coding
    foreach ($result in $results) {
        # Domain and certificate type
        Write-Host ("{0,-50} {1,-12}" -f $result.Domain, $result.CertificateType) -NoNewline
        
        # Provisioning State with color
        if ($result.ProvisioningState -and $result.ProvisioningState -notlike '*Succeeded*') {
            Write-Host ("{0,-25}" -f $result.ProvisioningState) -NoNewline -ForegroundColor Yellow
        } else {
            Write-Host ("{0,-25}" -f $result.ProvisioningState) -NoNewline
        }
        
        # Validation State with color
        if ($result.ValidationState -and $result.ValidationState -notlike '*Approved*') {
            Write-Host ("{0,-20}" -f $result.ValidationState) -NoNewline -ForegroundColor Yellow
        } else {
            Write-Host ("{0,-20}" -f $result.ValidationState) -NoNewline
        }
        
        # Subject
        Write-Host ("{0,-50}" -f $result.Subject) -NoNewline
        
        # Expiration Date with color based on status
        if ($result.ExpirationStatus -eq 'EXPIRED') {
            Write-Host ("{0,-35}" -f $result.ExpirationDate) -NoNewline -ForegroundColor Red
        } elseif ($result.ExpirationStatus -eq 'WARNING') {
            Write-Host ("{0,-35}" -f $result.ExpirationDate) -NoNewline -ForegroundColor Yellow
        } else {
            Write-Host ("{0,-35}" -f $result.ExpirationDate) -NoNewline
        }
        
        # Key Vault details
        $line2 = "{0,-20} {1}" -f $result.KeyVaultName, $result.KeyVaultSecretName
        Write-Host $line2
    }
    
    Write-Host ""
    
    # Summary of issues
    $expired = ($results | Where-Object { $_.ExpirationStatus -eq 'EXPIRED' }).Count
    $expiringSoon = ($results | Where-Object { $_.ExpirationStatus -eq 'WARNING' }).Count
    
    if ($expired -gt 0) {
        Write-Host "🔴 $expired certificate(s) EXPIRED" -ForegroundColor Red
    }
    if ($expiringSoon -gt 0) {
        Write-Host "⚠️  $expiringSoon certificate(s) expiring within 30 days" -ForegroundColor Yellow
    }
    if ($expired -eq 0 -and $expiringSoon -eq 0) {
        Write-Host "✅ All certificates are valid and not expiring soon" -ForegroundColor Green
    }
}

if ($ExportCsvPath) {
    $results | Export-Csv -Path $ExportCsvPath -NoTypeInformation -Force
    Write-Host "Results exported to $ExportCsvPath"
}
