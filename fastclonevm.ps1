# Script: Fastclone live VM
# Author: David Quinney 
# Description:
# This script gets around the limitations of VAAI cloning while a VM is powered on, by cloning from a nutanix restored snapshot.  VAAI clone only works if the VM is powered off.
# What the script does is creates a nutanix snapshot of the VM, restores the VM to a powered off state, then finally VAAI clones the restored VM so the nutanix snapshot can safely be removed.
# A good use case for this script is to attatch VMDK's from a live production VM which cannot be powered off, to a test VM. 
# Future Plans for the script (For anyone wanting to help out, my powershell knowledge is very limited
# 1) Add Error Checking
#	2) Ability to choose which specific VMDK's you want to snapshot 
#	3) Ability to select a target VM to auto attatch the cloned VMDK to a new SCSCI controller https://communities.vmware.com/thread/475941
#
# Use this script at your own risk, it is vary basic and has no error checking logic implemented.
# begin script
#
#Import PowerCli snapin
Add-PSSnapin VMware.VimAutomation.Core

#Import Nutanix Modules
Set-Location "C:\Program Files (x86)\Nutanix Inc\NutanixCmdlets\powershell\import_modules"
.\ImportModules.PS1

#Variables
#Nutanix cluster name
$nutanixcluster = 'nutanixclustername'
#Nutanix Prism User
$user = "admin"
$password = read-host "Please enter the prism user password" -AsSecureString
#vcenter server
$vcenter ="vcenterservername" 
#Current time
$time = Get-Date -format "dd-MMM-yyyy HH:mm"
 
# Connect to Nutanix Cluster
Connect-NutanixCluster -Server $nutanixcluster -UserName $user -Password ([Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($password))) -AcceptInvalidSSLCerts

#Connect to Virtual Centre
connect-viserver $vcenter
 
Write-Host "Enter the name of the VM you want to fast clone"

$vmname = read-host "VM Name to Clone"

#Create protection domain for this VM only
New-NTNXProtectionDomain -server $nutanixcluster -input $vmname

#Add VM to Nutanix protection domain
Add-NTNXProtectionDomainVM -name $vmname -names $vmname

#Create Local Nutanix Snapshot, get the time first
$time = Get-Date -format "dd-MMM-yyyy HH:mm"
Add-NTNXOutOfBandSchedule -name $vmname

#Sleep 10 seconds so snapshot is created
Start-Sleep -s 10

#List Local Nutanix Snapshots belonging to the VM
Get-NTNXProtectionDomainSnapshot -name $vmname
write-host = "Please enter snapshot ID to fast clone to a new VM"
$snapshotid = Read-Host "SnapshotID"



#Restore VM Snapshot 
Restore-NTNXEntity -Server $nutanixcluster -name $vmname -snapshotid $snapshotid -PathPrefix "/clone"

#VAAI Clone powered off Snapshot to New VM - this is required as Disk UUID's will be the same unless the VM is cloned
#Sleep 10 seconds until VM is added to inventory
Start-Sleep -s 10
$source_vm = Get-VM -name $vmname*| where {$_.PowerState -eq "PoweredOff"} | Get-View
$clonedvm = Get-VM -name $vmname*| where {$_.PowerState -eq "PoweredOff"}
write-host "VAAI Cloning $clonedvm" 
$clone_folder = $source_vm.parent
$clone_spec = new-object Vmware.Vim.VirtualMachineCloneSpec
$clone_spec.Location = new-object Vmware.Vim.VirtualMachineRelocateSpec
$clone_spec.Location.Transform = [Vmware.Vim.VirtualMachineRelocateTransformation]::flat
$clone_spec.Location.DiskMoveType = [Vmware.Vim.VirtualMachineRelocateDiskMoveOptions]::moveAllDiskBackingsAndAllowSharing
$clone_name = "${clonedvm}_clone ${time}"
$source_vm.CloneVM_Task($clone_folder, $clone_name, $clone_spec ) | Out-Null

#Delete original nutanix restored VM
Write-Host "Do you want to delete the Nutanix clone?"
Remove-VM $clonedvm -DeletePermanently 

#Delete Nutanix Snapshot
Remove-NTNXProtectionDomainSnapshot -ProtectionDomainName $vmname -snapshotid $snapshotid

#Delete Nutanix protection domain
Mark-NTNXProtectionDomainForRemoval -name $vmname


Write-Host "Done! $vmname has been fast cloned to $clone_name."
