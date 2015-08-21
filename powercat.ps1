<#
  .SYNOPSIS
    Netcat: The powershell version.
  .PARAMETER c
    Client mode: Provide an server to connect to.
  .PARAMETER l
    Listen mode: Use this switch to create a listener.
  .PARAMETER p
    The port to listen on, or the port to connect to.
  .PARAMETER e
    GAPING_SECURITY_HOLE :)
  .PARAMETER r
    Relay. Formats: "-r 10.1.1.1:443", "-r 443"
  .PARAMETER t
    Timeout for connecting and listening in seconds. Default is 60.
#>
function powercat
{
  param(
    [string]$c="",
    [Parameter(Mandatory=$True,Position=-1)][string]$p="",
    [switch]$l=$False,
    [string]$e="",
    [string]$r="",
    [Parameter(ValueFromPipeline=$True)][string]$i="",
    $t=60
  )
  
  if($l)
  {
    $Failure = $False
    netstat -na | Select-String LISTENING | % {if(($_.ToString().split(":")[1].split(" ")[0]) -eq $p){Write-Output ("The selected port " + $p + " is already in use.") ; $Failure=$True}}
    if($Failure){break}
  }
  if(($c -eq "") -and (!$l))
  {
    return "You must select either client mode (-c) or listen mode (-l)."
  }

  [console]::TreatControlCAsInput=$True

  function Listen
  {
    param($p,$t)
  
    Write-Verbose ("Listening on [0.0.0.0] (port " + $p + ")")
    $Socket = New-Object System.Net.Sockets.TcpListener $p
    $Socket.Start()
    $AcceptHandle = $Socket.BeginAcceptTcpClient($null, $null)
    $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    while($True)
    {
      if($Host.UI.RawUI.KeyAvailable)
      {
        Read-Host
      }
      if($Stopwatch.Elapsed.TotalSeconds -gt $t)
      {
        $Socket.Stop()
        $Stopwatch.Stop()
        return 1
      }
      if($AcceptHandle.IsCompleted)
      {
        $Client = $Socket.EndAcceptTcpClient($AcceptHandle)
        break
      }
    }
    $Stopwatch.Stop()
    Write-Verbose ("Connection from [" + $Client.Client.RemoteEndPoint.Address.IPAddressToString + "] port " + $port + " [tcp] accepted (source port " + $Client.Client.RemoteEndPoint.Port + ")")
    $Stream = $Client.GetStream()
    return @($Stream,$Socket,($Client.ReceiveBufferSize))
  }
  
  function Connect
  {
    param($c,$p,$t)
    Write-Verbose "Connecting..."
    $Socket = New-Object System.Net.Sockets.TcpClient
    $ConnectHandle = $Socket.BeginConnect($c,$p,$null,$null)
    $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    while($True)
    {
      if($Host.UI.RawUI.KeyAvailable)
      {
        Read-Host
      }
      if($Stopwatch.Elapsed.TotalSeconds -gt $t)
      {
        $Socket.Close()
        $Stopwatch.Stop()
        return 1
      }
      if($ConnectHandle.IsCompleted)
      {
        $Socket.EndConnect($ConnectHandle)
        break
      }
    }
    $Stopwatch.Stop()
    if($Socket -eq $null){return 2}
    Write-Verbose ("Connection to " + $c + ":" + $p + " [tcp] succeeeded!")
    $Stream = $Socket.GetStream()
    return @($Stream,$Socket,($Socket.ReceiveBufferSize))
  }
  
  if($r -ne "")
  {
    try
    {
      if($r.Contains(":"))
      {
        $RelayTarget=$r.split(":")[0]
        $RelayPort=$r.split(":")[1]
        $RelayType = "Client"
      }
      else
      {
        $RelayPort=$r
        $RelayType = "Listener"
      }
    }
    catch
    {
      return "Bad -r option. Formats: -r 10.1.1.1:443 , -r 443"
    }
    
    try
    {
      # Stream1
      if($l)
      {
        $ReturnValue = Listen $p $t
      }
      else
      {
        $ReturnValue = Connect $c $p $t
      }
      
      $Stream = $ReturnValue[0]
      $Socket = $ReturnValue[1]
      $BufferSize = $ReturnValue[2]
      if($Stream -eq 1){return "Timeout."}
      if($Stream -eq 2){return "Connection Error."}
      
      $StreamDestinationBuffer = New-Object System.Byte[] $BufferSize
      $StreamReadOperation = $Stream.BeginRead($StreamDestinationBuffer, 0, $BufferSize, $null, $null)
      
      # RelayStream
      if($RelayType -eq "Listener")
      {
        $ReturnValue = Listen $RelayPort $t
      }
      else
      {
        $ReturnValue = Connect $RelayTarget $RelayPort $t
      }
      
      $RelayStream = $ReturnValue[0]
      $RelaySocket = $ReturnValue[1]
      $RelayBufferSize = $ReturnValue[2]
      if($RelayStream -eq 1){return "Timeout."}
      if($RelayStream -eq 2){return "Connection Error."}
      
      $RelayStreamDestinationBuffer = New-Object System.Byte[] $RelayBufferSize
      $RelayStreamReadOperation = $RelayStream.BeginRead($RelayStreamDestinationBuffer, 0, $RelayBufferSize, $null, $null)
      
      while($True)
      {
        if($StreamReadOperation.IsCompleted)
        {
          $StreamBytesRead = $Stream.EndRead($StreamReadOperation)
          if($StreamBytesRead -eq 0){break}
          $RelayStream.Write(($StreamDestinationBuffer[0..([int]$StreamBytesRead-1)]), 0, $StreamBytesRead)
          $StreamReadOperation = $Stream.BeginRead($StreamDestinationBuffer, 0, $BufferSize, $null, $null)
        }
        if($RelayStreamReadOperation.IsCompleted)
        {
          $RelayStreamBytesRead = $RelayStream.EndRead($RelayStreamReadOperation)
          if($RelayStreamBytesRead -eq 0){break}
          $Stream.Write(($RelayStreamDestinationBuffer[0..([int]$RelayStreamBytesRead-1)]), 0, $RelayStreamBytesRead)
          $RelayStreamReadOperation = $RelayStream.BeginRead($RelayStreamDestinationBuffer, 0, $RelayBufferSize, $null, $null)
        }
      }
    }
    finally
    {
      $ErrorActionPreference= 'SilentlyContinue'
      $Stream.Close()
      if($l){$Socket.Stop()}
      else{$Socket.Close()}
      $RelayStream.Close()
      if($RelayType -eq "Listener"){$RelaySocket.Stop()}
      else{$RelaySocket.Close()}
    }
  }
  elseif($e -eq "")
  {
    try
    {
      if($l)
      {
        $ReturnValue = Listen $p $t
      }
      else
      {
        $ReturnValue = Connect $c $p $t
      }

      $Stream = $ReturnValue[0]
      $Socket = $ReturnValue[1]
      $BufferSize = $ReturnValue[2]
      if($Stream -eq 1){return "Timeout."}
      if($Stream -eq 2){return "Connection Error."}

      $Encoding = New-Object System.Text.AsciiEncoding
      $StreamDestinationBuffer = New-Object System.Byte[] $BufferSize
      $StreamReadOperation = $Stream.BeginRead($StreamDestinationBuffer, 0, $BufferSize, $null, $null)

      if($i -ne ""){$Stream.Write($Encoding.GetBytes($i),0,$i.Length)}

      while($True)
      {
        if($Host.UI.RawUI.KeyAvailable)
        {
          $command = Read-Host
          $Stream.Write($Encoding.GetBytes($command + "`n"),0,($command + "`n").Length)
        }
        if($StreamReadOperation.IsCompleted)
        {
          $StreamBytesRead = $Stream.EndRead($StreamReadOperation)
          if($StreamBytesRead -eq 0){break}
          Write-Host -n $Encoding.GetString($StreamDestinationBuffer[0..([int]$StreamBytesRead-1)])
          $StreamReadOperation = $Stream.BeginRead($StreamDestinationBuffer, 0, $BufferSize, $null, $null)
        }
      }
    }
    finally
    {
      $ErrorActionPreference= 'SilentlyContinue'
      $Stream.Close()
      if($l){$Socket.Stop()}
      else{$Socket.Close()}
    }
  }
  else
  {
    try
    {
      if($l)
      {
        $ReturnValue = Listen $p $t
      }
      else
      {
        $ReturnValue = Connect $c $p $t
      }

      $Stream = $ReturnValue[0]
      $Socket = $ReturnValue[1]
      $BufferSize = $ReturnValue[2]
      if($Stream -eq 1){return "Timeout."}
      if($Stream -eq 2){return "Connection Error."}

      $ProcessStartInfo = New-Object System.Diagnostics.ProcessStartInfo
      $ProcessStartInfo.FileName = $e
      $ProcessStartInfo.UseShellExecute = $False
      $ProcessStartInfo.RedirectStandardInput = $True
      $ProcessStartInfo.RedirectStandardOutput = $True
      $ProcessStartInfo.RedirectStandardError = $True
      $Process = [System.Diagnostics.Process]::Start($ProcessStartInfo)
      $Process.Start() | Out-Null

      $Encoding = New-Object System.Text.AsciiEncoding
      $ProcessDestinationBuffer = New-Object System.Byte[] 65536
      $ProcessReadOperation = $Process.StandardOutput.BaseStream.BeginRead($ProcessDestinationBuffer, 0, 65536, $null, $null)
      $StreamDestinationBuffer = New-Object System.Byte[] $BufferSize
      $StreamReadOperation = $Stream.BeginRead($StreamDestinationBuffer, 0, $BufferSize, $null, $null)
      
      if($i -ne ""){$Stream.Write($Encoding.GetBytes($i),0,$i.Length)}
      
      while($True)
      {
        if($ProcessReadOperation.IsCompleted)
        {
          $ProcessBytesRead = $Process.StandardOutput.BaseStream.EndRead($ProcessReadOperation)
          if($ProcessBytesRead -eq 0){break}
          $Stream.Write(($ProcessDestinationBuffer[0..([int]$ProcessBytesRead-1)]), 0, $ProcessBytesRead)
          $ProcessReadOperation = $Process.StandardOutput.BaseStream.BeginRead($ProcessDestinationBuffer, 0, 65536, $null, $null)
        }
        if($StreamReadOperation.IsCompleted)
        {
          $StreamBytesRead = $Stream.EndRead($StreamReadOperation)
          if($StreamBytesRead -eq 0){break}
          $Process.StandardInput.WriteLine($Encoding.GetString($StreamDestinationBuffer[0..([int]$StreamBytesRead-1)]).TrimEnd("`r").TrimEnd("`n"))
          $StreamReadOperation = $Stream.BeginRead($StreamDestinationBuffer, 0, $BufferSize, $null, $null)
        }
      }
    }
    finally
    {
      $ErrorActionPreference= 'SilentlyContinue'
      $Process | Stop-Process
      $Stream.Close()
      if($l){$Socket.Stop()}
      else{$Socket.Close()}
    }
  }
}
