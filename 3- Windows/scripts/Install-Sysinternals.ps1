$dest = "C:\Sysinternals"
New-Item $dest -ItemType Directory -ErrorAction SilentlyContinue

$tools = @(
    'procexp64.exe', 'Procmon64.exe', 'Autoruns64.exe', 'autorunsc64.exe',
    'Tcpview.exe', 'Sysmon64.exe', 'Sigcheck64.exe',
    'PsLoggedOn.exe', 'PsService.exe', 'AccessChk64.exe',
    'handle64.exe', 'listdlls64.exe', 'strings64.exe'
)
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$wc = New-Object System.Net.WebClient
$wc.Headers.Add("User-Agent", "Mozilla/5.0")
foreach ($t in $tools) {
    $wc.DownloadFile("https://live.sysinternals.com/$t", "$dest\$t")
}
$wc.Dispose()

# Accept all Sysinternals EULAs per-tool so dialogs never appear
Write-Host "[*] Accepting EULAs..." -ForegroundColor Cyan
$eulaNames = @(
    'Process Explorer','Process Monitor','Autoruns','AutorunsC',
    'TCPView','Sysmon','Sigcheck','PsLoggedOn','PsService',
    'AccessChk','Handle','ListDLLs','Strings'
)
foreach ($t in $eulaNames) {
    reg add "HKCU\Software\Sysinternals\$t" /v EulaAccepted /t REG_DWORD /d 1 /f | Out-Null
}

# Set all .exe files to always run as admin
Write-Host "[*] Setting run-as-admin..." -ForegroundColor Cyan
Get-ChildItem "$dest\*.exe" | ForEach-Object {
    Set-ItemProperty -Path "HKLM:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers" `
        -Name $_.FullName -Value "~ RUNASADMIN" -ErrorAction SilentlyContinue
}

# Install Sysmon with hardened config
@'
<Sysmon schemaversion="4.50">
  <HashAlgorithms>SHA256</HashAlgorithms>
  <EventFiltering>
    <ProcessCreate onmatch="exclude">
      <Image condition="is">C:\Windows\System32\backgroundTaskHost.exe</Image>
      <Image condition="is">C:\Windows\System32\RuntimeBroker.exe</Image>
      <Image condition="is">C:\Windows\System32\sihost.exe</Image>
      <Image condition="is">C:\Windows\System32\SearchProtocolHost.exe</Image>
      <Image condition="is">C:\Windows\System32\SearchFilterHost.exe</Image>
      <Image condition="is">C:\Windows\System32\audiodg.exe</Image>
      <Image condition="is">C:\Windows\System32\ctfmon.exe</Image>
      <Image condition="is">C:\Windows\System32\MusNotifyIcon.exe</Image>
      <Image condition="is">C:\Windows\System32\musnotification.exe</Image>
    </ProcessCreate>
    <FileCreateTime onmatch="exclude" />
    <NetworkConnect onmatch="exclude">
      <DestinationPort condition="is">67</DestinationPort>
      <DestinationPort condition="is">68</DestinationPort>
    </NetworkConnect>
    <ImageLoad onmatch="include">
      <ImageLoaded condition="contains">\Temp\</ImageLoaded>
      <ImageLoaded condition="contains">\AppData\</ImageLoaded>
      <ImageLoaded condition="contains">\Downloads\</ImageLoaded>
      <ImageLoaded condition="contains">\ProgramData\</ImageLoaded>
      <ImageLoaded condition="contains">\Users\Public\</ImageLoaded>
      <ImageLoaded condition="contains">\Windows\Tasks\</ImageLoaded>
      <ImageLoaded condition="contains">\Recycle</ImageLoaded>
      <Signed condition="is">false</Signed>
    </ImageLoad>
    <CreateRemoteThread onmatch="exclude">
      <SourceImage condition="is">C:\Windows\System32\csrss.exe</SourceImage>
      <SourceImage condition="is">C:\Windows\System32\wininit.exe</SourceImage>
      <SourceImage condition="is">C:\Windows\System32\winlogon.exe</SourceImage>
    </CreateRemoteThread>
    <ProcessAccess onmatch="include">
      <TargetImage condition="is">C:\Windows\System32\lsass.exe</TargetImage>
    </ProcessAccess>
    <FileCreate onmatch="include">
      <TargetFilename condition="end with">.exe</TargetFilename>
      <TargetFilename condition="end with">.dll</TargetFilename>
      <TargetFilename condition="end with">.sys</TargetFilename>
      <TargetFilename condition="end with">.scr</TargetFilename>
      <TargetFilename condition="end with">.ps1</TargetFilename>
      <TargetFilename condition="end with">.bat</TargetFilename>
      <TargetFilename condition="end with">.cmd</TargetFilename>
      <TargetFilename condition="end with">.vbs</TargetFilename>
      <TargetFilename condition="end with">.js</TargetFilename>
      <TargetFilename condition="end with">.wsf</TargetFilename>
      <TargetFilename condition="end with">.hta</TargetFilename>
      <TargetFilename condition="end with">.msi</TargetFilename>
      <TargetFilename condition="end with">.aspx</TargetFilename>
      <TargetFilename condition="end with">.asp</TargetFilename>
      <TargetFilename condition="end with">.jsp</TargetFilename>
      <TargetFilename condition="end with">.php</TargetFilename>
      <TargetFilename condition="contains">\inetpub\</TargetFilename>
      <TargetFilename condition="contains">\wwwroot\</TargetFilename>
      <TargetFilename condition="contains">\Start Menu\Programs\Startup\</TargetFilename>
    </FileCreate>
    <RegistryEvent onmatch="include">
      <TargetObject condition="contains">\CurrentVersion\Run</TargetObject>
      <TargetObject condition="contains">\CurrentVersion\RunOnce</TargetObject>
      <TargetObject condition="contains">\Services\</TargetObject>
      <TargetObject condition="contains">\Schedule\TaskCache\</TargetObject>
      <TargetObject condition="contains">\AppInit_DLLs</TargetObject>
      <TargetObject condition="contains">\Image File Execution Options\</TargetObject>
      <TargetObject condition="contains">\Winlogon\</TargetObject>
      <TargetObject condition="contains">\SecurityProviders\</TargetObject>
      <TargetObject condition="contains">\InprocServer32\</TargetObject>
      <TargetObject condition="contains">\Explorer\Shell Folders</TargetObject>
      <TargetObject condition="contains">\Wow6432Node\</TargetObject>
      <TargetObject condition="contains">\Environment\</TargetObject>
      <TargetObject condition="contains">\Windows\CurrentVersion\Policies\</TargetObject>
      <TargetObject condition="contains">\Authentication\Credential Providers\</TargetObject>
      <TargetObject condition="contains">\LSA\</TargetObject>
    </RegistryEvent>
    <FileCreateStreamHash onmatch="exclude">
      <TargetFilename condition="end with">Zone.Identifier</TargetFilename>
    </FileCreateStreamHash>
    <PipeEvent onmatch="include">
      <PipeName condition="contains">msagent_</PipeName>
      <PipeName condition="contains">MSSE-</PipeName>
      <PipeName condition="contains">postex_</PipeName>
      <PipeName condition="contains">status_</PipeName>
      <PipeName condition="is">\psexecsvc</PipeName>
      <PipeName condition="is">\paexecsvc</PipeName>
      <PipeName condition="is">\remcom_comunicacion</PipeName>
      <PipeName condition="is">\isapi_http</PipeName>
      <PipeName condition="is">\isapi_dg</PipeName>
      <PipeName condition="is">\isapi_dg2</PipeName>
      <PipeName condition="contains">csexec</PipeName>
      <PipeName condition="contains">DserNamePipe</PipeName>
      <PipeName condition="contains">SearchTextHarvester</PipeName>
      <PipeName condition="contains">lsadump</PipeName>
      <PipeName condition="contains">cachedump</PipeName>
      <PipeName condition="contains">wceservice</PipeName>
    </PipeEvent>
    <DnsQuery onmatch="exclude">
      <QueryName condition="end with">.windowsupdate.com</QueryName>
      <QueryName condition="end with">.msftconnecttest.com</QueryName>
      <QueryName condition="end with">.msftncsi.com</QueryName>
    </DnsQuery>
    <FileDelete onmatch="include">
      <TargetFilename condition="end with">.exe</TargetFilename>
      <TargetFilename condition="end with">.dll</TargetFilename>
      <TargetFilename condition="end with">.ps1</TargetFilename>
      <TargetFilename condition="end with">.bat</TargetFilename>
      <TargetFilename condition="end with">.cmd</TargetFilename>
      <TargetFilename condition="end with">.vbs</TargetFilename>
      <TargetFilename condition="contains">\winevt\Logs\</TargetFilename>
    </FileDelete>
    <ProcessTampering onmatch="exclude" />
  </EventFiltering>
</Sysmon>
'@ | Out-File "$env:TEMP\sc.xml" -Encoding UTF8
Write-Host "[*] Installing Sysmon..." -ForegroundColor Cyan
cmd /c "`"$dest\Sysmon64.exe`" -accepteula -i `"$env:TEMP\sc.xml`" >nul 2>&1"

# Launch the tools you actually need open during competition
Start-Process "$dest\procexp64.exe"   # process explorer
Start-Process "$dest\Autoruns64.exe"  # startup/persistence items
Start-Process "$dest\Tcpview.exe"     # live network connections

Write-Host "[+] Sysinternals installed to $dest — Sysmon running, tools launched" -ForegroundColor Green