# Ensure Azure CLI is installed and available
Write-Host "Checking Azure CLI installation..."
az --version | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Azure CLI is not installed. Exiting." -ForegroundColor Red
    exit 1
}

# Step 1: Login to Azure using environment variables or Device Code Flow
Write-Host "Logging in to Azure..."
if ($env:AZURE_CREDENTIALS) {
    try {
        Write-Host "Using Service Principal for login..."
        $creds = $env:AZURE_CREDENTIALS | ConvertFrom-Json
        az login --service-principal `
            --username $creds.clientId `
            --password $creds.clientSecret `
            --tenant $creds.tenantId | Out-Null
    } catch {
        Write-Host "Failed to login using Service Principal. Ensure credentials are correct." -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "Using Device Code Flow for login..."
    try {
        az login --use-device-code | Out-Null
    } catch {
        Write-Host "Failed to login using Device Code Flow. Exiting." -ForegroundColor Red
        exit 1
    }
}

# Verify login was successful
$loggedIn = az account show --query "id" -o tsv
if (-not $loggedIn) {
    Write-Host "Failed to log in to Azure. Exiting." -ForegroundColor Red
    exit 1
}
Write-Host "Azure login successful." -ForegroundColor Green

# Step 2: Retrieve Access Token from Azure CLI
Write-Host "Retrieving access token from Azure CLI..."
try {
    $accessToken = az account get-access-token --resource https://graph.microsoft.com --query accessToken -o tsv
    if (-not $accessToken) {
        throw "Access token retrieval failed."
    }
    Write-Host "Access token retrieved successfully." -ForegroundColor Green
} catch {
    Write-Host "Failed to retrieve access token. Ensure your account has appropriate permissions." -ForegroundColor Red
    exit 1
}

# Step 3: Define the initial Graph API request
$graphEndpoint = "https://graph.microsoft.com/v1.0/users"
$headers = @{
    "Authorization" = "Bearer $accessToken"
}

# Step 4: Create an array to store all users
$allUsers = @()

# Step 5: Loop through pagination to retrieve all users
do {
    try {
        # Fetch user data
        Write-Host "Fetching data from: $graphEndpoint"
        $response = Invoke-RestMethod -Uri $graphEndpoint -Headers $headers

        # Add retrieved users to the array
        if ($response.value) {
            $allUsers += $response.value
            Write-Host "Retrieved $($response.value.Count) users."
        }

        # Update endpoint for next page, if available
        $graphEndpoint = $response.'@odata.nextLink'
    } catch {
        Write-Host "An error occurred while fetching data: $($_.Exception.Message)" -ForegroundColor Red
        $graphEndpoint = $null # Stop the loop on error
    }
} while ($graphEndpoint)

# Step 6: Save all users to a CSV file
Write-Host "Saving users to CSV file..."
$csvFilePath = $PSScriptRoot + "\all_users.csv" # Save in the current script directory
try {
    $allUsers | Export-Csv -Path $csvFilePath -NoTypeInformation -Force
    Write-Host "Users saved to $csvFilePath" -ForegroundColor Green
} catch {
    Write-Host "Failed to save users to CSV file: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Step 7: Output summary
Write-Host "Total users retrieved: $($allUsers.Count)" -ForegroundColor Cyan
