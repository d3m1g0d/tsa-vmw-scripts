<#
.SYNOPSIS
  Export or import vCenter Alarm definitions.
.DESCRIPTION
  Export or import vCenter Alarm definitions.  
  Each alarm will be exported to a single XML file located in a specified directory.
  Alarms will be imported from XML files located in specified directories.
.PARAMETER Export
  Used to export alarms to XML.
.PARAMETER Import
  Used to import alarms from XML.
.PARAMETER AlarmDefinitionStore
  Directory where to save XML files.
.EXAMPLE
  PS> .\set-vc-alarms.ps1 -Export -AlarmDefinitionStore .\vc-alarms
.EXAMPLE
  PS> .\set-vc-alarms.ps1 -Import -AlarmDefinitionStore .\vc-alarms
.LINK
 See https://communities.vmware.com/thread/284908
.NOTES
  Author: Adrian Heißler <adrian.heissler@t-systems.com>
  Version: 1.1 - Initial release.
#>

Param(
	[Parameter(Mandatory = $false)]
	[Switch]$Export,
	[Parameter(Mandatory = $false)]
	[Switch]$Import,
	[Parameter(Mandatory = $true, HelpMessage="Enter the name of the directory where the alarm definition(s) should be stored, e.g. c:\myalarms")]
	[String]$AlarmDefinitionStore
)

function ExportAlarm(){
	param(
		$alarmToExport
	)
	$a = Get-View -Id $alarmToExport.Id
	$a.Info | Export-Clixml -Path $AlarmDefinitionStore\$alarmToExport.xml -Depth ( [System.Int32]::MaxValue )
}

function ImportAlarm {
	param(
		$alarmToImport
	)	
	$deserializedAlarmInfo = Import-Clixml -Path $alarmToImport
	$importedAlarmInfo = ConvertFromDeserialized( $deserializedAlarmInfo )
	$entity = Get-Folder -NoRecursion
	
	$alarmManager = Get-View -Id "AlarmManager"
	$alarmManager.CreateAlarm($entity.Id, $importedAlarmInfo)
}

# This function converts a Powershell object deserialized from xml (with Import-Clixml) to its original type (that has been previously serialized with Export-Clixml)
# The function will not work with all .NET types. It is currently tested only with the Vmware.Vim.AlarmInfo type.
function ConvertFromDeserialized {
	param(
		$deserializedObject
	)
	
	if($deserializedObject -eq $null){
		return $null
	}
		
	$deserializedTypeName = ($deserializedObject | Get-Member -Force | where { $_.Name -eq "psbase" } ).TypeName;
	
	if($deserializedTypeName.StartsWith("Deserialized.")) {
		$originalTypeName = $deserializedTypeName.Replace("Deserialized.", "")
		$result = New-Object -TypeName $originalTypeName
		$resultType = $result.GetType()
		
		if($resultType.IsEnum){
			$result = [Enum]::Parse($resultType, $deserializedObject, $true)
			return $result
		}
		
		$deserializedObject | Get-Member | % { 
			if($_.MemberType -eq "Property") {
				$resultProperty = $resultType.GetProperty($_.Name)
				if($resultProperty.CanWrite){
					$propertyValue = ( Invoke-Expression ('$deserializedObject.' + $_.Name) | % { ConvertFromDeserialized( $_ ) } ) 
					if($propertyValue -and $resultProperty.PropertyType.IsArray ) {
						if($propertyValue.GetType().IsArray){
							# convert the elements
							$elementTypeName = $resultProperty.PropertyType.AssemblyQualifiedName.Replace("[]", "")
							$elementType = [System.Type]::GetType($elementTypeName)
							$array = [System.Array]::CreateInstance($elementType, $propertyValue.Count)
							for($i = 0; $i -lt $array.Length; $i++){
								$array[$i] = $propertyValue[$i]
							}
							$propertyValue = $array
						} else {
							$elementTypeName = $resultProperty.PropertyType.AssemblyQualifiedName.Replace("[]", "")
							$elementType = [System.Type]::GetType($elementTypeName)
							$array = [System.Array]::CreateInstance($elementType, 1)
							$array[0] = $propertyValue
							$propertyValue = $array
						}
					}
					$resultProperty.SetValue($result, $propertyValue, $null)
				}
			}
		} 
	} else {
		$result = $deserializedObject
	}
	
	return $result	
}

if($export) {
	if(-not (Test-Path -Path $AlarmDefinitionStore -PathType Container) ) {
		mkdir -Path $AlarmDefinitionStore
	}
	Write-Host "Exporting alarms to $AlarmDefinitionStore..." -ForegroundColor green
	foreach($alarmdef in Get-AlarmDefinition) {
		ExportAlarm $alarmdef
	}
	exit
}

if($import) {
	Write-Host "Importing alarms from $AlarmDefinitionStore..." -ForegroundColor green
	$AlarmDefinitions = Get-ChildItem $AlarmDefinitionStore -Filter *.xml
	foreach($alarmdef in $AlarmDefinitions) {
		if((Get-AlarmDefinition -Name $alarmdef.BaseName -ErrorAction SilentlyContinue).Name -eq $null) {
			Write-Host $alarmdef.BaseName
			ImportAlarm $alarmdef.FullName | Out-Null
		}
	}
	exit
}
