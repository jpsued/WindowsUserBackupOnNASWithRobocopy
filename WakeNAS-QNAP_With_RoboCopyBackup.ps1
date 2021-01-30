# WakeNAS-QNAP_With_RoboCopyBackup.ps1
# small script to wake up NAS on i.e. Windows Start or user Login
# and to start incremental copy of changed files in actual user accound
# to be used in Aufgabensteuerung

# enfore some strict settings like variable declaration before usage
Set-StrictMode -Version Latest

# Set Logging - Level to DEBUG https://logging.readthedocs.io/en/latest/
#Add-LoggingTarget -Name Console -Configuration @{Level = 'DEBUG'; Format = '[%{filename}] [%{caller}] %{message}'}
$DebugPreference = 'Continue'


# Import needed modules
# details about using modules https://stackoverflow.com/questions/27138483/how-can-i-re-use-import-script-code-in-powershell-scripts
Import-Module .\modules\WakeOnLan.psm1

# global vars and consts
Set-Variable -Name "dest_hostname" -value "nas-qnap" -Scope global -Option constant        # Name of NAS Server
Set-Variable -Name "dest_mac" -value "24:5E:BE:40:CB:50" -Scope global -Option Constant    # MAC of NAS Server


function CheckIfNASisAavailable (
     ### checks if specified SMB Server is available
     ### if not, it tries to Wake up the Server
     $ServerName               # SMB Server Name
    ,$MAC                      # MAC Address of Server
    ,$MaxWaitTimeSec=5*60      # max. Warttime for whole check 5min    
    ,$LoopWaitTImeSec=10       # Sec. waittime between connectivity checks
    ) 
{
    $run_count = 0
    $total_time = 0

    Write-Debug "Check if network connectivity to $ServerName (MAC: $MAC) is given"
    
    # do until loop so that result can be stored and used for return value easily    
    do {
		# fire WakeOnLan IP-package independent of server status since it does not hurt and keeps this code easier :-)
		Write-Debug "Wake up $ServerName $MAC "
		Invoke-WakeOnLan -MacAddress $dest_mac -Verbose

        $testResult = (Test-NetConnection -ComputerName $ServerName -CommonTCPPort SMB).TcpTestSucceeded
        Write-Debug "run_count: $run_count - Test Result: $testResult"
        if ($testResult -ne "True")
        {
            # no connection -> wait some time before retry
            $run_count++
            Start-Sleep -Seconds $LoopWaitTimeSec
            $total_time = $run_count * $LoopWaitTimeSec
            Write-Debug ("Waiting for $ServerName to come up since $total_time seconds")
        }
    } until ( ($testResult -eq "True") -or ($total_time -gt $MaxWaitTimeSec))

    # return current network status
    return $testResult
  }



###
### main ###
###

# Check if NAS is available
$ret = CheckIfNASisAavailable -ServerName $dest_hostname -MAC $dest_mac
Write-Debug "CheckIfNASisAvailable Result: $ret" 
if ( $ret -ne "True" )
{
    Write-Error "NAS $dest_hostname is not available => please check or inform your Administrator !!! Press any key to close this window" 
    $x = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    throw 
}



# check if backup has been performed already today
# by looking at Log-File change date

# When backup is needed wait for NAS being available

# Start backup
#$host_name, $user_name = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name -split "\\"
#$homedir = (Get-AdUser -filter {name -eq $user_name} -properties *).HomeDirectory  # Problem Get-AdUser nicht Standard in Win10 
$host_name = $env:COMPUTERNAME
$user_name = $env:USERNAME
$src_dir   = $env:USERPROFILE # $env:HOMEDRIVE + "\" + $env:HOMEPATH # Backup whole user directory
$dest_dir  = "\\$dest_hostname\$user_name\$host_name\"

Write-Debug "Start Backup for $host_name - User: $user_name  SourceLocation:$src_dir to DestLocation:$dest_dir "

# Inform User about backup status

# exit programm
Write-Host "NAS $dest_hostname is now available! Press any key to close this window" -ForegroundColor Green
$x = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

