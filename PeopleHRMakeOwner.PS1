$username =""
$Password = ""

$secpassword = ConvertTo-SecureString $Password -AsPlainText -Force
$O365Cred = New-Object -TypeName System.Management.Automation.PSCredential -argumentlist $UserName,$secpassword


If(Get-PSSession | where-object {$_.ConfigurationName -eq "Microsoft.Exchange"}){
write-host "Session Exists"
}
else{
$O365Session = New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri https://ps.outlook.com/powershell -credential $adminCredential -Authentication Basic -AllowRedirection
Import-PSSession $O365Session -AllowClobber
}

#$O365Cred = Get-Credential

#$O365Session = New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri https://ps.outlook.com/powershell -Credential $O365Cred -Authentication Basic -AllowRedirection
#Import-PSSession $O365Session -AllowClobber

$delegate = 'peoplehr@landscapeinstitute.org'


$allmailbox = Get-Mailbox -Resultsize Unlimited
 
Foreach ($Mailbox in $allmailbox)
{
   $calendar = "${Mailbox}:\Calendar"

   write-host $calendar 

   #Add-MailboxFolderPermission -Identity $path -user $delegate -Accessrights FolderOwner | Where-Object { $_.Foldertype -eq "Calendar" }
   Set-mailboxfolderpermission –identity $calendar –user $delegate –Accessrights Owner  | Where-Object { $_.Foldertype -eq "Calendar" }

}
