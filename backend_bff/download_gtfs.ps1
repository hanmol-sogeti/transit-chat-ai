$envPath = Join-Path $PSScriptRoot '.env'
if (-Not (Test-Path $envPath)) { Write-Error "Env file not found: $envPath"; exit 1 }
$lines = Get-Content $envPath | Where-Object { $_ -and -not $_.TrimStart().StartsWith('#') }
$key = $null
foreach ($l in $lines) {
    if ($l -match '^(\w+)=\s*(.*)$') {
        $k = $matches[1]
        $v = $matches[2].Trim('"')
        if ($k -eq 'GTFS_SWEDEN3_STATIC_KEY') { $key = $v; break }
    }
}
if (-not $key) { Write-Error "GTFS_SWEDEN3_STATIC_KEY not found in $envPath"; exit 1 }
$destDir = Join-Path $PSScriptRoot '..\ul_transit_demo\data'
New-Item -ItemType Directory -Path $destDir -Force | Out-Null
$zipPath = Join-Path $destDir 'latest.zip'
$url = "https://opendata.samtrafiken.se/gtfs/sweden3/latest.zip?key=$key"
Write-Output "Downloading GTFS to $zipPath..."
$hdr = @{ 'Accept-Encoding' = 'gzip, deflate'; 'User-Agent' = 'ul-transit-demo/1.0' }
Invoke-WebRequest -Uri $url -OutFile $zipPath -Headers $hdr -UseBasicParsing
if (-not (Test-Path $zipPath)) { Write-Error "Download failed"; exit 1 }
Write-Output "Extracting..."
Expand-Archive -Path $zipPath -DestinationPath $destDir -Force
Write-Output "Looking for stops.txt in $destDir"
Get-ChildItem -Path $destDir -Filter 'stops.txt' -Recurse | Select-Object FullName | Format-List
