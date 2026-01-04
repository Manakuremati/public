# remote log off script for windows
# packets needed: none, remote system must have RPC enabled
# this script is made to log off users on remote windows systems it is intended to be run as interactive
#
# this is certified vibe code


function RemoteLogoff {
    Param(
     [Parameter(Mandatory)]
     [string]$ComputerName,

     [Parameter(Mandatory)]
     [string]$userName
    )
    Process{
        try{
            $Query = quser $userName /server:$ComputerName 2>&1
            If ($LASTEXITCODE -ne 0) {
                Switch -Wildcard ($Query) {
                    "*[1722]*" {
                        $Status = "Remote RPC not enabled on $($ComputerName) or the computer name is wrong"
                    }
                    "*[5]*" {
                        $Status = "Remote RPC access denied on $($ComputerName)"
                    }
                    "No User exists for*" {
                        $Status = "User $($userName) is not logged on on $($ComputerName)"
                    }
                }
                write-host $Status -ForegroundColor Yellow
            }
            Else {
                $sessionID = (($Query | Where-Object { $_ -match $userName }) -split " +")[3]
                logoff $sessionID /server:$ComputerName
            }
        }
        catch{
            $error[0]
            Write-Warning "Execution failed, get in touch with contact person"
        }
    }
}
$CN,$UN = ""
while($CN -eq ""){$CN = Read-Host -Prompt "Please type in the hostname"}
while($CN -ne ""){
$UN = Read-Host -Prompt "Please type in the Username (Default: User)"
if($UN -eq ""){$UN = "User"}
RemoteLogoff -ComputerName $CN -userName $UN
$CN,$UN = ""
$CN = Read-Host -Prompt "Please type in a new hostname or Enter to exit"
}
