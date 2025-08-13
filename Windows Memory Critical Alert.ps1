<#
.SYNOPSIS
Automate memory critical alert incident steps.

.DESCRIPTION
The script checks server availability, retrieves memory usage,
sends alert email if memory usage exceeds threshold,
and attaches a screenshot of memory status if resolved.

.NOTES
Requires admin privileges and network access.
#>

# Configurations
$jumpbox = "JXN-MS-ADMIN1"
$jumpboxUser = "HBC\FID"
$server = "JXN-MS-AMSBD1"
$serverIP = "10.237.XX.XXX"  # replace with actual IP
$memoryThresholdPercent = 80
$smtpServer = "smtp.yourcompany.com"
$smtpFrom = "alerts@yourcompany.com"
$smtpTo = "owner@company.com"  # Ideally fetched dynamically from CMDB or portal tags
$smtpPort = 587
$smtpUser = "smtpuser"
$smtpPass = "smtppassword"

# Function to ping the server
function Test-ServerPing {
    param([string]$ip)
    Test-Connection -ComputerName $ip -Count 2 -Quiet
}

# Function to get memory usage remotely
function Get-MemoryUsage {
    param([string]$computerName)

    $mem = Get-CimInstance -ClassName Win32_OperatingSystem -ComputerName $computerName -ErrorAction Stop

    $totalMemoryMB = [math]::Round($mem.TotalVisibleMemorySize / 1024, 2)
    $freeMemoryMB = [math]::Round($mem.FreePhysicalMemory / 1024, 2)
    $usedMemoryMB = $totalMemoryMB - $freeMemoryMB
    $usedPercent = [math]::Round(($usedMemoryMB / $totalMemoryMB) * 100, 2)

    return [PSCustomObject]@{
        TotalMB = $totalMemoryMB
        FreeMB = $freeMemoryMB
        UsedMB = $usedMemoryMB
        UsedPercent = $usedPercent
    }
}

# Function to take memory screenshot (simulate by saving info to a file)
function Save-MemorySnapshot {
    param([string]$computerName, [string]$outputPath)
    $memInfo = Get-MemoryUsage -computerName $computerName
    $content = @"
Memory Snapshot for $computerName - $(Get-Date)

Total Memory (MB): $($memInfo.TotalMB)
Free Memory (MB): $($memInfo.FreeMB)
Used Memory (MB): $($memInfo.UsedMB)
Used Percent: $($memInfo.UsedPercent)%
"@

    $content | Out-File -FilePath $outputPath -Encoding utf8
    return $outputPath
}

# Step 1 & 2: Incident acknowledged manually (outside script)
Write-Output "Incident acknowledged and in progress..."

# Step 6: Ping test
if (-not (Test-ServerPing -ip $serverIP)) {
    Write-Error "Server $server ($serverIP) is not reachable via ping."
    exit 1
}

Write-Output "Server $server ($serverIP) is reachable."

# Step 8: Get memory usage
try {
    $memUsage = Get-MemoryUsage -computerName $server
    Write-Output "Memory used: $($memUsage.UsedPercent)% (Threshold: $memoryThresholdPercent%)"
} catch {
    Write-Error "Failed to get memory usage on $server. $_"
    exit 1
}

# Step 9: Decide action based on memory usage
if ($memUsage.UsedPercent -ge $memoryThresholdPercent) {
    # Memory critical: send alert mail
    $subject = "Memory Critical Alert on Server $server"
    $body = @"
Dear Server Owner,

The physical memory usage on server $server ($serverIP) has reached $($memUsage.UsedPercent)%, which exceeds the threshold of $memoryThresholdPercent%.

Please investigate and take necessary actions.

Regards,
Automated Alert System
"@

    Write-Output "Sending memory alert email..."
    Send-MailMessage -From $smtpFrom -To $smtpTo -Subject $subject -Body $body -SmtpServer $smtpServer -Port $smtpPort -UseSsl `
        -Credential (New-Object System.Management.Automation.PSCredential($smtpUser, (ConvertTo-SecureString $smtpPass -AsPlainText -Force))) -BodyAsHtml:$false
    Write-Output "Alert email sent."

} else {
    # Memory usage OK: resolve incident with snapshot
    $snapshotPath = Join-Path -Path $env:TEMP -ChildPath "MemorySnapshot_$server.txt"
    Save-MemorySnapshot -computerName $server -outputPath $snapshotPath | Out-Null

    # Send resolution mail with snapshot attachment
    $subject = "Memory Alert Resolved on Server $server"
    $body = @"
Dear Team,

The memory usage on server $server ($serverIP) is currently $($memUsage.UsedPercent)% which is below the threshold of $memoryThresholdPercent%.

Incident resolved. Please find attached the memory usage snapshot for records.

Regards,
Automated Alert System
"@

    Write-Output "Sending resolution email..."
    Send-MailMessage -From $smtpFrom -To $smtpTo -Subject $subject -Body $body -Attachments $snapshotPath -SmtpServer $smtpServer -Port $smtpPort -UseSsl `
        -Credential (New-Object System.Management.Automation.PSCredential($smtpUser, (ConvertTo-SecureString $smtpPass -AsPlainText -Force))) -BodyAsHtml:$false
    Write-Output "Resolution email sent."

    # Incident closure logic here (e.g., API call) - outside scope of this script
}

