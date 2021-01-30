# https://powershell.one/code/11.html
# New Wake-On-LAN Command
# Invoke-WakeOnLan takes one or more MAC addresses, composes the Magic Packet and sends it to the machines:

# Examples
# Before you can wake a remote computer, you need to know its MAC address.
# Identifying MAC Addresses
# You can use WMI to find it out. The WMI class Win32_NetworkAdapter represents all network adapters in a computer.
# This line lists the MAC address from all network adapters that are currently connected to a network:
#Get-CimInstance -Query 'Select * From Win32_NetworkAdapter Where NetConnectionStatus=2' | Select-Object -Property Name, Manufacturer, MacAddress
# Sending Magic Packet
# Provided you ran the code above to define Invoke-WakeOnLan, you can now send off a Magic Package to wake up the computer of choice.
# Simply submit its MAC address:
# Invoke-WakeOnLan -MacAddress '24:EE:9A:54:1B:E5'
# You can also wake a number of machines. Either submit the MAC addresses as a comma-separated list:
# Invoke-WakeOnLan -MacAddress '24:EE:9A:54:1B:E5', '98:E7:43:B5:B2:2F' -Verbose
# Or pipe the information:
# '24:EE:9A:54:1B:E5', '98:E7:43:B5:B2:2F' | Invoke-WakeOnLan -Verbose


function Invoke-WakeOnLan
{
  param
  (
    # one or more MACAddresses
    [Parameter(Mandatory,ValueFromPipeline,ValueFromPipelineByPropertyName)]
    # mac address must be a following this regex pattern:
    [ValidatePattern('^([0-9A-F]{2}[:-]){5}([0-9A-F]{2})$')]
    [string[]]
    $MacAddress 
  )
 
  begin
  {
    # instantiate a UDP client:
    $UDPclient = [System.Net.Sockets.UdpClient]::new()
  }
  process
  {
    foreach($_ in $MacAddress)
    {
      try {
        $currentMacAddress = $_
        
        # get byte array from mac address:
        $mac = $currentMacAddress -split '[:-]' |
          # convert the hex number into byte:
          ForEach-Object {
            [System.Convert]::ToByte($_, 16)
          }
 
        #region compose the "magic packet"
        
        # create a byte array with 102 bytes initialized to 255 each:
        $packet = [byte[]](,0xFF * 102)
        
        # leave the first 6 bytes untouched, and
        # repeat the target mac address bytes in bytes 7 through 102:
        6..101 | Foreach-Object { 
          # $_ is indexing in the byte array,
          # $_ % 6 produces repeating indices between 0 and 5
          # (modulo operator)
          $packet[$_] = $mac[($_ % 6)]
        }
        
        #endregion
        
        # connect to port 400 on broadcast address:
        $UDPclient.Connect(([System.Net.IPAddress]::Broadcast),4000)
        
        # send the magic packet to the broadcast address:
        $null = $UDPclient.Send($packet, $packet.Length)
        Write-Verbose "sent magic packet to $currentMacAddress..."
      }
      catch 
      {
        Write-Warning "Unable to send ${mac}: $_"
      }
    }
  }
  end
  {
    # release the UDF client and free its memory:
    $UDPclient.Close()
    $UDPclient.Dispose()
  }
}

