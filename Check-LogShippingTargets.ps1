$dt=$null 
foreach ($RegisteredSQLs in dir -recurse SQLSERVER:\SQLRegistration\'Database Engine Server Group'\Development\ | where {$_.Mode -ne "d"}) 
{
$dt+=invoke-sqlcmd2 -query "SELECT @@ServerName AS 'ServerName'
		, secondary_database
        , last_restored_date
        , last_restored_file
  FROM dbo.log_shipping_secondary_databases" -ServerInstance $RegisteredSQLs.ServerName -database msdb 
#Write-DataTable -ServerInstance "Win7NetBook" -Database SandBox -TableName DatabasesSizes -Data $dt 
}
$LSTargetReport = $dt | sort last_restored_date | SELECT ServerName, secondary_database, last_restored_date, last_restored_file | ConvertTo-Html | Out-String;
Send-MailMessage -To Aaron@SQLvariant.com -Subject "Log-Shipping Target Check" -From Aaron@SQLvariant.com -SmtpServer SMTP.SQLvariant.com -Body $LSTargetReport -BodyAsHtml



