Param([object]$WebhookData)

$eventData = (ConvertFrom-Json -InputObject $WebhookData.RequestBody)

if ($eventData.subject -match 'microsoft.compute/virtualmachines') {
    $vmName = $eventData.subject.Split('/')[8]
    $vmResourceGroupName = $eventData.subject.Split('/')[4]

    Connect-AzAccount -Identity

    $storageAccountName = Get-AutomationVariable "StorageAccountName"
    $resourceGroupName = Get-AutomationVariable "ResourceGroupName"

    $ctx = (Get-AzStorageAccount -ResourceGroupName $resourceGroupName -Name $storageAccountName).Context

    $sasUri = New-AzStorageBlobSASToken -Blob 'PowerShell-7.1.3-win-x64.msi' -Container software -Permission r -ExpiryTime (Get-Date).AddMinutes(30) -Context $ctx -FullUri


    $scriptBlock = @'
$sasUri = "VALUE"

Invoke-WebRequest -Uri $sasUri -OutFile "$env:TEMP\PowerShell-7.1.3-win-x64.msi" -Verbose

Start-Process "$env:Temp\PowerShell-7.1.3-win-x64.msi" -ArgumentList "/quiet /norestart" -Verbose
'@

    $scriptBlock | Out-File $env:Temp\script.ps1

    (Get-Content $env:Temp\script.ps1 -Raw) -replace "VALUE", $sasUri | Set-Content $env:Temp\script.ps1 -Force

 Write-verbose "Trying command:  Invoke-AzVMRunCommand" 
           $StartTime = Get-Date
           ## Attempting to run the Invoke-AzVMRunCommand against a VM that is not available will cause a 90 minute timeout
           $VMstatus = Get-AzVM -ResourceGroupName $vmResourceGroupName -Name $vmName -Status
           if ($VMstatus) 
             {
                if ($VMstatus.VMAgent.Statuses[0].Code -eq "ProvisioningState/succeeded") 
                {

                  "Running Invoke-AzVMRunCommand -ResourceGroupName $vmResourceGroupName -Name $vmName ..."
                  $Results = Invoke-AzVMRunCommand -ResourceGroupName $vmResourceGroupName -VMName $vmName -ScriptPath $env:Temp\script.ps1 -CommandId 'RunPowerShellScript' -Verbose
                  "Result: " + $Results.Value.message
                }
                else 
                {
                  Write-verbose "$vmName is not ready for Invoke-AzVMRunCommad"
                }
             }
           $EndTime = Get-Date
           If ($Results) {
               "    $VMName Finished    TotalSeconds: " + $EndTime.Subtract($StartTime).TotalSeconds + "  with "  + $Results.Status
              }  
           else  ## If $Result is NULL
           {   Write-verbose "Retrying command:  Invoke-AzVMRunCommand"   ## Note this will only show up if the runbook "Logging and Tracing" is enabled with Verbose
               Start-sleep -seconds 180  # VM extension will only process one command at a time, if you get a 
                                        # 409 "Run command extension execution is in progress. Please wait for completion before invoking a run command" 
                                        # you must wait and retry.  This might need additional time or possibly another retry.
               $StartTime = Get-Date
               $VMstatus = Get-AzVM -ResourceGroupName $VMRG -Name $VMName -Status
               if ($VMstatus) 
                 {
                   if ($VMstatus.VMAgent.Statuses[0].Code -eq "ProvisioningState/succeeded") 
                       {
                         "Running Invoke-AzVMRunCommand -ResourceGroupName $vmResourceGroupName -Name $vmName ..."
                         $Results = Invoke-AzVMRunCommand -ResourceGroupName $vmResourceGroupName -VMName $vmName -ScriptPath $env:Temp\script.ps1 -CommandId 'RunPowerShellScript' -Verbose
                         "Result2: " + $Results.Value.message
                       }
                 }
               else 
                 {
                   Write-verbose "$VMName is not ready for Invoke-AzVMRunCommad"
                 }
               if (!$Results) {$ErrMessage = $error[0].Exception.Message}  ## If $Result is NULL
               $EndTime = Get-Date
               If ($Results) {"    $VMName Finished    TotalSeconds: " + $EndTime.Subtract($StartTime).TotalSeconds + "  with "  + $Results.Status}
               else {    "    $VMName  Error: " + $ErrMessage}
           } 

}
else {
    Write-Output "Event subject does not match microsoft.compute"
}

