# get-classicafdcertificates.ps1

## Overview

 Azure Front Door classic is disabling Azure managed TLS certificate provisioning.

`get-classicafdcertificates.ps1` is a PowerShell script designed to help Azure administrators retrieve and report on the TLS/SSL certificate configuration of Azure Front Door (classic) instances across multiple Azure subscriptions. It collects information about managed and Key Vault-based certificates used by Front Door frontend endpoints, including details such as certificate source, provisioning state, Key Vault names, and minimum TLS versions.

The script can be used to check which instances and profiles of Azure Front Door (Classic) are using managed certificates.

## Features
- Enumerates all Azure subscriptions matching a filter (by name).
- Lists all Azure Front Door (classic) instances in each subscription.
- Retrieves all frontend endpoints for each instance.
- Collects certificate details for each endpoint, including:
  - Certificate source (Front Door managed or Key Vault)
  - Custom HTTPS provisioning state
  - Key Vault name and secret name (if applicable)
  - Minimum TLS version
- Outputs results in a table format in the console.
- Optionally exports results to a CSV file for further analysis or reporting.

## Prerequisites
- PowerShell 7 (Core Edition)
- Az PowerShell modules, especially `Az.Accounts` and `Az.FrontDoor`
- Sufficient Azure permissions to read subscription and Front Door resources
- Logged in to Azure via `Connect-AzAccount`

## Usage

### Basic Usage
Run the script in a PowerShell terminal:

```powershell
./get-classicafdcertificates.ps1
```

This will process all subscriptions and display the results in the console.

### Filtering Subscriptions
To filter subscriptions by name (e.g., only those containing "PRODUZIONE"):

```powershell
./get-classicafdcertificates.ps1 -SubscriptionFilter '*PRODUZIONE*'
```

### Exporting to CSV
To export the results to a CSV file:

```powershell
./get-classicafdcertificates.ps1 -ExportCsvPath './output.csv'
```

You can combine both parameters as needed.

## Output
- Console table of certificate details for each Front Door (classic) endpoint.
- Optional CSV file with the same information if `-ExportCsvPath` is specified.

## Example
```powershell
./get-classicafdcertificates.ps1 -SubscriptionFilter '*PROD*' -ExportCsvPath './afd-certs.csv'
```

## Notes
- The script only processes Azure Front Door (classic) resources, not Standard/Premium Front Door.
- Make sure you have the necessary permissions and modules installed before running the script.

## Author
Marcello Formica
