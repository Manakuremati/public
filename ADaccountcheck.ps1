# cmdlet for getting general AD information of a user
# packets needed: none, AD access
# this script is intended to be added as cmdlet to powershell
# it will get some general information of a user directly from the AD DC's
#
# this is certified vibe code


function Check-ADUserActivity {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false,ValueFromPipeline=$true)]
        [Alias('samaccountname','user')]
        [string]$Identity = $(Read-Host "Please Enter Username")
    )
    try {
        if([bool]$(Get-ADUser -Filter {sAMAccountName -eq $Identity})){
            $ADUser = Get-ADUser -Identity $Identity -Properties *
            $DCs = Get-ADDomainController -Filter * | Select-Object -ExpandProperty HostName | Sort-Object
            $NewestLogonDate = $null
            $LastBadPasswordAttempt = $null
            foreach($DC in $DCs){
                $ADUserfromDC = Get-ADUser -Identity $Identity -Server $DC -Properties LastLogon,LastBadPasswordAttempt
                $LogonDate = $ADUserfromDC | Select-Object -ExpandProperty LastLogon
                $BadPasswordAttempt = $ADUserfromDC | Select-Object -ExpandProperty LastBadPasswordAttempt
                if($LogonDate -gt $NewestLogonDate){
                    $NewestLogonDate = $LogonDate
                }
                if($BadPasswordAttempt -gt $LastBadPasswordAttempt){
                    $LastBadPasswordAttempt = $BadPasswordAttempt
                }
            }
            $Output = [PSCustomObject]@{
                Firstname = $ADUser.GivenName
                Lastname = $ADUser.Surname
                SamAccountName = $ADUser.SamAccountName
                Mail = $ADUser.mail
                DistinguishedName = $ADUser.DistinguishedName
                Lockedout = $ADUser.lockedout
                IsActive = $ADUser.Enabled
                LastLogon = [datetime]::FromFileTime($NewestLogonDate)
                LastBadPasswordAttempt = $LastBadPasswordAttempt
                pwdLastSet = [datetime]::FromFileTime($ADUser.pwdLastSet)
                PasswordExpired = $ADUser.PasswordExpired
                PasswordNeverExpires = $ADUser.PasswordNeverExpires
            }
            return $Output
        }
        else{
            Write-Host "User $Identity not found" -ForegroundColor Red
            return $null
        }
    }
    catch {
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Line: $($_.InvocationInfo.ScriptLineNumber)" -ForegroundColor Red
        Write-Host "File: $($_.InvocationInfo.ScriptName)" -ForegroundColor Red
    }
}
