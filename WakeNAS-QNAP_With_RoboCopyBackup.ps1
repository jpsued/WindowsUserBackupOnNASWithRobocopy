# WakeNAS-QNAP_With_RoboCopyBackup.ps1
# small script to wake up NAS on i.e. Windows Start or user Login
# and to start incremental copy of changed files in actual user accound
# to be used in Aufgabensteuerung

# enfore some strict settings like variable declaration before usage
Set-StrictMode -Version Latest

# Set Logging - Level to DEBUG https://logging.readthedocs.io/en/latest/
#Add-LoggingTarget -Name Console -Configuration @{Level = 'DEBUG'; Format = '[%{filename}] [%{caller}] %{message}'}
#$DebugPreference = 'Continue'
$DebugPreference = 'Continue'
$InformationPreference = 'Continue'


# Import needed modules
# details about using modules https://stackoverflow.com/questions/27138483/how-can-i-re-use-import-script-code-in-powershell-scripts
Import-Module .\modules\WakeOnLan.psm1

# global vars and consts
# for difference of Constant and ReadOnly see https://tommymaynard.com/protect-your-variables-with-readonly-and-constant-options-2015/
#   and https://powershell.org/forums/topic/constants-in-powershell/
#Remove-Variable -Name "dest_hostname" -Force
New-Variable -Name "dest_hostname" -value "nas-qnap" -Scope global -Option ReadOnly -Force      # Name of NAS Server
#Remove-Variable -Name "dest_mac" -Force
New-Variable -Name "dest_mac" -value "24:5E:BE:40:CB:50" -Scope global -Option ReadOnly -Force    # MAC of NAS Server


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
    $maxWaitTimeSpan = New-TimeSpan -Seconds $MaxWaitTimeSec

    $start_date = Get-Date 
    $duration = 0

    Write-Debug "Check if network connectivity to $ServerName (MAC: $MAC) is given"
    
    # do until loop so that result can be stored and used for return value easily    
    do {
		# fire WakeOnLan IP-package independent of server status since it does not hurt and keeps this code easier :-)
		Write-Debug "Wake up $ServerName $MAC "
		Invoke-WakeOnLan -MacAddress $dest_mac # -Verbose

        $testResult = (Test-NetConnection -ComputerName $ServerName -CommonTCPPort SMB -InformationLevel "Quiet") #.TcpTestSucceeded -> only available in InformationLevel Detailed
        Write-Debug "run_count: $run_count - Test Result: $testResult"
        if ($testResult -ne "True")
        {
            # no connection -> wait some time before retry
            $run_count++
            Start-Sleep -Seconds $LoopWaitTimeSec
            $duration = New-TimeSpan -Start $start_date -End (Get-Date)
            Write-Debug ("Waiting for $ServerName to come up since $duration")
        }
    } until ( ($testResult -eq "True") -or ($duration -gt $maxWaitTimeSpan))

    $duration = New-TimeSpan -Start $start_date -End (Get-Date)
    Write-Information ("NAS startup duration: $duration")

    # return current network status
    return $testResult
  }


  $robocopy_block = {
    param($src, $dst, $exclude_dirs, $exclude_files, $log)
    #New-Item -Force $log | Out-Null
    # Execute a command
    #robocopy $src $dst /MIR /ZB /MT /XJ /XD $exclude_dirs /XF $exclude_files /R:3 /LOG:$log /NP
    robocopy $src $dst /MIR /MT /XJ /XD $exclude_dirs /XF $exclude_files /R:3 /LOG:$log /NP # /tee /L
        # /MIR  # mirroring the folders, removing non-existant files. We don't want lots of old files cluttering up the backup and the File Shares should keep a history on their own
        # /ZB   # copies files such that if they are interrupted part-way, they can be restarted (should be default IMHO)
        # /MT   # copies using multiple cores, good for many small files
        # /XJ   # Ignoring junctions, they can cause infinite loops when recursing through folders
        # /XD   # directories shouldn't have important data files
        # /XF   # exclude files
        # /R:3  # Retrying a file only 3 times, we don't want bad permissions or other dumb stuff to halt the entire backup
        # /LOG:$log # Logging to a file internally, the best way to log with the /MT flag
        # /NP   # Removing percentages from the log, they don't format well
        # /tee 	Schreibt die Status Ausgabe in das Konsolenfenster sowie in die Protokolldatei.
        # /m 	Kopiert nur Dateien, für die das Archive -Attribut festgelegt ist, und setzt das Archiv Attribut zurück.
        # /l    Gibt an, dass Dateien nur aufgelistet werden sollen (nicht kopiert, gelöscht oder Zeitstempel).    
    #"Backup directory is complete. [$src -> $dst] ($log)"
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
    $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    throw 
}


# Set Variables for further steps
$host_name = $env:COMPUTERNAME
$user_name = $env:USERNAME
$src_dir   = $env:USERPROFILE # $env:HOMEDRIVE + "\" + $env:HOMEPATH # Backup whole user directory
$dest_dir  = "\\$dest_hostname\$user_name\$host_name\"
$exclude_dirs = @("temp*", "*cache*", "*caching*", "thumbnails", "service", "session", "*cookies*", "update", "diagnostic", "logs",
                   "*UbuntuonWindows*", "QtWebEngine", "Programs\Microsoft VS Code", "mingw64", "*Microsoft.*", "*+++*",
                   "*datareporting*", "*.vscode*") #, "Chrome\User Data\*\Extensions", "\Edge\*\Snapshots")
$exclude_files = @("*cache*", "*.log", "*thumbnail*", "*.tmp", "*.lnk", "*.lock", "*.old", "NTUSER.DAT", "settings.dat")

$act_date  = Get-Date -Format yyyy-MM-dd
$myScriptName = $MyInvocation.MyCommand.Name.Replace(".ps1", "")
$log_file  = "$dest_dir" + $act_date + "_" + $myScriptName + ".log"

Write-Debug "act_date: $act_date myScriptName: $myScriptName log_file: $log_file"

# check if backup has been performed already today
if ( ! (Test-Path $log_file -PathType Leaf) )
{
    # Create Log-File since it does not exist yet (-force: create subdirs if not exiting)
    New-Item -ItemType "file" -Path $log_file -force

    # check existing log file for last entry eq SUCCESS !
    
    # Start backup
    Write-Debug "Start Backup for $host_name - User: $user_name  SourceLocation:$src_dir to DestLocation:$dest_dir "
    Set-Content -Path $log_file "Start Backup"

    $ret = Invoke-Command $robocopy_block -ArgumentList $src_dir, $dest_dir, $exclude_dirs, $exclude_files, $log_file #-Name "backup-$src_dir" #| Out-Null
    Write-Debug "Result of Robocopy: $ret"
    if ($ret -eq "TRUE") {
        # finalize Logfile
        Add-Content -Path $log_file  "SUCCESS"
    }
    


     # Inform User about backup status
     Get-Content  $log_file
}
else {
    Write-Host "Logfile $log_file already exists => no more backup today" -ForegroundColor Green
}



# exit programm
Write-Host "NAS $dest_hostname is now available! Press any key to close this window" -ForegroundColor Green
$host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

