# WindowsUserBackupOnNASWithRobocopy
When using witin Windows Autostart of an user account the script
1. checks if specified NAS is up and running
2. is waking up NAS in case it's sleepin
3. runs a differntial backup of the %USERPROFILE% directories and files using robocopy
