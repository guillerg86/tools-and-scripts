#######################################################################################
# @author: Guille Rodriguez https://github.com/guillerg86
#
# Conecta al servidor VMWare vSphere y extrae la información de las máquinas virtuales
# en un fichero CSV. Si se dispone de un servidor con API-Rest, entonces también
# puede enviar la información en formato JSON.
#
# En la variable Env:VCENTER_HOST se pueden añadir tantos servidores vSphere como se desee
# sin embargo es necesario que tengan la misma contraseña para que el script pueda conectarse
#
# De cada servidor vSphere extrae la siguiente información de cada VM.
# - Folder
# - Name
# - State (Powered On, Off, Suspend)
# - Virtual CPUs
# - RAM (in GiB)
# - OS (VMware configured, not real)
# - VMWare Tools Versión
# - VMWare Tools State (Running, not running)
# - ESX Host (in wich baremetal is machine running)
# - Last snapshot name
# - Last snapshot size (in GiB)
# - Num of virtual disks attached
# - Partitions free space
#
# Como hacerlo funcionar? 
# - Instala PowerCLI https://docs.vmware.com/es/VMware-vSphere/7.0/com.vmware.esxi.install.doc/GUID-F02D0C2D-B226-4908-9E5C-2E783D41FE2D.html
# - Configura los servidores vSphere en la variable VCENTER_HOST
# - Abre una ventana Powershell y lanza el siguiente comando
#   powershell.exe -ExecutionPolicy bypass -File vcenter_extractor.ps1
#
# También extrae la informacion de los datastores, si no deseas dicha información
# simplemente comenta la linea:
#   $datastores | export-csv -Path "vmware_datastores.csv" -NoTypeInformation
#  
#######################################################################################

$Env:VCENTER_USER = ""
$Env:VCENTER_PASS = ""
$Env:VCENTER_HOST = @("vsphere1.domain.tld","vsphere2.domain.tld")
function get_datastores_info {
    Param(
        [Parameter(Mandatory=$true)] $connection,
        [Parameter(Mandatory=$true)] $dtstoresarray
    )

    $dtstores = get-datastore -Server $connection | select-object name, FreespaceGB, CapacityGB, @{Label=”Provisioned”;E={($_.CapacityGB – $_.FreespaceGB +($_.extensiondata.summary.uncommitted/1GB))}}|sort name
    foreach ($dt in $dtstores) {
        $new_obj = New-Object -TypeName psobject
        $new_obj | Add-Member -NotePropertyName name -NotePropertyValue $dt.name
        $new_obj | Add-Member -NotePropertyName free_space_gb -NotePropertyValue 0
        $new_obj | Add-Member -NotePropertyName capacity_gb -NotePropertyValue 0
        $new_obj | Add-Member -NotePropertyName provisioned -NotePropertyValue 0
        $new_obj | Add-Member -NotePropertyName host -NotePropertyValue $connection.name

        $new_obj.free_space_gb = [math]::round($dt.FreespaceGB,2)
        $new_obj.capacity_gb = [math]::round($dt.CapacityGB,2)
        $new_obj.provisioned = [math]::round($dt.Provisioned,2)

        $dtstoresarray.Add($new_obj) | Out-Null
    }

}

# VMWARE FUNCTIONS ------------
function get_vms_filtered_info{
    Param(
        [Parameter(Mandatory=$true)] $connection,
        [Parameter(Mandatory=$true)] $vms_arraylist
    )
    $virtualMachines = Get-VM -Server $connection | select Folder,Name,powerstate,guest,numcpu,memoryGB,VMHost | sort-object -property @{Expression="Folder";Descending=$false},@{Expression="Name";Descending=$false}
    foreach ($vm in $virtualMachines) {
        $new_obj = New-Object -TypeName psobject
        $new_obj | Add-Member -NotePropertyName folder -NotePropertyValue $vm.Folder.Name
        $new_obj | Add-Member -NotePropertyName name -NotePropertyValue $vm.name
        $new_obj | Add-Member -NotePropertyName power_state -NotePropertyValue $vm.powerstate.value__
        $new_obj | Add-Member -NotePropertyName num_cpu -NotePropertyValue $vm.numcpu
        $new_obj | Add-Member -NotePropertyName mem_gb -NotePropertyValue 0
        $new_obj | Add-Member -NotePropertyName os_system -NotePropertyValue $vm.Guest.OSFullName
        $new_obj | Add-Member -NotePropertyName tools_version -NotePropertyValue $vm.Guest.ToolsVersion
        $new_obj | Add-Member -NotePropertyName tools_status -NotePropertyValue $null
        $new_obj | Add-Member -NotePropertyName tools_running_status -NotePropertyValue $null
        $new_obj | Add-Member -NotePropertyName host -NotePropertyValue $vm.VMHost.Name.Replace(".domain.tld","").ToUpper()
        $new_obj | Add-Member -NotePropertyName snapshot_name -NotePropertyValue $null
        $new_obj | Add-Member -NotePropertyName snapshot_sizegb -NotePropertyValue 0
        $new_obj | Add-Member -NotePropertyName disk_number -NotePropertyValue 0
        $new_obj | Add-Member -NotePropertyName disk_space -NotePropertyValue ""
        
        # No permite asignarlo directametne al declarar la variable
        $new_obj.mem_gb = [math]::round($vm.memoryGB,2)

        # Vamos a extraer el snapshot sobre el que esta corriendo
        $snaps = Get-VM $vm.name -Server $connection | Get-Snapshot | Where-Object {$_.IsCurrent -eq $true} 
        foreach ($snap in $snaps) {
            $new_obj.snapshot_name = $snap.Name
            $new_obj.snapshot_sizegb = [math]::round($snap.SizeGB,2)
        }
        # Vamos a traducir el estado
        if ( $new_obj.power_state -eq 0 ) { $new_obj.power_state = "OFF" }
        elseif ( $new_obj.power_state -eq 1 ) { $new_obj.power_state = "ON" }
        elseif ( $new_obj.power_State -eq 2 ) { $new_obj.power_state = "SUSPENDED" }

        # Vamos a extraer las tools status y mas informacion del guest
        $status = Get-VM $vm.name -Server $connection | Get-View
        $new_obj.tools_status = $status.Guest.ToolsStatus.value__
        $new_obj.tools_running_status = $status.Guest.ToolsRunningStatus
        if ( $new_obj.tools_status -eq 1 ) { $new_obj.tools_status = "NOT RUN" }
        elseif ( $new_obj.tools_status -eq 2 ) { $new_obj.tools_status = "OLD" }
        elseif ( $new_obj.tools_status -eq 3 ) { $new_obj.tools_status = "OK" }

        # Vamos a extraer la informacion de los discos duros
        #Write-Host $status.Guest.Disk
        foreach ($disk in $status.Guest.Disk) {
            $free_percent = ($disk.FreeSpace / $disk.Capacity)*100 
            $free_percent = [math]::round($free_percent,2)
            $new_obj.disk_space += $disk.DiskPath.Replace("\","")+" "+$free_percent+"% free. "
            $new_obj.disk_number = $new_obj.disks_number +1;
        }


        # Extraemos las IP
        $ips = ""
        foreach ($ip in $vm.Guest.IPAddress) {
            $ips += $ip+" " 
        }
        $new_obj | Add-Member -NotePropertyName ip_address -NotePropertyValue $ips.Trim()
        $vms_arraylist.Add($new_obj) | Out-Null
    }
}

# MAIN
function main{
    
    Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false | Out-Null
    

    $vms = New-Object -TypeName "System.Collections.ArrayList"
    $datastores = New-Object -TypeName "System.Collections.ArrayList"
    foreach ($vicenter in $Env:VCENTER_HOST.split(" ",[System.StringSplitOptions]::RemoveEmptyEntries)) {
        Write-Host "Connecting to "$vicenter ... " " -NoNewline
        $vmCon = Connect-VIServer -Server $vicenter -Protocol https -User $Env:VCENTER_USER -Password $Env:VCENTER_PASS -NotDefault
        if ( $vmCon -eq $null ) {
            Write-Error "Error on connect"
            return
        } else {
            Write-Host "connected succesfully "
        }
        get_vms_filtered_info -connection $vmCon -vms_arraylist $vms
        get_datastores_info -connection $vmCon -dtstoresarray $datastores

        Disconnect-VIServer -Server $vmCon -Force -Confirm:$false
    }

    $vms | export-csv -Path "vmware_virtualmachines.csv" -NoTypeInformation
    $datastores | export-csv -Path "vmware_datastores.csv" -NoTypeInformation
    
	
	## SOLO SI TIENES UNA API REST y quieres enviarlo a la API
	# $api_path = "https://yourApiRest.endpointBaseDomain.tld"
    # Write-Host "Enviando datos de VMachines"
    # $json_data = $vms | ConvertTo-Json
    # $json_data = [System.Text.Encoding]::UTF8.GetBytes($json_data)
    # Invoke-RestMethod -Uri $api_path"/api/v1/vmachines-batch/" -Method Post -Body $json_data -ContentType "application/json"
    
    # Write-Host "Enviando datos de Datastores"
    # $json_data = $datastores | ConvertTo-Json
    # $json_data = [System.Text.Encoding]::UTF8.GetBytes($json_data)
    # Invoke-RestMethod -Uri $api_path"/api/v1/vdatastores-batch/" -Method Post -Body $json_data -ContentType "application/json"
}

main



