$watcher = New-Object System.IO.FileSystemWatcher
$watcher.Path = "C:\\Users"
$watcher.IncludeSubdirectories = $true
$watcher.EnableRaisingEvents = $true

Register-ObjectEvent $watcher Changed -Action {
    Write-Host \"File changed: $($Event.SourceEventArgs.FullPath)\"
}