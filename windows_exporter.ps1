# ================================
# CONFIGURACIÓN GENERAL
# ================================
$sharedTargetPath = "\\Ruta\a\la\carpeta\compartida"
$networkInterface = (Get-NetAdapter | Where-Object { $_.Status -eq "Up" -and $_.InterfaceDescription -notmatch "Virtual|Loopback" } | Select-Object -First 1).Name
$port = 18081
$computerName = $env:COMPUTERNAME
$hostname = "$computerName.dominio"
$target = "${hostname}:${port}"

# ================================
# ESCRITURA DEL JSON DE DISCOVERY
# ================================
Write-Output "DEBUG - COMPUTERNAME: '$computerName'"
Write-Output "DEBUG - Hostname generado: '$hostname'"
Write-Output "DEBUG - Target: '$target'"

if (-not $target -or $target.Trim() -eq "" -or $target -eq ":$port" -or $target -like "dominio:$port") {
    Write-Error "Target Prometheus vacío o inválido. Abortando escritura del JSON."
    exit 1
}

$sdObject = @(
    @{
        targets = @("${hostname}:${port}")
        labels = @{ job = "eventlog_exporter" }
    }
)

try {
    $jsonPath = Join-Path $sharedTargetPath "$computerName.json"
    $sdJson = ($sdObject | ForEach-Object { $_ | ConvertTo-Json -Depth 3 }) -join ",`n"
    $sdJson = "[`n$sdJson`n]"
    [System.IO.File]::WriteAllText($jsonPath, $sdJson, [System.Text.UTF8Encoding]::new($false))
    Write-Output "JSON de descubrimiento exportado correctamente en: $jsonPath"
} catch {
    Write-Error "Error al escribir el JSON de descubrimiento: $_"
}

# ================================
# FUNCIÓN PARA MÉTRICAS PROMETHEUS
# ================================
function Get-MetricsContent {
    $startDate = (Get-Date).AddDays(-5)

    $filterHash = @{
        LogName   = 'System'
        Level     = 1,2
        StartTime = $startDate
    }

    try {
        $events = Get-WinEvent -FilterHashtable $filterHash -ErrorAction Stop
        $criticalEvents = $events | Where-Object { $_.Level -eq 1 }
        $severeEvents   = $events | Where-Object { $_.Level -eq 2 }
    } catch {
        Write-Warning "No se pudieron obtener eventos: $_"
        $criticalEvents = @()
        $severeEvents = @()
    }

    $criticalCount = $criticalEvents.Count
    $severeCount = $severeEvents.Count

    function Format-EventDetails {
        param ($events, $title)
        $output = ""
        if ($events.Count -gt 0) {
            $output += "=== $title ===`n"
            $output += "TimeCreated        Id   Level        Message`n"
            $output += "------------       ---  ---------    ---------------------------------------------------`n"
            foreach ($event in $events) {
                $timeCreated = $event.TimeCreated.ToString("dd/MM/yyyy HH:mm:ss")
                $eventID = $event.Id
                $level = $event.LevelDisplayName
                $message = ($event.Message -replace "`n", " ") -replace '"', "'"
                $output += "${timeCreated}  ${eventID}  ${level}  ${message}`n"
            }
            $output += "`n"
        }
        return $output
    }

    $eventDetails = ""
    if ($criticalCount -gt 0) {
        $eventDetails += Format-EventDetails -events $criticalEvents -title "Eventos Críticos"
    }
    if ($severeCount -gt 0) {
        $eventDetails += Format-EventDetails -events $severeEvents -title "Errores Graves"
    }
    if ($criticalCount -eq 0 -and $severeCount -eq 0) {
        $eventDetails = "No hay ningún error durante los últimos 5 días.`n"
    }

    $ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -eq $networkInterface -and $_.IPAddress -notmatch "169.254.|127." } | Select-Object -First 1).IPAddress
    $cpuLoad = (Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average

    $initialStats = Get-NetAdapterStatistics -Name $networkInterface
    $initialSent = $initialStats.SentBytes
    $initialReceived = $initialStats.ReceivedBytes
    Start-Sleep -Seconds 1
    $finalStats = Get-NetAdapterStatistics -Name $networkInterface
    $finalSent = $finalStats.SentBytes
    $finalReceived = $finalStats.ReceivedBytes
    $bytesSentMB = [math]::Round(($finalSent - $initialSent) / 1MB, 3)
    $bytesReceivedMB = [math]::Round(($finalReceived - $initialReceived) / 1MB, 3)
    
    $disk = Get-PSDrive C
    $totalSpaceGB = [math]::Round(($disk.Used + $disk.Free) / 1GB, 2)
    $freeSpaceGB = [math]::Round($disk.Free / 1GB, 2)
    $diskUsagePercent = [math]::Round((($totalSpaceGB - $freeSpaceGB) / $totalSpaceGB) * 100, 2)
    $mem = Get-CimInstance Win32_OperatingSystem
    $totalMemoryGB = [math]::Round($mem.TotalVisibleMemorySize / 1MB, 2)
    $freeMemoryGB = [math]::Round($mem.FreePhysicalMemory / 1MB, 2)
    $ramUsagePercent = [math]::Round((($totalMemoryGB - $freeMemoryGB) / $totalMemoryGB) * 100, 2)
    $loggedUsers = (Get-WMIObject -Class Win32_ComputerSystem).UserName -replace "\\\\", "\\" -replace '"', "'"
    $osInfo = Get-CimInstance Win32_OperatingSystem
    $osVersion = "$($osInfo.Caption) $($osInfo.Version) Build $($osInfo.BuildNumber)" -replace "\\", "\\" -replace '"', "'"

    $eventComment = "# HELP windows_eventlog_details Detalles de eventos`n"
    $eventComment += "# TYPE windows_eventlog_details gauge`n"
    $eventDetails -split "`n" | ForEach-Object {
        if ($_ -ne "") {
            $eventComment += "# $_`n"
        } else {
            $eventComment += "#`n"
        }
    }

    $finalOutput = @"
# HELP system_ip_address Direccion IP del sistema
# TYPE system_ip_address gauge
system_ip_address{host="$computerName", ip="$ip"} 1
# HELP system_cpu_usage Uso de CPU en porcentaje
# TYPE system_cpu_usage gauge
system_cpu_usage{host="$computerName"} $cpuLoad
# HELP system_network_bytes_sent_MB MBps enviados
# TYPE system_network_bytes_sent_MB gauge
system_network_bytes_sent_MB{host="$computerName"} $bytesSentMB
# HELP system_network_bytes_received_MB MBps recibidos
# TYPE system_network_bytes_received_MB gauge
system_network_bytes_received_MB{host="$computerName"} $bytesReceivedMB
# HELP system_disk_total Espacio total en disco en GB
# TYPE system_disk_total gauge
system_disk_total{host="$computerName"} $totalSpaceGB
# HELP system_disk_free Espacio libre en disco en GB
# TYPE system_disk_free gauge
system_disk_free{host="$computerName"} $freeSpaceGB
# HELP system_disk_usage_percent Porcentaje de uso de disco
# TYPE system_disk_usage_percent gauge
system_disk_usage_percent{host="$computerName"} $diskUsagePercent
# HELP system_memory_total Memoria RAM total en GB
# TYPE system_memory_total gauge
system_memory_total{host="$computerName"} $totalMemoryGB
# HELP system_memory_usage Porcentaje de memoria RAM en uso
# TYPE system_memory_usage gauge
system_memory_usage{host="$computerName"} $ramUsagePercent
# HELP windows_eventlog_critical Numero de eventos criticos
# TYPE windows_eventlog_critical gauge
windows_eventlog_critical{host="$computerName"} $criticalCount
# HELP windows_eventlog_severe Numero de errores graves
# TYPE windows_eventlog_severe gauge
windows_eventlog_severe{host="$computerName"} $severeCount
# HELP system_info Informacion del usuario y sistema operativo
# TYPE system_info gauge
system_info{host="$computerName", user="$loggedUsers", os="$osVersion"} 1
$eventComment
"@

    return $finalOutput -replace "`r", ""
}

# ================================
# SERVIDOR HTTP
# ================================
try {
    $listener = [System.Net.HttpListener]::new()
    $listener.Prefixes.Add("http://+:$port/metrics/")
    $listener.Start()
    Write-Output "Servidor HTTP iniciado en http://localhost:$port/metrics/"
} catch {
    Write-Error "Error al iniciar el servidor HTTP: $_"
    exit 1
}

while ($true) {
    try {
        $context = $listener.GetContext()
        $response = $context.Response
        $response.ContentType = "text/plain"
        $metricsContent = Get-MetricsContent
        $metricsBytes = [System.Text.Encoding]::UTF8.GetBytes($metricsContent)
        $response.OutputStream.Write($metricsBytes, 0, $metricsBytes.Length)
        $response.OutputStream.Close()
    } catch {
        Write-Error "Error al procesar la solicitud HTTP: $_"
    }
}
