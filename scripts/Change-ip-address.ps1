
If (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator"))
{
	$arguments = "& '" + $myinvocation.mycommand.definition + "'"
	Start-Process powershell -Verb runAs -ArgumentList $arguments
	Break
}

$dhcp = Get-NetAdapter | ? Name -eq "イーサネット" | Get-NetIPInterface | where {$_.AddressFamily -eq "IPv4"} | select dhcp

if ($dhcp.dhcp -eq "Enabled") {
	echo "Change static ip address"
	Get-NetAdapter | ? Name -eq "イーサネット" | Set-NetIPInterface -Dhcp Disabled
	Get-NetAdapter | ? Name -eq "イーサネット" | New-NetIPAddress -AddressFamily IPv4 -IPAddress 172.16.100.3 -PrefixLength 24 -DefaultGateway 172.16.100.1
	Get-NetAdapter | ? Name -eq "イーサネット" | Set-DnsClientServerAddress -ResetServerAddresses
	Get-NetAdapter | ? Name -eq "イーサネット" | Set-DnsClientServerAddress -ServerAddresses 8.8.8.8, 8.8.4.4, 1.1.1.1, 1.0.0.1, 2001:4860:4860::8888, 2001:4860:4860::8844, 2606:4700:4700::1111, 2606:4700:4700::1001
	pause
} else {
	echo "Change DHCP ip address"
	Get-NetAdapter | ? Name -eq "イーサネット" | Remove-NetIPAddress -IPAddress 172.16.100.3 -DefaultGateway 172.16.100.1 -PrefixLength 24 -Confirm:$false
	Get-NetAdapter | ? Name -eq "イーサネット" | Set-DnsClientServerAddress -ResetServerAddresses
	Get-NetAdapter | ? Name -eq "イーサネット" | Set-DnsClientServerAddress -ServerAddresses 8.8.8.8, 8.8.4.4, 1.1.1.1, 1.0.0.1, 2001:4860:4860::8888, 2001:4860:4860::8844, 2606:4700:4700::1111, 2606:4700:4700::1001
	Get-NetAdapter | ? Name -eq "イーサネット" | Set-NetIPInterface -Dhcp Enabled
	Get-NetAdapter | ? Name -eq "イーサネット" | Get-NetIPAddress -AddressFamily IPv4
	pause
}
