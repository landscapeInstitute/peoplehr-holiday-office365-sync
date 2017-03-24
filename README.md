# PeopleHR-Holiday-Office365-Sync
Automate Calendar events for PeopleHR Holidays

Install https://www.microsoft.com/en-us/download/details.aspx?id=35371
on the server that will be running script. 

Input your password and username into BOTH Scripts

Run PeopleHRSync-MakeOwner.PS1 

this will give your dedicated service account Ownership over all mailboxes so it can add and delete appointments

this should be run manually everytime you have a new starter. It can however be coded to run automaticly but may be a little overkill thus not included in the main script. 

now run PeopleHRSyncEWS.PS1

it should..

1) use peopleHR API to find all employees
2) find all their holidays 
3) Removes some legacy entries from an older script i wrote, this can be removed for most people
4) adds the holiday to their calender, their managers calender and any additional accounts specified at the top
5) using an array of holidays for that employee. remove any holidays that are now no longer on PeopleHR
6) Save everything to a log file. 

