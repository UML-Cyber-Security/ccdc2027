$DocumentsPath = [System.Environment]::GetFolderPath("MyDocuments")
$HostsFilePath = "C:\Windows\System32\drivers\etc\hosts"
$BackupPath = Join-Path -Path $DocumentsPath -ChildPath "hosts_backup.txt"
Copy-Item -Path $HostsFilePath -Destination $BackupPath -Force
$defaultHostsContent = @"
127.0.0.1       localhost
::1             localhost
"@
Set-Content -Path $HostsFilePath -Value $defaultHostsContent -Force