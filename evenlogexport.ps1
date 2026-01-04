# eventlog export script for external windows systems
# packets needed: none, permissions on remote systems
# this script will export windows event logs on remote systems and copy them to a destination of choice
# this script is intended to be run interactively
#
# this is certified vibe code


Write-Host "EventLog Export Script has been started"
Write-Host "Starting Variable check"

$Servers = Get-Content "PATH TO SERVER CSV FILE"
$LocalPath = "LOCAL DIRECTORY FOR LOG IMPORT"
$EvtLogExpPath = "LOCAL DIRECTORY ON REMOTE SERVER FOR LOG EXPORT"
$RemotePath = "PATH TO SHARED DIRECTORY ON REMOTE SERVER"
$DateFull = Get-Date -format "ddMMyyyy"
$DateYear = Get-Date -format "yyyy"
$LogTypes = @("Application","Security","System")
$WarnMsg = "Log was not tansfered to storage server in time, EventLog has not been cleared and manual check is needed! `n"
$InfMsg = "Log, additional time for file transfer granted"

Write-Host "Completed Variable check"
Write-Host "Starting Folder check"

foreach($Server in $Servers){
    if(!(Test-Path -path "${LocalPath}$Server${DateYear}" )){
        if(!(Test-Path -path "${LocalPath}$Server" )){New-Item -name $Server -Path "${LocalPath}" -ItemType Directory}
    New-Item -name $DateYear -Path "${LocalPath}$Server" -ItemType Directory}
}
Write-Host "Completed Folder check"
Write-host "Starting EventLog Export on all Servers. This may take a while..."

foreach($Type in $LogTypes){
    foreach($Server in $Servers){
        wevtutil epl $Type "${EvtLogExpPath}${Type}_${DateFull}.evtx" /r:$Server
    }
    Start-Sleep -s 2
}

Write-Host "Completed EventLog Export on all Servers"
Write-Host "Starting File Copy from all Servers and File check"

foreach($Type in $LogTypes){
    foreach($Server in $Servers){
        Move-Item -Path "\\$Server\${RemotePath}${Type}_${DateFull}.evtx" -Destination "${LocalPath}$Server\${DateYear}\"
        Start-Sleep -s 5

        $LogTest = Test-Path -Path "${LocalPath}$Server\${DateYear}\${Type}_${DateFull}.evtx" -PathType Leaf
        If($LogTest){Clear-EventLog $Type -ComputerName $Server}
        else{
            Write-Host "INFORMATION: $Server $Type ${InfMsg}" -ForegroundColor Yellow
            Start-Sleep -s 5
            $LogTest = Test-Path -Path "${LocalPath}$Server\${DateYear}\${Type}_${DateFull}.evtx" -PathType Leaf
            if($LogTest){Clear-EventLog $Type -ComputerName $Server}
            else{write-Warning -Message "$Server $Type ${WarnMsg}"}
        }
    Write-Host "${Server}: File Check completed"
    }
}
Read-Host -Prompt "Script finished, press Enter to exit"
