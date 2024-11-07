# Load required assemblies
Add-Type -AssemblyName PresentationFramework, PresentationCore

# Define the XAML for the GUI
$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Title="Server Health Check Version 1.0" Height="600" Width="1200">
    <Grid>
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
        </Grid.RowDefinitions>
        <StackPanel Orientation="Vertical" HorizontalAlignment="Center" Margin="10">
            <StackPanel Orientation="Horizontal" Margin="5">
                <Label Content="Enter Server Names (comma-separated):" VerticalAlignment="Center" Margin="5"/>
                <TextBox Name="txtServerNames" Width="600" Margin="5"/>
            </StackPanel>
            <StackPanel Orientation="Horizontal" HorizontalAlignment="Center" Margin="5">
                <Button Name="btnPing" Content="Ping Check" Margin="5"/>
                <Button Name="btnUptime" Content="Uptime Check" Margin="5"/>
                <Button Name="btnDiskUsage" Content="Disk Usage Check" Margin="5"/>
                <Button Name="btnCPUUsage" Content="CPU Usage Check" Margin="5"/>
                <Button Name="btnRAMUsage" Content="RAM Usage Check" Margin="5"/>
                <Button Name="btnInstalledApps" Content="Installed Apps Check" Margin="5"/>
                <Button Name="btnOSVersion" Content="OS Version Check" Margin="5"/>
                <Button Name="btnNICDetails" Content="NIC Details Check" Margin="5"/>
                <Button Name="btnTopCPUProcess" Content="Top RAM Process" Margin="5"/>
            </StackPanel>
        </StackPanel>
        <TextBox Name="txtOutput" Grid.Row="1" Margin="10" AcceptsReturn="True" VerticalScrollBarVisibility="Auto" IsReadOnly="True"/>
    </Grid>
</Window>
"@

# Load the XAML
$reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($xaml))
$window = [System.Windows.Markup.XamlReader]::Load($reader)

# Function to split server names
function Get-ServerNames {
    $serverNamesText = $window.FindName("txtServerNames").Text
    return $serverNamesText -split ",\s*"
}

# Append output to txtOutput
function Append-Output {
    param ([string]$text)
    $window.FindName("txtOutput").AppendText("$text`n")
}

# Function to perform ping check
function Ping-Server {
    param (
        [string]$serverName
    )
    try {
        $pingResult = Test-Connection -ComputerName $serverName -Count 2 -ErrorAction Stop
        if ($pingResult) {
            Append-Output "Ping to ${serverName} successful."
        }
    } catch {
        Append-Output "Ping to ${serverName} failed: $_"
    }
}

# Function to check disk usage
function Get-DiskUsage {
    param (
        [string]$serverName
    )
    try {
        $disks = Get-WmiObject -Class Win32_LogicalDisk -ComputerName $serverName -Filter "DriveType=3" -ErrorAction Stop
        if ($disks) {
            foreach ($disk in $disks) {
                $freeSpaceGB = [math]::round($disk.FreeSpace / 1GB, 2)
                $totalSizeGB = [math]::round($disk.Size / 1GB, 2)
                Append-Output "Drive ${disk.DeviceID} on ${serverName} has ${freeSpaceGB} GB free out of ${totalSizeGB} GB."
            }
        } else {
            Append-Output "No disks found for ${serverName}."
        }
    } catch {
        Append-Output "Failed to get disk usage for ${serverName}: $_"
    }
}

# Function to parse WMI datetime format
function Convert-WmiDateTime {
    param (
        [string]$wmiDateTime
    )
    # Convert WMI date-time format to DateTime
    $dateString = $wmiDateTime.Substring(0, 14)
    $timezoneOffset = [int]$wmiDateTime.Substring(15, 3) # Timezone offset in hours

    $year = $dateString.Substring(0, 4)
    $month = $dateString.Substring(4, 2)
    $day = $dateString.Substring(6, 2)
    $hour = $dateString.Substring(8, 2)
    $minute = $dateString.Substring(10, 2)
    $second = $dateString.Substring(12, 2)

    # Use ${} to ensure variable interpolation is correct
    $dateTimeString = "${year}-${month}-${day} ${hour}:${minute}:${second}"
    $dateTime = [datetime]::ParseExact($dateTimeString, 'yyyy-MM-dd HH:mm:ss', $null)
    return $dateTime.AddHours(-$timezoneOffset) # Adjust for timezone
}

# Function to get server uptime
function Get-Uptime {
    param (
        [string]$serverName
    )

    try {
        # Get the last boot time of the server
        $osInfo = Get-CimInstance -ClassName Win32_OperatingSystem -ComputerName $serverName -ErrorAction Stop
        $lastBootUpTime = $osInfo.LastBootUpTime

        # Calculate the uptime by subtracting the last boot time from the current time
        $uptime = (Get-Date) - $lastBootUpTime

        # Format the uptime as days, hours, minutes
        $uptimeFormatted = "{0} days, {1} hours, {2} minutes" -f $uptime.Days, $uptime.Hours, $uptime.Minutes

        # Output the uptime
        Append-Output "Uptime for ${serverName}: ${uptimeFormatted}"
    } catch {
        # Handle errors, such as the server being unreachable
        Append-Output "Failed to get uptime for ${serverName}: $_"
    }
}

# Function to check real-time CPU usage
function Get-CPUUsage {
    param (
        [string]$serverName
    )
    try {
        # Use Get-Counter to fetch the most recent CPU usage
        $counter = "\Processor(_Total)\% Processor Time"
        $counterSample = Get-Counter -ComputerName $serverName -Counter $counter -SampleInterval 1 -MaxSamples 1 -ErrorAction Stop

        # Extract the CPU usage value
        $cpuUsage = $counterSample.CounterSamples | Select-Object -ExpandProperty CookedValue

        # Check if CPU usage data is retrieved correctly
        if ($cpuUsage -eq $null) {
            throw "No CPU usage data retrieved from ${serverName}."
        }

        # Round the value for better readability
        $cpuUsage = [math]::Round($cpuUsage, 2)

        # Output the CPU usage
        Append-Output "Current CPU usage for ${serverName}: ${cpuUsage}%"
    } catch {
        # Display errors if getting CPU usage fails
        Append-Output "Failed to get CPU usage for ${serverName}: $_"
    }
}

# Function to check RAM usage
function Get-RAMUsage {
    param (
        [string]$serverName
    )
    try {
        $memory = Get-WmiObject -Class Win32_OperatingSystem -ComputerName $serverName
        $totalMemory = [math]::round($memory.TotalVisibleMemorySize / 1MB, 2)
        $freeMemory = [math]::round($memory.FreePhysicalMemory / 1MB, 2)
        $usedMemory = [math]::round($totalMemory - $freeMemory, 2)
        $usedPercentage = [math]::round(($usedMemory / $totalMemory) * 100, 2)
        Append-Output "RAM usage for ${serverName}: ${usedMemory} GB used out of ${totalMemory} GB (${usedPercentage}%)."
    } catch {
        Append-Output "Failed to get RAM usage for ${serverName}: $_"
    }
}

# Function to list installed applications
function Get-InstalledApps {
    param (
        [string]$serverName
    )
    try {
        $apps = Get-WmiObject -Class Win32_Product -ComputerName $serverName -ErrorAction Stop
        if ($apps) {
            Append-Output "Installed applications on ${serverName}:"
            foreach ($app in $apps) {
                Append-Output "$($app.Name) - Version: $($app.Version)"
            }
        } else {
            Append-Output "No installed applications found for ${serverName}."
        }
    } catch {
        Append-Output "Failed to get installed applications for ${serverName}: $_"
    }
}

# Function to get OS version
function Get-OSVersion {
    param (
        [string]$serverName
    )
    try {
        $os = Get-WmiObject -Class Win32_OperatingSystem -ComputerName $serverName -ErrorAction Stop
        $version = $os.Version
        $buildNumber = $os.BuildNumber
        $servicePack = $os.ServicePackMajorVersion
        Append-Output "OS Version for ${serverName}: Version ${version}, Build ${buildNumber}, Service Pack ${servicePack}."
    } catch {
        Append-Output "Failed to get OS version for ${serverName}: $_"
    }
}

# Function to get NIC details
function Get-NICDetails {
    param (
        [string]$serverName
    )
    try {
        $nicConfigs = Get-WmiObject -Class Win32_NetworkAdapterConfiguration -ComputerName $serverName -Filter "IPEnabled = True" -ErrorAction Stop
        if ($nicConfigs) {
            Append-Output "NIC details for ${serverName}:"
            foreach ($nic in $nicConfigs) {
                $macAddress = $nic.MACAddress
                $ipAddresses = $nic.IPAddress -join ", "
                $description = $nic.Description
                Append-Output "Description: $description"
                Append-Output "MAC Address: $macAddress"
                Append-Output "IP Addresses: $ipAddresses"
                Append-Output ""
            }
        } else {
            Append-Output "No NIC details found for ${serverName}."
        }
    } catch {
        Append-Output "Failed to get NIC details for ${serverName}: $_"
    }
}

# Function to get top CPU-consuming processes
function Get-TopCPUProcesses {
    param (
        [string]$serverName,
        [int]$topN = 5
    )
    try {
        # Get the processes using WMI
        $processes = Get-WmiObject -Class Win32_Process -ComputerName $serverName -ErrorAction Stop |
                     Sort-Object -Property WorkingSetSize -Descending |
                     Select-Object -First $topN

        if ($processes) {
            Append-Output "Top ${topN} RAM-consuming processes on ${serverName}:"
            foreach ($proc in $processes) {
                $processName = $proc.Name
                $cpuUsage = [math]::Round($proc.WorkingSetSize / 1MB, 2) # Memory in MB (as proxy for CPU)
                Append-Output "Process: $processName - Memory Usage: $cpuUsage MB"
            }
        } else {
            Append-Output "No RAM processes found for ${serverName}."
        }
    } catch {
        Append-Output "Failed to get top RAM processes for ${serverName}: $_"
    }
}

# Event Handlers
$window.FindName("btnPing").Add_Click({
    $window.FindName("txtOutput").Clear()  # Clear output
    foreach ($server in Get-ServerNames) {
        Ping-Server -serverName $server
    }
})

$window.FindName("btnDiskUsage").Add_Click({
    $window.FindName("txtOutput").Clear()  # Clear output
    foreach ($server in Get-ServerNames) {
        Get-DiskUsage -serverName $server
    }
})

$window.FindName("btnUptime").Add_Click({
    $window.FindName("txtOutput").Clear()  # Clear output
    foreach ($server in Get-ServerNames) {
        Get-Uptime -serverName $server
    }
})

$window.FindName("btnCPUUsage").Add_Click({
    $window.FindName("txtOutput").Clear()  # Clear output
    foreach ($server in Get-ServerNames) {
        Get-CPUUsage -serverName $server
    }
})

$window.FindName("btnRAMUsage").Add_Click({
    $window.FindName("txtOutput").Clear()  # Clear output
    foreach ($server in Get-ServerNames) {
        Get-RAMUsage -serverName $server
    }
})

$window.FindName("btnInstalledApps").Add_Click({
    $window.FindName("txtOutput").Clear()  # Clear output
    foreach ($server in Get-ServerNames) {
        Get-InstalledApps -serverName $server
    }
})

$window.FindName("btnOSVersion").Add_Click({
    $window.FindName("txtOutput").Clear()  # Clear output
    foreach ($server in Get-ServerNames) {
        Get-OSVersion -serverName $server
    }
})

$window.FindName("btnNICDetails").Add_Click({
    $window.FindName("txtOutput").Clear()  # Clear output
    foreach ($server in Get-ServerNames) {
        Get-NICDetails -serverName $server
    }
})

$window.FindName("btnTopCPUProcess").Add_Click({
    $window.FindName("txtOutput").Clear()  # Clear output
    foreach ($server in Get-ServerNames) {
        Get-TopCPUProcesses -serverName $server
    }
})

# Show the window
$window.ShowDialog()
