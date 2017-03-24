
##################################################################################################

    #PeopleHR
    $PeopleapiKey = ''

    ##O365 Service Account
    $username =""
    $Password = ""

    #Additional
    $global:AdditionalAccounts = @()
    $global:AdditionalAccounts += ''
    $global:AdditionalAccounts += ''


    #Log
    $logLocation = '\\server\support\Logs\peopleHR.log'

    #ArrArray
    $global:uidArr = @()

    #Refresh : WILL DELETE ALL ENTRIES BUT NOT ADD THEM.
    $refresh = 'false' #true / false

##########################################################################################
###CONNECT TO EWS SERVICE###
##########################################################################################

function EWSConnect {

        $secpassword = ConvertTo-SecureString $Password -AsPlainText -Force
        $adminCredential = New-Object -TypeName System.Management.Automation.PSCredential -argumentlist $UserName,$secpassword

        If(Get-PSSession | where-object {$_.ConfigurationName -eq "Microsoft.Exchange"}){
    
        }
        else{
            $rpRemotePowershell = New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri https://ps.outlook.com/powershell -credential $adminCredential -Authentication Basic -AllowRedirection
            $importresults = Import-PSSession $rpRemotePowershell
        }

        $dllpath = "C:\Program Files (x86)\Microsoft\Exchange\Web Services\2.1\Microsoft.Exchange.WebServices.dll"
        [void][Reflection.Assembly]::LoadFile($dllpath)
        $service = New-Object Microsoft.Exchange.WebServices.Data.ExchangeService([Microsoft.Exchange.WebServices.Data.ExchangeVersion]::Exchange2010_SP1)

        $windowsIdentity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $sidbind = "LDAP://<SID=" + $windowsIdentity.user.Value.ToString() + ">"
        $aceuser = [ADSI]$sidbind
        $service.Credentials = New-Object System.Net.NetworkCredential($username,$password)
        $service.AutodiscoverUrl($UserName ,{$true})

        write-host "EWS Connection Successfull"

        return $service

}

##########################################################################################
###OUTPUT TO LOG FILE###
##########################################################################################

function write-log{
       Param ([string]$string)
       Add-content $logLocation -value "$(get-date -f dd-MM-yyyy:HH.mm.ss) : $string"
}

##########################################################################################
###SHOW A BALLOONTIP###
##########################################################################################

function Show-BalloonTip {            
        [cmdletbinding()]            
        param(            
         [parameter(Mandatory=$true)]            
         [string]$Title,            
         [ValidateSet("Info","Warning","Error")]             
         [string]$MessageType = "Info",            
         [parameter(Mandatory=$true)]            
         [string]$Message,            
         [string]$Duration=10000            
        )            

            [system.Reflection.Assembly]::LoadWithPartialName('System.Windows.Forms') | Out-Null            
            $balloon = New-Object System.Windows.Forms.NotifyIcon            
            $path = Get-Process -id $pid | Select-Object -ExpandProperty Path            
            $icon = [System.Drawing.Icon]::ExtractAssociatedIcon($path)            
            $balloon.Icon = $icon            
            $balloon.BalloonTipIcon = $MessageType            
            $balloon.BalloonTipText = $Message            
            $balloon.BalloonTipTitle = $Title            
            $balloon.Visible = $true            
            $balloon.ShowBalloonTip($Duration)  
            Start-Sleep -Milliseconds $Duration
            $balloon.Dispose()          
}          

##########################################################################################
###SEND A REQUEST PeopleHR###
##########################################################################################

function SendRequestPHR([String]$url,[String]$Send){
    $response = invoke-restmethod  $url -Method POST -Body $send
    return $response.result # | Select * | ConvertTo-Json | ConvertFrom-Json
}

##########################################################################################
###LIST ALL ACTIVE EMPLOYEES###
##########################################################################################

function GetAllEmployees ([String]$apiKey){
    $send = '{"APIKey": "' + $PeopleapiKey + '","Action": "GetAllEmployeeDetail","IncludeLeavers":"false"}'
    $response = SendRequestPHR 'https://api.peoplehr.net/Employee' $send
    return $response
}

##########################################################################################
###GENERATES A UNIQUE ID USING EMAIL AND HOLIDAY AND START AND END###
##########################################################################################
function GenerateUID([string] $email, [string] $starts, [string] $ends){

    $str = "$email $starts $ends"
    $md5 = new-object -TypeName System.Security.Cryptography.MD5CryptoServiceProvider
    $utf8 = new-object -TypeName System.Text.UTF8Encoding
    $hash = [System.BitConverter]::ToString($md5.ComputeHash($utf8.GetBytes($str)))
    return $hash

}

##########################################################################################
###LIST ALL EMPLOYEES HOLIDAYS###
##########################################################################################

function GetAllEmployeesHolidays ([String]$apiKey, [string]$employeeID){
    $year = get-date –format yyyy
    $send = '{"APIKey": "' + $PeopleapiKey + '", "Action" : "GetHolidayDetail", "EmployeeId" : "' + $employeeID + '", "StartDate": "' + $year + '-01-01", "EndDate": "' + $year + '-12-31" }' 
    $response = SendRequestPHR 'https://api.peoplehr.net/Holiday' $send
    return $response
}

##########################################################################################
###PROCESS ADDING TO CALENDARS###
##########################################################################################

function CalendarProcess  ([String] $holidayApproverEmail, [String] $holidayRequesterEmail, [String] $holidayStarts,[String] $holidayEnds, [String] $holidayRequesterFullName, [String] $holidayRequestersComments){

    ####################################################################################
    #THE MAIN CALENDAR PROCESS, ADDS AND DELETES APPOINTMENTS
    ####################################################################################

    ##GETS THE UID FOR THE HOLIDAY
    $uid = GenerateUID $holidayRequesterEmail $holidayStarts,$holidayEnds 

    ####################################################################################
    #REMOVES LEGACY ENTRIES
    ####################################################################################

    ##REMOVE ANY LEGACY ENTRIES FROM REQUESTER
    RemoveLegacyEntries $holidayRequesterEmail $uid $holidayStarts $holidayEnds

    ##REMOVE ANY LEGACY ENTRIES FROM APPROVER
    RemoveLegacyEntries $holidayApproverEmail $uid $holidayStarts $holidayEnds

    ##REMOVE LEGACY ENTRIES FROM ANY ADDITIONAL ACCOUNTS
    foreach($additionalAccount in $additionalAccounts){
       RemoveLegacyEntries $additionalAccount $uid $holidayStarts $holidayEnds
    }


    ####################################################################################
    #ADDS INTO REQUESTER MAILBOX
    ####################################################################################

    ##CHECK IF THIS APPOINTMENT IS ALREADY IN THE REQUESTERS MAILBOX
    $appointment = CheckForHolidayAppointments $holidayRequesterEmail $uid $holidayStarts $holidayEnds

    if($appointment){
        ##IF APPOINTMENT WAS FOUND ALREADY
        write-host "Appointment Already Excists in $holidayRequesterEmail - Skipping" -foregroundcolor "Gray"
    } else {
        ##NOT ADDED SO ADD THIS HOLIDAY APPOINTMENT
        NewHolidayAppointment $holidayRequesterEmail $uid $holidayStarts $holidayEnds $holidayRequesterFullName $holidayRequestersComments 'OOH'
    }


    ####################################################################################
    #ADDS INTO APPROVER MAILBOX
    ####################################################################################

    ##CHECK IF THIS APPOINTMENT IS ALREADY IN THE APPROVER MAILBOX
    $appointment = CheckForHolidayAppointments $holidayApproverEmail $uid $holidayStarts $holidayEnds

    if($appointment){
        ##IF APPOINTMENT WAS FOUND ALREADY
        write-host "Appointment Already Excists in $holidayRequesterEmail - Skipping" -foregroundcolor "Gray"
    } else {
        ##NOT ADDED SO ADD THIS HOLIDAY APPOINTMENT
        NewHolidayAppointment $holidayApproverEmail $uid $holidayStarts $holidayEnds $holidayRequesterFullName $holidayRequestersComments 'Free'
    }

    ####################################################################################
    #ADDS INTO ADDITIONAL ACCOUNT MAILBOX
    ####################################################################################

    foreach($additionalAccount in $additionalAccounts){

        $appointment = CheckForHolidayAppointments $additionalAccount $uid $holidayStarts $holidayEnds

        if($appointment){
            ##IF APPOINTMENT WAS FOUND ALREADY
            write-host "Appointment Already Excists in $additionalAccount - Skipping" -foregroundcolor "Gray"
        } else {
            ##NOT ADDED SO ADD THIS HOLIDAY APPOINTMENT
            NewHolidayAppointment $additionalAccount $uid $holidayStarts $holidayEnds $holidayRequesterFullName $holidayRequestersComments 'Free'
        }


    }


}

##########################################################################################
###REMOVE OLD STYLE ENTRIES###
##########################################################################################

function RemoveLegacyEntries  ([String] $Mailbox, [String] $uid, [string] $starts, [string] $ends  ){

    write-host "Looking for legacy entries in $mailbox for $starts and $ends"
    $folderid= new-object Microsoft.Exchange.WebServices.Data.FolderId([Microsoft.Exchange.WebServices.Data.WellKnownFolderName]::Calendar,$Mailbox)   
    $calendarFolder = [Microsoft.Exchange.WebServices.Data.calendarFolder]::Bind($service, $folderid)
    $calendarView = new-object Microsoft.Exchange.WebServices.Data.CalendarView($starts, $ends)
    #$calendarView = new-object Microsoft.Exchange.WebServices.Data.CalendarView([System.DateTime]::Now, [System.DateTime]::Now.AddDays(365))
    $calendarView.MaxItemsReturned = 200;
    $calendarView.PropertySet = new-object Microsoft.Exchange.WebServices.Data.PropertySet([Microsoft.Exchange.WebServices.Data.BasePropertySet]::FirstClassProperties)
    $calendarEvents = $calendarFolder.FindAppointments($calendarView)        
    $CalendarAppointments = $calendarEvents 

    foreach($CalendarAppointment in $CalendarAppointments){

      $PropertySet = New-Object Microsoft.Exchange.WebServices.Data.PropertySet([Microsoft.Exchange.WebServices.Data.BasePropertySet]::FirstClassProperties)
      $PropertySet.RequestedBodyType = [Microsoft.Exchange.WebServices.Data.BodyType]::Text
      $CalendarAppointment.Load($PropertySet)
      $bodyText= $CalendarAppointment.Body.toString()

      if($bodyText -like "*${uid}*"){
        write-host "Deleting Legacy Appointment from mailbox $Mailbox" -foregroundcolor "Red"
        write-log "Deleting Legacy Appointment from mailbox $Mailbox"
        $CalendarAppointment.Delete([Microsoft.Exchange.WebServices.Data.DeleteMode]::SoftDelete)

      }


    }

}

##########################################################################################
###CHECK IF APPOINTMENT ALREADY IN A MAILBOX###
##########################################################################################

function CheckForHolidayAppointments  ([String] $Mailbox, [String] $uid, [string] $starts, [string] $ends ){

    $folderid= new-object Microsoft.Exchange.WebServices.Data.FolderId([Microsoft.Exchange.WebServices.Data.WellKnownFolderName]::Calendar,$Mailbox)   
 
    $newEnd = [datetime]$ends
    $newEnd = $newEnd.AddDays(1)
    $ends = $newEnd.toString('yyyy-MM-dd')

    $Start = "${starts}T00:00:00Z"
    $End = "${ends}T00:00:00Z"

    if($refresh -eq 'true'){
        $uid = 'none'
    }

    $calendarFolder = [Microsoft.Exchange.WebServices.Data.calendarFolder]::Bind($service, $folderid)
    $calendarView = new-object Microsoft.Exchange.WebServices.Data.CalendarView($Start,$End)
    $calendarView.MaxItemsReturned = 200;
    $calendarView.PropertySet = new-object Microsoft.Exchange.WebServices.Data.PropertySet([Microsoft.Exchange.WebServices.Data.BasePropertySet]::FirstClassProperties)
    $calendarEvents = $calendarFolder.FindAppointments($calendarView)        
    $CalendarAppointments = $calendarEvents 

    foreach($CalendarAppointment in $CalendarAppointments){

        $psPropSet = new-object Microsoft.Exchange.WebServices.Data.PropertySet([Microsoft.Exchange.WebServices.Data.BasePropertySet]::FirstClassProperties);
        $CalendarAppointment.Load($psPropSet);
        if($CalendarAppointment.ICalUid -like "*${uid}*"){
           return $CalendarAppointment          
        }


    }

}

##########################################################################################
###REMOVE ANY DELETED HOLIDAYS###
##########################################################################################


function CheckForHolidayDeletedAppointments ([String] $holidayRequesterFullName, [String] $Mailbox ){
 
    $year = get-date –format yyyy
    $starts = "$year-01-01"
    $ends = "$year-12-31"

    $folderid= new-object Microsoft.Exchange.WebServices.Data.FolderId([Microsoft.Exchange.WebServices.Data.WellKnownFolderName]::Calendar,$Mailbox)   
    $calendarFolder = [Microsoft.Exchange.WebServices.Data.calendarFolder]::Bind($service, $folderid)
    $calendarView = new-object Microsoft.Exchange.WebServices.Data.CalendarView($starts, $ends)
    $calendarView.MaxItemsReturned = 200;
    $calendarView.PropertySet = new-object Microsoft.Exchange.WebServices.Data.PropertySet([Microsoft.Exchange.WebServices.Data.BasePropertySet]::FirstClassProperties)
    $calendarEvents = $calendarFolder.FindAppointments($calendarView)        
    $CalendarAppointments = $calendarEvents 

    foreach($CalendarAppointment in $CalendarAppointments){
        
        Try
        {
            $PropertySet = New-Object Microsoft.Exchange.WebServices.Data.PropertySet([Microsoft.Exchange.WebServices.Data.BasePropertySet]::FirstClassProperties)
            $PropertySet.RequestedBodyType = [Microsoft.Exchange.WebServices.Data.BodyType]::Text
            $CalendarAppointment.Load($PropertySet)
            $bodyText= $CalendarAppointment.Body.toString()

            if($bodyText -like "*PeopleHR Holiday Sync*"){

                if($global:uidArr -contains $CalendarAppointment.ICalUid){
                  if($refresh -eq 'true'){
                        $dUID = $CalendarAppointment.ICalUid.toString()
                        write-log "Deleting Holiday for $holidayRequesterFullName in $Mailbox [$dUID]" 
                        write-host "Deleting Holiday for $holidayRequesterFullName in $Mailbox" -foregroundcolor "Red"
                        $CalendarAppointment.Delete([Microsoft.Exchange.WebServices.Data.DeleteMode]::SoftDelete)
                  }
                    
                }else{
                    $dUID = $CalendarAppointment.ICalUid.toString()
                    write-log "Deleting Holiday for $holidayRequesterFullName in $Mailbox [$dUID]" 
                    write-host "Deleting Holiday for $holidayRequesterFullName in $Mailbox" -foregroundcolor "Red"
                    $CalendarAppointment.Delete([Microsoft.Exchange.WebServices.Data.DeleteMode]::SoftDelete)
                }
            }
        }
        Catch
        {
        }

    }
}

##########################################################################################
###ADD NEW APPOINTMENT###
##########################################################################################

function NewHolidayAppointment  ([String] $Mailbox, [String] $uid, [string] $starts, [string] $ends,[string] $fullname,[string] $comments, [string] $status  ){

    write-host "Creating new Holiday Appointment for $fullname in mailbox $Mailbox" -foregroundcolor "Green"
    write-log "Creating new Holiday Appointment for $fullname in mailbox $Mailbox [$starts] [$ends] [$uid]"

    if($refresh -eq 'false'){

        $Appointment = New-Object Microsoft.Exchange.WebServices.Data.Appointment -ArgumentList $service    

        $Appointment.Start = "${starts} 00:00:00"
        $Appointment.End = "${ends} 23:59:59"

        $Appointment.ICalUid = $uid

        $Appointment.Subject = "Annual Leave $fullname" 

        if($status -eq 'OOF'){$Appointment.LegacyFreeBusyStatus = [Microsoft.Exchange.WebServices.Data.LegacyFreeBusyStatus]::OOF; }
        $Appointment.Body = "<div style='font-family:arial;font-size:12px'>$comments <br /><br /> Added by PeopleHR Holiday Sync Services</div>"  
        $Appointment.IsAllDayEvent=1
    
        $folderid= new-object Microsoft.Exchange.WebServices.Data.FolderId([Microsoft.Exchange.WebServices.Data.WellKnownFolderName]::Calendar,$Mailbox)   
        $Appointment.Save($folderid,[Microsoft.Exchange.WebServices.Data.SendInvitationsMode]::SendToNone); 

    }
 
}


###################################################################################################################################
####################################################MAIN CODE######################################################################
###################################################################################################################################

function MainCodeBlock(){

    $service = EWSConnect

    Show-BalloonTip -Title “Service Running” -MessageType Info -Message “Running PeopleHR Holiday Service” -Duration 3000

    $employees = GetAllEmployees($apiKey)

    ##EACH EMPLOYEE IN PEOPLEHR
    foreach($employee in $employees){

        ##INITIAL EMPLOYEE VARS
        $emailAddress = $employee.EmailId.DisplayValue
        $managerEmailAddress = $employee.ReportsToEmailAddress.DisplayValue
        $employeeID = $employee.EmployeeId.DisplayValue
        $firstName = $employee.FirstName.DisplayValue
        $lastName = $employee.LastName.DisplayValue
        $fullName = "$firstName $lastName"  

        ##GET EMPLOYEES HOLIDAY
        $holidays = GetAllEmployeesHolidays $apiKey $employeeID

        write-host "Processing Holidays for $fullName"  

        foreach($holiday in $holidays){
            
            ##WACK ALL THE UIDs INTO AN ARRAY
            $uid = GenerateUID $emailAddress $holiday.StartDate,$holiday.EndDate
            $global:uidArr+=$uid

            ##SET UP SOME INITIAL VARS 

            $holidayStarts = $holiday.StartDate
            $holidayEnds = $holiday.EndDate
          
            $holidayApprover = $holiday.Approver
            $holidayApproverComments = $holiday.ApproverComments
            $holidayStatus = $holiday.status
            $holidayRequestersComments = $holiday.RequesterComments
            $holidayRequesterEmail = $emailAddress
            $holidayApproverEmail = $managerEmailAddress
            $holidayRequesterFirstName = $firstName
            $holidayRequesterLastName = $lastName
            $holidayRequesterFullName = $fullName  

            ##PROCEED IF THIS HOLIDAY HAS BEEN APPROVED
            if($holidayStatus -eq 'Approved'){
                CalendarProcess $holidayApproverEmail $holidayRequesterEmail $holidayStarts $holidayEnds $holidayRequesterFullName $holidayRequestersComments
            }



        }


         ##CHECK FOR ANY APPOINTMENTS WHERE THE UID IS NOT IN PEOPLEHR

            CheckForHolidayDeletedAppointments $holidayRequesterFullName $holidayRequesterEmail
            CheckForHolidayDeletedAppointments $holidayRequesterFullName $holidayApproverEmail

            ##ALSO CHECK ANY ADDITIONAL ACCOUNTS
            foreach($additionalAccount in $additionalAccounts){
                CheckForHolidayDeletedAppointments $holidayRequesterFullName $additionalAccount
            }

    

    }


}

MainCodeBlock




  



