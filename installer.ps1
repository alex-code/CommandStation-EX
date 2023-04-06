<#
# © 2023 Peter Cole
# 
# This file is part of EX-CommandStation
#
# This is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# It is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with CommandStation.  If not, see <https://www.gnu.org/licenses/>.
#>

<############################################
For script errors set ExecutionPolicy:
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy Bypass
############################################>

<############################################
Optional command line parameters:
  $buildDirectory - specify an existing directory rather than generating a new unique one
  $version - specify an exact version to download
############################################>
Param(
  [Parameter()]
  [String]$buildDirectory,
  [Parameter()]
  [String]$configDirectory
)

<############################################
Define global parameters here such as known URLs etc.
############################################>
$installerVersion = "v0.0.1"
$gitHubAPITags = "https://api.github.com/repos/DCC-EX/CommandStation-EX/git/refs/tags"
$gitHubURLPrefix = "https://github.com/DCC-EX/CommandStation-EX/archive/"
if ((Get-WmiObject win32_operatingsystem | Select-Object osarchitecture).osarchitecture -eq "64-bit") {
  $arduinoCLIURL = "https://downloads.arduino.cc/arduino-cli/arduino-cli_latest_Windows_64bit.zip"
  $arduinoCLIZip = $env:TEMP + "\" + "arduino-cli_latest_Windows_64bit.zip"
} else {
  $arduinoCLIURL = "https://downloads.arduino.cc/arduino-cli/arduino-cli_latest_Windows_32bit.zip"
  $arduinoCLIZip = $env:TEMP + "\" + "arduino-cli_latest_Windows_32bit.zip"
}
$arduinoCLIDirectory = $env:TEMP + "\" + "arduino-cli_installer"
$arduinoCLI = $arduinoCLIDirectory + "\arduino-cli.exe"

<############################################
Set default action for progress indicators, warnings, and errors
############################################>
$global:ProgressPreference = "SilentlyContinue"
$global:WarningPreference = "SilentlyContinue"
$global:ErrorActionPreference = "SilentlyContinue"

<############################################
If $buildDirectory not provided, generate a new time/date stamp based directory to use
############################################>
if (!$PSBoundParameters.ContainsKey('buildDirectory')) {
  $buildDate = Get-Date -Format 'yyyyMMdd-HHmmss'
  $buildDirectory = $env:TEMP + "\" + $buildDate
}
$commandStationDirectory = $buildDirectory + "\CommandStation-EX"

<############################################
Write out intro message and prompt to continue
############################################>
@"
Welcome to the DCC-EX PowerShell installer for EX-CommandStation ($installerVersion)

Current installer options:
- EX-CommandStation will be built in $commandStationDirectory
- Arduino CLI will be in $arduinoCLIDirectory
"@


<############################################
Create build directory if it doesn't exist, or fail
############################################>
if (!(Test-Path -PathType Container -Path $buildDirectory)) {
  try {
    New-Item -ItemType Directory -Path $buildDirectory | Out-Null
  }
  catch {
    Write-Output "Could not create build directory $buildDirectory"
    Exit
  }
}

<############################################
See if we have the Arduino CLI already, otherwise download and extract it
############################################>
if (!(Test-Path -PathType Leaf -Path $arduinoCLI)) {
  if (!(Test-Path -PathType Container -Path $arduinoCLIDirectory)) {
    try {
      New-Item -ItemType Directory -Path $arduinoCLIDirectory | Out-Null
    }
    catch {
      Write-Output "Arduino CLI does not exist and cannot create directory $arduinoCLIDirectory"
      Exit
    }
  }
  Write-Output "Downloading and extracting Arduino CLI"
  try {
    Invoke-WebRequest -Uri $arduinoCLIURL -OutFile $arduinoCLIZip
  }
  catch {
    Write-Output "Failed to download Arduino CLI"
    Exit
  }
  try {
    Expand-Archive -Path $arduinoCLIZip -DestinationPath $arduinoCLIDirectory -Force
  }
  catch {
    Write-Output "Failed to extract Arduino CLI"
  }
}

<############################################
Get the list of tags
############################################>
try {
  $gitHubTags = Invoke-RestMethod -Uri $gitHubAPITags
}
catch {
  Write-Output "Failed to obtain list of available EX-CommandStation versions"
  Exit
}

<############################################
Get our GitHub tag list in a hash so we can sort by version numbers and extract just the ones we want
############################################>
$versionMatch = ".*?v(\d+)\.(\d+).(\d+)-(.*)"
$tagList = @{}
foreach ($tag in $gitHubTags) {
  $tagHash = @{}
  $tagHash["Ref"] = $tag.ref
  $version = $tag.ref.split("/")[2]
  $null = $version -match $versionMatch
  $tagHash["Major"] = [int]$Matches[1]
  $tagHash["Minor"] = [int]$Matches[2]
  $tagHash["Patch"] = [int]$Matches[3]
  $tagHash["Type"] = $Matches[4]
  $tagList.Add($version, $tagHash)
}

<############################################
Get latest two Prod and Devel for user to select
############################################>
$userList = @{}
$prodCount = 1
$devCount = 1
$select = 1
foreach ($tag in $tagList.Keys | Sort-Object {$tagList[$_]["Major"]},{$tagList[$_]["Minor"]},{$tagList[$_]["Patch"]} -Descending) {
  if (($tagList[$tag]["Type"] -eq "Prod") -and $prodCount -le 2) {
    $userList[$select] = $tag
    $select++
    $prodCount++
  } elseif (($tagList[$tag]["Type"] -eq "Devel") -and $devCount -le 2) {
    $userList[$select] = $tag
    $select++
    $devCount++
  }
}

<############################################
Display options for user to select and get the selection
############################################>
foreach ($selection in $userList.Keys | Sort-Object $selection) {
  Write-Output "$selection - $($userList[$selection])"
}
Write-Output "5 - Exit"
$userSelection = 0
do {
  [int]$userSelection = Read-Host "Select the version to install from the list above (1 - 5)"
} until (
  (($userSelection -ge 1) -and ($userSelection -le 5))
)
if ($userSelection -eq 5) {
  Write-Output "Exiting installer"
  Exit
} else {
  $downloadURL = $gitHubURLPrefix + $tagList[$userList[$userSelection]]["Ref"] + ".zip"
}

<############################################
Download the chosen version to the build directory
############################################>
$downladFile = $buildDirectory + "\CommandStation-EX.zip"
Write-Output "Downloading and extracting $($userList[$userSelection])"
try {
  Invoke-WebRequest -Uri $downloadURL -OutFile $downladFile
}
catch {
  Write-Output "Error downloading EX-CommandStation zip file"
  Exit
}

<############################################
Extract and rename to CommandStation-EX to allow building
############################################>
try {
  Expand-Archive -Path $downladFile -DestinationPath $buildDirectory -Force
}
catch {
  Write-Output "Failed to extract EX-CommandStation zip file"
  Exit
}

$folderName = $buildDirectory + "\CommandStation-EX-" + ($userList[$userSelection] -replace "^v", "")
Write-Output $folderName
try {
  Rename-Item -Path $folderName -NewName $commandStationDirectory
}
catch {
  Write-Output "Could not rename folder"
  Exit
}

<############################################
If config directory provided, copy files here
############################################>


<############################################
Once files all together, identify available board(s)
############################################>
# Need to do an initial board list to download everything first
& $arduinoCLI board list | Out-Null
# Run again to generate the list of discovered boards
& $arduinoCLI board list --format json

<############################################
Get user to select board
############################################>




<############################################
Upload the sketch to the selected board
############################################>
#$arduinoCLI upload -b fqbn -p port $commandStationDirectory

<#
Write-Output "Installing using directory $buildDirectory"

$tagList = Invoke-RestMethod -Uri $gitHubAPITags

foreach ($tag in $tagList) {
  $version = $tag.ref.split("/")[2]
  $versionURL = $gitHubURLPrefix + $tag.ref
  Write-Output "$version : $versionURL"
}
#>