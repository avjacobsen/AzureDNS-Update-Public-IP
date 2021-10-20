# AzureDNS-Update-Public-IP
Powershell script for AzureDNS to update a DNS A record to reflect the machine's current public IP

# Running
Just start the script, and it will ask for the necessary info, like credentials, tenantid, resource group, zone name etc. and saves it in the script folder. Password will of course be hashed SecureString.
If successful, it will start silently subsequent times.

# Notes
Make sure you don't have a CNAME record of the record you wish to create/update. The script will notify you of this and fail if you do.

# Todo
The ARecordToUpdate settings is not the FQDN, only the name. Ex. if DNS zone is example.com, and you want to change publicip.example.com, then set ARecordToUpdate to publicip, not public.example.com.
