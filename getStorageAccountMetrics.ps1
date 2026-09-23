
<# 
DISCLAIMER - By downloading / using these scripts you are agreeing that they are "Use at your own risk" and I will not be held responsible for any impact. Please make sure they will work for your need!
These sample scripts are not supported under any Microsoft standard support program or service. The sample scripts
are provided AS IS without warranty of any kind. Microsoft further disclaims all implied warranties including, wihout
limitation, any implied warranties of merchantability or of fitness for a particular purpose. The entire risk arising
out of the use or performance of the sample scripts and documentation remains with you. In no event shall Microsoft,
its authors, or anyone else involved in the creation, production, or delivery of the scripts be liable for any damages
whatsoever (including, without limitation, damages for loss of business profits, business interruption, loss of business
information, or other pecuniary loss) arising out of the use of or inability to use the sample scripts or documentation,
even if Microsoft has been advised of the possibility of such damages. 
#>

# collect a few metrics for all storage accounts in subid

$sub = (Get-AzContext -ErrorAction SilentlyContinue).Subscription
if ($sub -eq $null)
    {
        "Login to Azure... Please set the target subscription with Set-AzContext <subid> if needed."
        Add-AzAccount
    }
    else{
            $sub = (Get-AzContext -ErrorAction Stop).Subscription
        }

Write-Host "`n`nGetting a list of all Storage Accounts on subscription $sub...`n"
$accounts = Get-AzStorageAccount -ErrorAction Stop
$start = (Get-Date).AddDays(-90)
$start1day = (Get-Date).AddDays(-1)
$end = Get-Date
$i = 0
$ct = $accounts.Length

# TESTING - target v1
#$accounts = $accounts|?{$_.StorageAccountName -like "javanstorev1"}

$result = foreach ($sa in $accounts)
{

$usedcap = $null
$UsedCapacityGB = $null
$transactions = $null
$ingress = $null
$egress = $null
$metric = $null

    $i++
    Write-Host "Collecting Metrics on storage account '$($sa.StorageAccountName)' ($i of $ct)"
    # grab ingress,egress,transactions with 'total' aggregation
    $metric = Get-AzMetric `
        -ResourceId $sa.Id `
        -MetricName Transactions,Ingress,Egress `
        -StartTime $start `
        -EndTime $end `
        -AggregationType Total `
        -WarningAction SilentlyContinue

     #storage v1 accounts dont seem to have capacity metric?? skip
     if ($($sa.Kind) -eq "Storage")
     {
         $UsedCapacityGB = "N/A"
     }
     else
     {     
        # grab usedCapacity with 'average' aggregation (doesn't support total), and only look back 1 day to get current used capacity.
        $metricusedcapacity = Get-AzMetric `
        -ResourceId $sa.Id `
        -MetricName UsedCapacity `
        -StartTime $start1day `
        -EndTime $end `
        -AggregationType Average `
        -WarningAction SilentlyContinue

        $usedcap = ($metricusedcapacity.Data | Where-Object {$_.Name -ne $_.Average})[-1].Average
        if ($usedcap -eq $null){$UsedCapacityGB = "N/A"}
        else{$UsedCapacityGB = [math]::Round(($usedcap) / 1MB,2)}
    }

    $transactions = $metric | Where-Object {$_.Name.Value -like 'Transactions' }
    $ingress = $metric | Where-Object { $_.Name.Value -eq 'Ingress' }
    $egress = $metric | Where-Object { $_.Name.Value -eq 'Egress' }

    # create output        

    [pscustomobject]@{
        SubscriptionID = $sub.SubscriptionId
        StorageAccountName = $sa.StorageAccountName
        Kind = "$($sa.Kind)"
        SKU = "$($sa.Sku.Name)"
        ResourceGroup  = $sa.ResourceGroupName
        UsedCapacityMB = $UsedCapacityGB | Sort-Object TimeStamp | Select-Object
        transactions90d = ($transactions.Data.Total | Measure-Object -Sum).Sum
        IngressMB90d = [math]::Round((($ingress.Data.Total | Measure-Object -Sum).Sum) / 1MB, 2)
        EgressMB90d = [math]::Round((($egress.Data.Total | Measure-Object -Sum).Sum) / 1MB, 2)
    }
}

"`nRESULTS:`n"

if ($result -eq $null){"`nNo Metrics Found. Check Access, scope, etc...`n";return}
$result | ft

Write-Host "`nSaving results to file:  .\storage-transactions-$($sub.subscriptionId).csv`n"
$result | Export-Csv .\storage-transactions-$($sub.subscriptionId).csv -NoTypeInformation  

