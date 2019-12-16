<#
.SYNOPSIS
  Show VM deployment or removal events for a given period.
.DESCRIPTION
  Show VM deployment or removal events for a given period.
.PARAMETER Type
  Report type, valid inputs: Created, Removed
.EXAMPLE
  PS> .\get-vmdeploy-report.ps1
  Get VM deployments of the last 30 days.
.EXAMPLE
  PS> .\get-vmdeploy-report.ps1 -Type Remove -Days 7
  Get VM removals of the last week.
.NOTES
  Author: Adrian Heißler <adrian.heissler@t-systems.com>
  Version: 1.0 - Initial release.
#>

param (
	[int]$days = 30,
	[string]$type = "Created"
)

function Get-VmDeployReport {
	Param(
		[int]$LastDays = 30
	)

	$report = @()

	$EventFilterSpecByTime = New-Object VMware.Vim.EventFilterSpecByTime
	$EventFilterSpecByTime.BeginTime = (get-date).AddDays(-$($LastDays))
	$EventFilterSpec = New-Object VMware.Vim.EventFilterSpec
    $EventFilterSpec.Time = $EventFilterSpecByTime
    $EventFilterSpec.DisableFullMessage = $False
	$EventFilterSpec.Type = "VmCreatedEvent","VmDeployedEvent","VmClonedEvent","VmDiscoveredEvent","VmRegisteredEvent"
    $EventManager = Get-View EventManager
    $NewVmTasks = $EventManager.QueryEvents($EventFilterSpec)
	 
	Foreach ($Task in $NewVmTasks) {
		# If VM was deployed from a template then record which template.
		If ($Task.Template -and ($Task.SrcTemplate.Vm)) {
			$srcTemplate = (Get-View $Task.SrcTemplate.Vm -Property name).Name
		}
		Else {
			$srcTemplate = $null
		}
		$report += ""|Select-Object @{
			Name="Name"
			Expression={$Task.Vm.name}
		}, @{
			Name="Created"
			Expression={$Task.CreatedTime}
		}, @{
			Name="UserName"
			Expression={$Task.UserName}
		}, @{        
			Name="Type"
			Expression={$Task.gettype().name}
		}, @{
			Name="Template"
			Expression={$srcTemplate}
		}
	}
	$report
}

function Get-VmRemoveReport {
	Param(
		[int]$LastDays = 30
	)

	$report = @()

	$EventFilterSpecByTime = New-Object VMware.Vim.EventFilterSpecByTime
	$EventFilterSpecByTime.BeginTime = (get-date).AddDays(-$($LastDays))
	$EventFilterSpec = New-Object VMware.Vim.EventFilterSpec
    $EventFilterSpec.Time = $EventFilterSpecByTime
    $EventFilterSpec.DisableFullMessage = $False
	$EventFilterSpec.Type = "VmRemovedEvent"
    $EventManager = Get-View EventManager
    $RemovedVmEvents = $EventManager.QueryEvents($EventFilterSpec)
	 
	Foreach ($Event in $RemovedVmEvents) {
		# Note: VmRemovedEvent is also triggered in vMotion operations.
		# Thus, we're searching all related events to make sure we're really dealing
		# with a VM removal, i.e. FullFormattedMessage of the related event looks like:
		# "Task: Unregister virtual machine"
		# "Task: Delete virtual machine"
		$EventFilterSpec = New-Object VMware.Vim.EventFilterSpec
		$EventFilterSpec.Time = $EventFilterSpecByTime
		$EventFilterSpec.DisableFullMessage = $False
		$EventFilterSpec.EventChainId = $Event.ChainId
		$EventManager = Get-View EventManager
		$RelatedVmEvents = $EventManager.QueryEvents($EventFilterSpec)
		Foreach ($RelatedVmEvent in $RelatedVmEvents) { 
			if ($RelatedVmEvent.FullFormattedMessage -match "Task:.*virtual machine") {
				$report += ""|Select-Object @{
					Name="Name"
					Expression={$Event.Vm.name}
				}, @{
					Name="Removed"
					Expression={$Event.CreatedTime}
				}, @{
					Name="UserName"
					Expression={$Event.UserName}
				}, @{        
					Name="Type"
					Expression={$Event.gettype().name}
				}
			}
		}
	}
	$report
}


if ($type -ne "Removed") {
	$VmDeployReport = Get-VmDeployReport -LastDays $days
	$VmDeployReport | sort Created -Descending
	write-output "$($VmDeployReport.count) VMs have been deployed during the last $days day(s)."
	exit
}

$VmRemoveReport = Get-VmRemoveReport -LastDays $days
$VmRemoveReport | sort Removed -Descending
write-output "$($VmRemoveReport.count) VMs have been removed during the last $days day(s)."