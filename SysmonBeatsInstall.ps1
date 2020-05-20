$SysmonURI = "https://download.sysinternals.com/files/Sysmon.zip"
$TempFolder = "C:\Temp\Sysmon"
$LocalFilePath = "$TempFolder\sysmon.zip"
$SysmonConfigFile = "C:\configV0.xml"
$LocalRulesFilePath = "C:\Windows\sysmon.xml"
$StackVersion = '7.7.0'
$InstallFolder = "C:\Program Files\Elastic"
$ConfigRepositoryURL = "https://raw.githubusercontent.com/elkyaml/762/master/"
$CloudID = "PEXA-Corp:YXAtc291dGhlYXN0LTIuYXdzLmZvdW5kLmlvJDFkODU3ZWU2NDBmODRhYzI4ZGQwY2ZkZDFhOWNlYzljJDlhOTgxZmU1ZWU5NzRhMGFiNTcxN2Y0MzRlNTFjMzgy"
$CloudAuth = "windowsWriter:FutureToBack%^&"

if (Test-Path "C:\Windows\Sysmon64.exe")
{
    Write-Host "Unistalling Sysmon"
    Start-Process -WorkingDirectory "C:\Windows" -FilePath "sysmon64" -ArgumentList "-u" -Wait
}

Write-Host "Installing Sysmon..."
if (!(Test-Path $TempFolder)) {
    New-Item -Path $TempFolder -Type directory
}
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Invoke-WebRequest -Uri $SysmonConfigFile -OutFile $LocalRulesFilePath
Invoke-WebRequest -Uri $SysmonURI -OutFile $LocalFilePath
Expand-Archive -Path $LocalFilePath -DestinationPath $TempFolder
Start-Process -WorkingDirectory "$TempFolder" -FilePath "sysmon64" -ArgumentList "-accepteula -i $LocalRulesFilePath" -Wait
Remove-Item -Path $TempFolder -Recurse -Force
Write-Host "Installation Complete"
Write-Output "Elastic Beats $StackVersion Installation Initiated"

function InstallElasticBeat ([string]$BeatName)
{
    $ArtifactURI = "https://artifacts.elastic.co/downloads/beats/$BeatName/$BeatName-" + $StackVersion + "-windows-x86_64.zip"
    $LocalFilePath = "C:\Temp\$BeatName.zip"
    $BeatInstallFolder = $InstallFolder + '\' + "$BeatName"

    Write-Host "`nInstalling $BeatName..."

    #If Beat was already installed, disinstall service and cleanup first

    if (Get-Service $BeatName -ErrorAction SilentlyContinue) {
        $service = Get-WmiObject -Class Win32_Service -Filter "name='$BeatName'"
        $service.StopService()
        Start-Sleep -s 1
        $service.delete()
    }
    if (Test-Path $BeatInstallFolder) {
        Remove-Item -Path $BeatInstallFolder -Recurse -Force
    }

    #Downloading Beat artifact and install it
    Write-Host "Downloading $BeatName artifact..."
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $ArtifactURI -OutFile $LocalFilePath
    Expand-Archive -Path $LocalFilePath -DestinationPath $InstallFolder
    Rename-Item -Path "$InstallFolder\$BeatName-$StackVersion-windows-x86_64" -NewName $BeatInstallFolder
    Remove-Item -Path $LocalFilePath

    #Update Beat configuration
    Write-Host "Updating $BeatName.yml..."
    Rename-Item -Path $BeatInstallFolder\$BeatName.yml -NewName $BeatInstallFolder\$BeatName.yml.bak
    Invoke-WebRequest -Uri $ConfigRepositoryURL/$BeatName.yml -OutFile $BeatInstallFolder\$BeatName.yml

    #Create Beat keystore and add CloudAuth and CloudID secrets
    Push-Location $BeatInstallFolder
    Write-Host "Creating $BeatName keystore..."
    $params = $('keystore','create','--force')
    & .\$BeatName.exe $params
    Write-Host "Adding CloudID to $BeatName keystore..."
    $params = $('keystore','add','CloudID','--stdin','--force')
    Write-Output $CloudID | & .\$BeatName.exe $params
    Write-Host "Adding CloudAuth to $BeatName keystore..."
    $params = $('keystore','add','CloudAuth','--stdin','--force')
    Write-Output $CloudAuth | & .\$BeatName.exe $params
    
    if ($BeatName -eq 'metricbeat') {
        Write-Host "Setting up Beat Modules..."
        $params = $('modules','enable','windows')
        & .\$BeatName.exe $params
        Invoke-WebRequest -Uri $ConfigRepositoryURL/system.yml -OutFile $BeatInstallFolder\modules.d\system.yml
        Invoke-WebRequest -Uri $ConfigRepositoryURL/windows.yml -OutFile $BeatInstallFolder\modules.d\windows.yml
    }
    
    Write-Host "Testing $BeatName Connectivity to Elastic Cloud..."
    $params = $('test', 'output')
    & .\$BeatName.exe $params
    Pop-Location

    #Create Windows Service for Beat and start service
    Write-Host "Creating $BeatName service..."
    New-Service -name $BeatName `
                -displayName $BeatName `
                -binaryPathName "`"$BeatInstallFolder\$BeatName.exe`" -c `"$BeatInstallFolder\$BeatName.yml`" -path.home `"$BeatInstallFolder`"" `
                -startupType Automatic
    Write-Host "Starting $BeatName service..."
    Start-Service -Name "$BeatName"
    Write-Host "`n$BeatName Installation Completed!`n"
}

InstallElasticBeat("winlogbeat")
InstallElasticBeat("metricbeat")
