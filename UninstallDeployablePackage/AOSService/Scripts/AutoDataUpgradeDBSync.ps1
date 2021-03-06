﻿[CmdletBinding()]
param
(
    [Parameter(Mandatory=$false)]
    [string]$LogDir
)

Import-Module WebAdministration
Import-Module "$PSScriptRoot\ExecuteSqltoAXDB.psm1" -Force -DisableNameChecking
Import-Module "$PSScriptRoot\CommonRollBackUtilities.psm1" -Force -DisableNameChecking
Import-Module "$PSScriptRoot\AosEnvironmentUtilities.psm1" -Force -DisableNameChecking

if(!$LogDir)
{
    $LogDir = $PSScriptRoot
}

$webroot = Get-AosWebSitePhysicalPath

$metadataDirectory = Get-CommonBinDir

[xml]$web = Get-Content "$($webroot)\web.config"

$sqlPwd = Get-DataAccessSqlPwd
$sqlUser = Get-DataAccessSqlUsr
$sqlServer = Get-DataAccessDbServer
$sqlDB = Get-DataAccessDatabase


Write-Output 'Update Web.Config file - set Safe Mode On'
($web.configuration.appSettings.add | where key -eq 'Aos.SafeMode' | select -First 1).Value  = 'True'
$web.Save("$($webroot)\web.config")

Write-Output 'Constructing the connection string for the SQL DB using the web.config'

$sqlParams = @{
   'Database' = $sqlDB
   'UserName' = $sqlUser
   'Password' = $sqlPwd
   'ServerInstance' = $sqlServer
   'Query' = "SELECT TABLENAME, INDEXNAME FROM RELEASEUPDATEDISABLEDINDEXES"
}

$disabledIndexes = Invoke-SqlCmd @sqlParams

$disabledIndexesCount = @($disabledIndexes).Count

$disabledIndexesArg = ''

if ($disabledIndexesCount -gt 0)
{
    $disabledIndexesArg = '-IgnoreIndexList='

    foreach($row in $disabledIndexes)
    {
        $disabledIndexesArg = $disabledIndexesArg + $row[0] + '.' + $row[1] + ','
    }

    $disabledIndexesArg = $disabledIndexesArg.Substring(0, $disabledIndexesArg.Length - 1)
}

Write-Output "Calling DB Sync"
$connectionString = "Data Source=$sqlServer; " +
        "Integrated Security=False; " +
        "User Id=$sqlUser; " +
        "Password='`"$sqlPwd`"'; " +
        "Initial Catalog=$sqlDB"

$command = Join-Path $metadataDirectory "Bin\SyncEngine.exe"
$arguments = "-syncmode=fullall $disabledIndexesArg -metadatabinaries=$metadataDirectory -connect=`"$connectionstring`" "

Write-Output $command $arguments

$process = Start-Process $command -ArgumentList $arguments -PassThru -Wait -RedirectStandardOutput "$LogDir\FullDBSync.log" -RedirectStandardError "$LogDir\FullDBSync.error.log"

#Update Web.Config file - set Safe Mode Off
[xml]$web = Get-Content "$($webroot)\web.config"
($web.configuration.appSettings.add | where key -eq 'Aos.SafeMode' | select -First 1).Value  = 'False'
$web.Save("$($webroot)\web.config")

if ($process.ExitCode -ne 0)
{
    Write-Error 'Failure detected during DB Sync. Please fix the issues in the error log and retry the step'
    throw $syncError
}

# SIG # Begin signature block
# MIIkCAYJKoZIhvcNAQcCoIIj+TCCI/UCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBBCwjoxKHZv6Ru
# 2j+hiBswX3FZ45Cn1DI6//Q3oz3zXaCCDYIwggYAMIID6KADAgECAhMzAAAAww6b
# p9iy3PcsAAAAAADDMA0GCSqGSIb3DQEBCwUAMH4xCzAJBgNVBAYTAlVTMRMwEQYD
# VQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNpZ25p
# bmcgUENBIDIwMTEwHhcNMTcwODExMjAyMDI0WhcNMTgwODExMjAyMDI0WjB0MQsw
# CQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
# ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMR4wHAYDVQQDExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIB
# AQC7V9c40bEGf0ktqW2zY596urY6IVu0mK6N1KSBoMV1xSzvgkAqt4FTd/NjAQq8
# zjeEA0BDV4JLzu0ftv2AbcnCkV0Fx9xWWQDhDOtX3v3xuJAnv3VK/HWycli2xUib
# M2IF0ZWUpb85Iq2NEk1GYtoyGc6qIlxWSLFvRclndmJdMIijLyjFH1Aq2YbbGhEl
# gcL09Wcu53kd9eIcdfROzMf8578LgEcp/8/NabEMC2DrZ+aEG5tN/W1HOsfZwWFh
# 8pUSoQ0HrmMh2PSZHP94VYHupXnoIIJfCtq1UxlUAVcNh5GNwnzxVIaA4WLbgnM+
# Jl7wQBLSOdUmAw2FiDFfCguLAgMBAAGjggF/MIIBezAfBgNVHSUEGDAWBgorBgEE
# AYI3TAgBBggrBgEFBQcDAzAdBgNVHQ4EFgQUpxNdHyGJVegD7p4XNuryVIg1Ga8w
# UQYDVR0RBEowSKRGMEQxDDAKBgNVBAsTA0FPQzE0MDIGA1UEBRMrMjMwMDEyK2M4
# MDRiNWVhLTQ5YjQtNDIzOC04MzYyLWQ4NTFmYTIyNTRmYzAfBgNVHSMEGDAWgBRI
# bmTlUAXTgqoXNzcitW2oynUClTBUBgNVHR8ETTBLMEmgR6BFhkNodHRwOi8vd3d3
# Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NybC9NaWNDb2RTaWdQQ0EyMDExXzIwMTEt
# MDctMDguY3JsMGEGCCsGAQUFBwEBBFUwUzBRBggrBgEFBQcwAoZFaHR0cDovL3d3
# dy5taWNyb3NvZnQuY29tL3BraW9wcy9jZXJ0cy9NaWNDb2RTaWdQQ0EyMDExXzIw
# MTEtMDctMDguY3J0MAwGA1UdEwEB/wQCMAAwDQYJKoZIhvcNAQELBQADggIBAE2X
# TzR+8XCTnOPVGkucEX5rJsSlJPTfRNQkurNqCImZmssx53Cb/xQdsAc5f+QwOxMi
# 3g7IlWe7bn74fJWkkII3k6aD00kCwaytWe+Rt6dmAA6iTCXU3OddBwLKKDRlOzmD
# rZUqjsqg6Ag6HP4+e0BJlE2OVCUK5bHHCu5xN8abXjb1p0JE+7yHsA3ANdkmh1//
# Z+8odPeKMAQRimfMSzVgaiHnw40Hg16bq51xHykmCRHU9YLT0jYHKa7okm2QfwDJ
# qFvu0ARl+6EOV1PM8piJ858Vk8gGxGNSYQJPV0gc9ft1Esq1+fTCaV+7oZ0NaYMn
# 64M+HWsxw+4O8cSEQ4fuMZwGADJ8tyCKuQgj6lawGNSyvRXsN+1k02sVAiPGijOH
# OtGbtsCWWSygAVOEAV/ye8F6sOzU2FL2X3WBRFkWOCdTu1DzXnHf99dR3DHVGmM1
# Kpd+n2Y3X89VM++yyrwsI6pEHu77Z0i06ELDD4pRWKJGAmEmWhm/XJTpqEBw51sw
# THyA1FBnoqXuDus9tfHleR7h9VgZb7uJbXjiIFgl/+RIs+av8bJABBdGUNQMbJEU
# fe7K4vYm3hs7BGdRLg+kF/dC/z+RiTH4p7yz5TpS3Cozf0pkkWXYZRG222q3tGxS
# /L+LcRbELM5zmqDpXQjBRUWlKYbsATFtXnTGVjELMIIHejCCBWKgAwIBAgIKYQ6Q
# 0gAAAAAAAzANBgkqhkiG9w0BAQsFADCBiDELMAkGA1UEBhMCVVMxEzARBgNVBAgT
# Cldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29m
# dCBDb3Jwb3JhdGlvbjEyMDAGA1UEAxMpTWljcm9zb2Z0IFJvb3QgQ2VydGlmaWNh
# dGUgQXV0aG9yaXR5IDIwMTEwHhcNMTEwNzA4MjA1OTA5WhcNMjYwNzA4MjEwOTA5
# WjB+MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMH
# UmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSgwJgYDVQQD
# Ex9NaWNyb3NvZnQgQ29kZSBTaWduaW5nIFBDQSAyMDExMIICIjANBgkqhkiG9w0B
# AQEFAAOCAg8AMIICCgKCAgEAq/D6chAcLq3YbqqCEE00uvK2WCGfQhsqa+laUKq4
# BjgaBEm6f8MMHt03a8YS2AvwOMKZBrDIOdUBFDFC04kNeWSHfpRgJGyvnkmc6Whe
# 0t+bU7IKLMOv2akrrnoJr9eWWcpgGgXpZnboMlImEi/nqwhQz7NEt13YxC4Ddato
# 88tt8zpcoRb0RrrgOGSsbmQ1eKagYw8t00CT+OPeBw3VXHmlSSnnDb6gE3e+lD3v
# ++MrWhAfTVYoonpy4BI6t0le2O3tQ5GD2Xuye4Yb2T6xjF3oiU+EGvKhL1nkkDst
# rjNYxbc+/jLTswM9sbKvkjh+0p2ALPVOVpEhNSXDOW5kf1O6nA+tGSOEy/S6A4aN
# 91/w0FK/jJSHvMAhdCVfGCi2zCcoOCWYOUo2z3yxkq4cI6epZuxhH2rhKEmdX4ji
# JV3TIUs+UsS1Vz8kA/DRelsv1SPjcF0PUUZ3s/gA4bysAoJf28AVs70b1FVL5zmh
# D+kjSbwYuER8ReTBw3J64HLnJN+/RpnF78IcV9uDjexNSTCnq47f7Fufr/zdsGbi
# wZeBe+3W7UvnSSmnEyimp31ngOaKYnhfsi+E11ecXL93KCjx7W3DKI8sj0A3T8Hh
# hUSJxAlMxdSlQy90lfdu+HggWCwTXWCVmj5PM4TasIgX3p5O9JawvEagbJjS4NaI
# jAsCAwEAAaOCAe0wggHpMBAGCSsGAQQBgjcVAQQDAgEAMB0GA1UdDgQWBBRIbmTl
# UAXTgqoXNzcitW2oynUClTAZBgkrBgEEAYI3FAIEDB4KAFMAdQBiAEMAQTALBgNV
# HQ8EBAMCAYYwDwYDVR0TAQH/BAUwAwEB/zAfBgNVHSMEGDAWgBRyLToCMZBDuRQF
# TuHqp8cx0SOJNDBaBgNVHR8EUzBRME+gTaBLhklodHRwOi8vY3JsLm1pY3Jvc29m
# dC5jb20vcGtpL2NybC9wcm9kdWN0cy9NaWNSb29DZXJBdXQyMDExXzIwMTFfMDNf
# MjIuY3JsMF4GCCsGAQUFBwEBBFIwUDBOBggrBgEFBQcwAoZCaHR0cDovL3d3dy5t
# aWNyb3NvZnQuY29tL3BraS9jZXJ0cy9NaWNSb29DZXJBdXQyMDExXzIwMTFfMDNf
# MjIuY3J0MIGfBgNVHSAEgZcwgZQwgZEGCSsGAQQBgjcuAzCBgzA/BggrBgEFBQcC
# ARYzaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9kb2NzL3ByaW1hcnlj
# cHMuaHRtMEAGCCsGAQUFBwICMDQeMiAdAEwAZQBnAGEAbABfAHAAbwBsAGkAYwB5
# AF8AcwB0AGEAdABlAG0AZQBuAHQALiAdMA0GCSqGSIb3DQEBCwUAA4ICAQBn8oal
# mOBUeRou09h0ZyKbC5YR4WOSmUKWfdJ5DJDBZV8uLD74w3LRbYP+vj/oCso7v0ep
# o/Np22O/IjWll11lhJB9i0ZQVdgMknzSGksc8zxCi1LQsP1r4z4HLimb5j0bpdS1
# HXeUOeLpZMlEPXh6I/MTfaaQdION9MsmAkYqwooQu6SpBQyb7Wj6aC6VoCo/KmtY
# SWMfCWluWpiW5IP0wI/zRive/DvQvTXvbiWu5a8n7dDd8w6vmSiXmE0OPQvyCInW
# H8MyGOLwxS3OW560STkKxgrCxq2u5bLZ2xWIUUVYODJxJxp/sfQn+N4sOiBpmLJZ
# iWhub6e3dMNABQamASooPoI/E01mC8CzTfXhj38cbxV9Rad25UAqZaPDXVJihsMd
# YzaXht/a8/jyFqGaJ+HNpZfQ7l1jQeNbB5yHPgZ3BtEGsXUfFL5hYbXw3MYbBL7f
# QccOKO7eZS/sl/ahXJbYANahRr1Z85elCUtIEJmAH9AAKcWxm6U/RXceNcbSoqKf
# enoi+kiVH6v7RyOA9Z74v2u3S5fi63V4GuzqN5l5GEv/1rMjaHXmr/r8i+sLgOpp
# O6/8MO0ETI7f33VtY5E90Z1WTk+/gFcioXgRMiF670EKsT/7qMykXcGhiJtXcVZO
# SEXAQsmbdlsKgEhr/Xmfwb1tbWrJUnMTDXpQzTGCFdwwghXYAgEBMIGVMH4xCzAJ
# BgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25k
# MR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jv
# c29mdCBDb2RlIFNpZ25pbmcgUENBIDIwMTECEzMAAADDDpun2LLc9ywAAAAAAMMw
# DQYJYIZIAWUDBAIBBQCggc4wGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYK
# KwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIPHt7mcy
# gsOpg/LPR5VmifWjmp2JoU6n4fRLzt8rZhArMGIGCisGAQQBgjcCAQwxVDBSoDSA
# MgBBAHUAdABvAEQAYQB0AGEAVQBwAGcAcgBhAGQAZQBEAEIAUwB5AG4AYwAuAHAA
# cwAxoRqAGGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbTANBgkqhkiG9w0BAQEFAASC
# AQA5nFeFLJ4/QCOwqkm2wRKiqEObJgbIi13WAiE4HB+jKxxt9oVRtn8CBD9z4fC7
# T3Zsq79t+L86UndqOirWn71OWwm2EuR+5LoayZdmGCRw6umRSGBcr32d8XhUsi6P
# KoQ7W4d2XNbn41CLVTMDlN34+7wf/9Uag4vG7r6PYf0qrOZ4u7oVCMUg+SgrneSs
# nbb08d88+XGAyuL+l4SxIF2gRYuR9wNbQHPLyqXk/s9kQ4cuOoZ7uEQbnzz+SccL
# AdhdTma83LZjX6VRj9RkNp6V00C+cS3NqHLxlxMGbw6AjRKftIjUlaT/C5vjAQzt
# XadYR8KCHIata4GLo2tRETJ9oYITRjCCE0IGCisGAQQBgjcDAwExghMyMIITLgYJ
# KoZIhvcNAQcCoIITHzCCExsCAQMxDzANBglghkgBZQMEAgEFADCCATwGCyqGSIb3
# DQEJEAEEoIIBKwSCAScwggEjAgEBBgorBgEEAYRZCgMBMDEwDQYJYIZIAWUDBAIB
# BQAEILodwb09jOHqOZTfRxJ2DblzTx1fSfn7Y0qecPBptaylAgZasoCDlVYYEzIw
# MTgwMzI1MjEwNTUyLjE0NFowBwIBAYACAfSggbikgbUwgbIxCzAJBgNVBAYTAlVT
# MRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQK
# ExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xDDAKBgNVBAsTA0FPQzEnMCUGA1UECxMe
# bkNpcGhlciBEU0UgRVNOOjEyQjQtMkQ1Ri04N0Q0MSUwIwYDVQQDExxNaWNyb3Nv
# ZnQgVGltZS1TdGFtcCBTZXJ2aWNloIIOyjCCBnEwggRZoAMCAQICCmEJgSoAAAAA
# AAIwDQYJKoZIhvcNAQELBQAwgYgxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNo
# aW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29y
# cG9yYXRpb24xMjAwBgNVBAMTKU1pY3Jvc29mdCBSb290IENlcnRpZmljYXRlIEF1
# dGhvcml0eSAyMDEwMB4XDTEwMDcwMTIxMzY1NVoXDTI1MDcwMTIxNDY1NVowfDEL
# MAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1v
# bmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWlj
# cm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAwggEiMA0GCSqGSIb3DQEBAQUAA4IB
# DwAwggEKAoIBAQCpHQ28dxGKOiDs/BOX9fp/aZRrdFQQ1aUKAIKF++18aEssX8XD
# 5WHCdrc+Zitb8BVTJwQxH0EbGpUdzgkTjnxhMFmxMEQP8WCIhFRDDNdNuDgIs0Ld
# k6zWczBXJoKjRQ3Q6vVHgc2/JGAyWGBG8lhHhjKEHnRhZ5FfgVSxz5NMksHEpl3R
# YRNuKMYa+YaAu99h/EbBJx0kZxJyGiGKr0tkiVBisV39dx898Fd1rL2KQk1AUdEP
# nAY+Z3/1ZsADlkR+79BL/W7lmsqxqPJ6Kgox8NpOBpG2iAg16HgcsOmZzTznL0S6
# p/TcZL2kAcEgCZN4zfy8wMlEXV4WnAEFTyJNAgMBAAGjggHmMIIB4jAQBgkrBgEE
# AYI3FQEEAwIBADAdBgNVHQ4EFgQU1WM6XIoxkPNDe3xGG8UzaFqFbVUwGQYJKwYB
# BAGCNxQCBAweCgBTAHUAYgBDAEEwCwYDVR0PBAQDAgGGMA8GA1UdEwEB/wQFMAMB
# Af8wHwYDVR0jBBgwFoAU1fZWy4/oolxiaNE9lJBb186aGMQwVgYDVR0fBE8wTTBL
# oEmgR4ZFaHR0cDovL2NybC5taWNyb3NvZnQuY29tL3BraS9jcmwvcHJvZHVjdHMv
# TWljUm9vQ2VyQXV0XzIwMTAtMDYtMjMuY3JsMFoGCCsGAQUFBwEBBE4wTDBKBggr
# BgEFBQcwAoY+aHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraS9jZXJ0cy9NaWNS
# b29DZXJBdXRfMjAxMC0wNi0yMy5jcnQwgaAGA1UdIAEB/wSBlTCBkjCBjwYJKwYB
# BAGCNy4DMIGBMD0GCCsGAQUFBwIBFjFodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20v
# UEtJL2RvY3MvQ1BTL2RlZmF1bHQuaHRtMEAGCCsGAQUFBwICMDQeMiAdAEwAZQBn
# AGEAbABfAFAAbwBsAGkAYwB5AF8AUwB0AGEAdABlAG0AZQBuAHQALiAdMA0GCSqG
# SIb3DQEBCwUAA4ICAQAH5ohRDeLG4Jg/gXEDPZ2joSFvs+umzPUxvs8F4qn++ldt
# GTCzwsVmyWrf9efweL3HqJ4l4/m87WtUVwgrUYJEEvu5U4zM9GASinbMQEBBm9xc
# F/9c+V4XNZgkVkt070IQyK+/f8Z/8jd9Wj8c8pl5SpFSAK84Dxf1L3mBZdmptWvk
# x872ynoAb0swRCQiPM/tA6WWj1kpvLb9BOFwnzJKJ/1Vry/+tuWOM7tiX5rbV0Dp
# 8c6ZZpCM/2pif93FSguRJuI57BlKcWOdeyFtw5yjojz6f32WapB4pm3S4Zz5Hfw4
# 2JT0xqUKloakvZ4argRCg7i1gJsiOCC1JeVk7Pf0v35jWSUPei45V3aicaoGig+J
# FrphpxHLmtgOR5qAxdDNp9DvfYPw4TtxCd9ddJgiCGHasFAeb73x4QDf5zEHpJM6
# 92VHeOj4qEir995yfmFrb3epgcunCaw5u+zGy9iCtHLNHfS4hQEegPsbiSpUObJb
# 2sgNVZl6h3M7COaYLeqN4DMuEin1wC9UJyH3yKxO2ii4sanblrKnQqLJzxlBTeCG
# +SqaoxFmMNO7dDJL32N79ZmKLxvHIa9Zta7cRDyXUHHXodLFVeNp3lfB0d4wwP3M
# 5k37Db9dT+mdHhk4L7zPWAUu7w2gUDXa7wknHNWzfjUeCLraNtvTX4/edIhJEjCC
# BNkwggPBoAMCAQICEzMAAACnZF3FKA8BPUQAAAAAAKcwDQYJKoZIhvcNAQELBQAw
# fDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1Jl
# ZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMd
# TWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAwHhcNMTYwOTA3MTc1NjUyWhcN
# MTgwOTA3MTc1NjUyWjCBsjELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0
# b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3Jh
# dGlvbjEMMAoGA1UECxMDQU9DMScwJQYDVQQLEx5uQ2lwaGVyIERTRSBFU046MTJC
# NC0yRDVGLTg3RDQxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZp
# Y2UwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQCm6hpQwF9P0lP5oewE
# fA3XIFcxIVHYx+4DCi54zosuIiNrljYQHwpReoXnXRT+c7LX0nxjVcEKuMaUNOi4
# idkXnAmxGKGRP0NWVVbZW8VP1oN+5OgQiBtMehuQotS1AtPR+L+bzv81atUujkyT
# RnqzfU5S0BgR2MyXzEyU5HKLUPzq0lIJEDiDEbiWAzE4XEGNOimHEVgTow6tfa3e
# +uZuytC4oXNtvrWppWdJawd8eYi0ZjbyMSc4FOI1H8EnXXjI4ioya2eBRlMF1ntD
# NWpEMO27Ie03SX+yRAmb2lnAKz6S+A7AJksXiu8I01TnjAuPio1S9qB5qE9mBjK5
# iyrxAgMBAAGjggEbMIIBFzAdBgNVHQ4EFgQUfA1KC337T/9eECw9eW8gTUJQiF0w
# HwYDVR0jBBgwFoAU1WM6XIoxkPNDe3xGG8UzaFqFbVUwVgYDVR0fBE8wTTBLoEmg
# R4ZFaHR0cDovL2NybC5taWNyb3NvZnQuY29tL3BraS9jcmwvcHJvZHVjdHMvTWlj
# VGltU3RhUENBXzIwMTAtMDctMDEuY3JsMFoGCCsGAQUFBwEBBE4wTDBKBggrBgEF
# BQcwAoY+aHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraS9jZXJ0cy9NaWNUaW1T
# dGFQQ0FfMjAxMC0wNy0wMS5jcnQwDAYDVR0TAQH/BAIwADATBgNVHSUEDDAKBggr
# BgEFBQcDCDANBgkqhkiG9w0BAQsFAAOCAQEAmsYkS+eXslIBZIcP4kKTKFZ5dvT5
# ChVnTXoOiYA8PzNC3o5y8lym83izubCF0o8l7duKveEsfVZgBBLPJ/NjePhGVFRK
# Ftpr6ly7+4Z6bF5/TXNioDadsN6z6c8SYoz68JxsJAxriC6Rl77fTjKMXG4nhCd5
# m53L3+jsEQsACVx6L2ol9tL2OiqHbUd2zFWvTrbx1Xoas/mcHQhIKP1x/14HmyVC
# sKP4C/1h0l+6dOhh1fPi4ES/KQ3jivBtXYxa4uUODYEH0SuO0nlQma0Boss1Abq+
# AEKDI3G2HWCHqoxb/nvtcIYOCHG1V4UvlBAjbbQfvKNGt+UWS67wrra6TqGCA3Qw
# ggJcAgEBMIHioYG4pIG1MIGyMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGlu
# Z3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBv
# cmF0aW9uMQwwCgYDVQQLEwNBT0MxJzAlBgNVBAsTHm5DaXBoZXIgRFNFIEVTTjox
# MkI0LTJENUYtODdENDElMCMGA1UEAxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAgU2Vy
# dmljZaIlCgEBMAkGBSsOAwIaBQADFQDkgi6dMjZtdAAyDx7BIbQN6wx32aCBwTCB
# vqSBuzCBuDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNV
# BAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEMMAoG
# A1UECxMDQU9DMScwJQYDVQQLEx5uQ2lwaGVyIE5UUyBFU046MjY2NS00QzNGLUM1
# REUxKzApBgNVBAMTIk1pY3Jvc29mdCBUaW1lIFNvdXJjZSBNYXN0ZXIgQ2xvY2sw
# DQYJKoZIhvcNAQEFBQACBQDeYefPMCIYDzIwMTgwMzI1MDkxODA3WhgPMjAxODAz
# MjYwOTE4MDdaMHQwOgYKKwYBBAGEWQoEATEsMCowCgIFAN5h588CAQAwBwIBAAIC
# ID0wBwIBAAICGYgwCgIFAN5jOU8CAQAwNgYKKwYBBAGEWQoEAjEoMCYwDAYKKwYB
# BAGEWQoDAaAKMAgCAQACAxbjYKEKMAgCAQACAwehIDANBgkqhkiG9w0BAQUFAAOC
# AQEABx7EJHtdjgMxUNxkh0L7Qjf+L+RTGmQf8YTmM8CZFgli0HPH00yrmfspvP7T
# ld+G2cEoRY5hveDwqP8sILNJi5tz650P+k1LoNguAvl3NFweicycyNboyQUWbS0V
# 7xQPCekG75qIZDdT276BPfE1Zk8rS9HdvfVbRtUZQZiSlx1mbv09MR0zLGyfuIZo
# LvAKwPCYZQ6WcB4KhIB7ixlr2QJjATJ7+0fe2Btwp7w5FxtcBp0Hp1R4h57Pmq1n
# T5CXSkgkn0JdYQp6gizmT6RBhOnsUdWMYTBtgkISwtBOUlZxcgzAppVKES29m+lW
# Zhkkp7wCjgT7cYbl8PaSisaVpDGCAvUwggLxAgEBMIGTMHwxCzAJBgNVBAYTAlVT
# MRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQK
# ExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1l
# LVN0YW1wIFBDQSAyMDEwAhMzAAAAp2RdxSgPAT1EAAAAAACnMA0GCWCGSAFlAwQC
# AQUAoIIBMjAaBgkqhkiG9w0BCQMxDQYLKoZIhvcNAQkQAQQwLwYJKoZIhvcNAQkE
# MSIEIOtRPWZhD5hb2rewPwjXFJlvlbGIurM56soI5lrFB6rEMIHiBgsqhkiG9w0B
# CRACDDGB0jCBzzCBzDCBsQQU5IIunTI2bXQAMg8ewSG0DesMd9kwgZgwgYCkfjB8
# MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVk
# bW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1N
# aWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMAITMwAAAKdkXcUoDwE9RAAAAAAA
# pzAWBBRhjz/2IczTl8Uag1UtwEj7DPO9jjANBgkqhkiG9w0BAQsFAASCAQCTTVSz
# ylHmDfQ4ifRs++cQFSKEdrWTyDbeTbiN7q9LumuMrvMBfXsZMyU+/6q12gUtABRq
# TLvWrPCEFc9vR4ISeTETPwOAaLwgnSdMyPZ+NSLGD6Ru3GBNcaxB3CAXZAN0YKHc
# xMqPsAC/RzKmFP9yNuEc0Jka3TIq9efk8Wf/d2qx78x8ahWZPio2TQjHwYZBAZiQ
# AELIF832ffsFL7yEgr1IoysqxXj34OhjEWXkQGLhJ5ygXbCG+eonZ1brWFQzkWr+
# xSHi2l6z7hUWkVcbNlSgn1Yxau6QeW/EQYGQMTeoGAuaklJu4m9Ku9c/a4GsK/sX
# FRmBELUIFYoszs72
# SIG # End signature block
