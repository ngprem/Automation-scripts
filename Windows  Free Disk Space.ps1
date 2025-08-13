<#
.SYNOPSIS
Automate disk space check and incident management for server alerts.

.DESCRIPTION
This script acknowledges disk space alert incidents, checks free space, identifies large folders,
and emails owners to remediate low disk space issues.

.NOTES
Run on admin machine with access to jumpbox and servers via RDP or Invoke-Command.

#>

# Configurations - adjust as needed
$jumpbox = "JXN-MS-ADMIN1"
$jumpboxUser = "HBC\FID"
$server = "JXN-MS-VERTX1"
$serverIP = "10.237.64.190"
$thresholdPercent = 20  # minimum free space percent to maintain
$smtpServer = "smtp.yourcompany.com"
$smtpFrom = "alerts@yourcompany.com"
$smtpPort = 587
$smtpUser = "smtpuser"
$smtpPass = "smtppassword"
$mailOwnerList = @() # This will be filled later based on portal tags

# Function: Check disk free space remotely
function Get-FreeDiskSpace {
    param($computerName, $driveLetter="C")
    $script = @"
    Get-PSDrive -Name $driveLetter | Select-Object Used, Free, @{Name='Total';Expression={\$_.Used + \$_.Free}}, @{Name='FreePercent';Expression={[math]::Round(\$_.Free/(\$_.Used + \$_.Free)*100,2)}}
"@
    Invoke-Command -ComputerName $computerName -ScriptBlock {Invoke-Expression $using:script}
}

# Function: Get large folders (simulate TreeSize)
function Get-LargeFolders {
    param($computerName, $path="C:\")
    $script = @"
    Get-ChildItem -Path $path -Directory | ForEach-Object {
        \$size = (Get-ChildItem -Path \$_.FullName -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
        [PSCustomObject]@{Folder=\$_.FullName; SizeGB = [math]::Round(\$size/1GB,2)}
    } | Sort-Object -Property SizeGB -Descending | Select-Object -First 10
"@
    Invoke-Command -ComputerName $computerName -ScriptBlock {Invoke-Expression $using:script}
}

# Step 1: Acknowledge Incident - Assume manual or API based outside this script

# Step 2 to Step 8: Check Disk Space
try {
    $diskInfo = Get-FreeDiskSpace -computerName $server
    $freePercent = $diskInfo.FreePercent

    Write-Output "Free disk space on $server C: drive is $freePercent%."

    if ($freePercent -lt $thresholdPercent) {
        # Step 9: Identify large folders
        Write-Output "Disk free space below threshold. Identifying large folders..."
        $largeFolders = Get-LargeFolders -computerName $server -path "C:\"

        # Here you can add logic to identify problematic folders such as logs, dumps, user folders, etc.
        Write-Output "Top large folders:"
        $largeFolders | Format-Table -AutoSize

        # Step 11: Compose and send mail to owner
        # For demo, let's assume we have the owner emails
        $mailOwnerList = @("owner1@company.com", "appteam@company.com")

        $subject = "Urgent: Low Disk Space Alert on $server (C: Drive)"
        $body = @"
Dear Server Owner / Application Team,

The C:\ drive on server $server (IP: $serverIP) has only $freePercent% free space left, below the required $thresholdPercent% threshold.

Top large directories consuming disk space:
$( $largeFolders | ForEach-Object { "$($_.Folder) - $($_.SizeGB) GB" } -join "`n")

Please take immediate action to clean up unnecessary files, archive old logs, or request disk expansion through Change Request.

This alert was generated automatically.

Regards,
Automated Disk Space Monitoring
"@

        Write-Output "Sending alert email to owners..."
        Send-MailMessage -From $smtpFrom -To $mailOwnerList -Subject $subject -Body $body -SmtpServer $smtpServer -Port $smtpPort -UseSsl -Credential (New-Object System.Management.Automation.PSCredential($smtpUser,(ConvertTo-SecureString $smtpPass -AsPlainText -Force))) -BodyAsHtml:$false

        Write-Output "Alert email sent."

    } else {
        Write-Output "Disk space is sufficient. No action required."
    }
} catch {
    Write-Error "Error checking disk space or sending email: $_"
}

# End of Script
