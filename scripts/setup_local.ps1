# HotelGroup - lokalne odtworzenie PostgreSQL + staging + core + mart
# Windows PowerShell 5.1 / PowerShell 7; uruchamiaj z dowolnego katalogu.
[CmdletBinding()]
param(
    [switch]$Reset,
    [switch]$ReuseGenerated,
    [switch]$CoreOnly,
    [switch]$SkipInstall
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$databaseName = 'hotelgroup_dw'  # Istniejace skrypty US-03-04 wymagaja dokladnie tej nazwy.
$originalLocation = Get-Location
$originalPassword = [Environment]::GetEnvironmentVariable('PGPASSWORD', 'Process')
$originalEncoding = [Environment]::GetEnvironmentVariable('PGCLIENTENCODING', 'Process')
$originalPythonUtf8 = [Environment]::GetEnvironmentVariable('PYTHONUTF8', 'Process')
$originalPythonIo = [Environment]::GetEnvironmentVariable('PYTHONIOENCODING', 'Process')
$originalPgSettings = @{}
foreach ($key in @('PG_HOST','PG_PORT','PG_DATABASE','PG_USER','PG_PASSWORD')) {
    $originalPgSettings[$key] = [Environment]::GetEnvironmentVariable($key, 'Process')
}
$tempSql = $null
$tempVerify = $null

function Step([string]$message) { Write-Host "`n==> $message" -ForegroundColor Cyan }
function Fail([string]$message) { throw $message }
function Execute([string]$exe, [string[]]$arguments, [string]$label) {
    Step $label
    & $exe @arguments
    if ($LASTEXITCODE -ne 0) { Fail "${label}: kod wyjscia $LASTEXITCODE. Zatrzymano automatyzacje." }
}
function SqlFile([string]$file, [string]$label) {
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { Fail "Brak pliku SQL: $file" }
    Execute $psql @('-X','-w','-v','ON_ERROR_STOP=1','-h',$pgHost,'-p',$pgPort,'-U',$pgUser,'-d',$databaseName,'-f',$file) $label
}
function Get-Tool([string]$name) {
    $cmd = Get-Command $name -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $programFiles = ${env:ProgramFiles}
    if ($programFiles) {
        $candidate = Join-Path $programFiles ("PostgreSQL\18\bin\" + $name + '.exe')
        if (Test-Path -LiteralPath $candidate) { return $candidate }
        $pgDir = Join-Path $programFiles 'PostgreSQL'
        if (Test-Path -LiteralPath $pgDir) {
            $bins = Get-ChildItem -LiteralPath $pgDir -Directory | Sort-Object Name -Descending
            foreach ($bin in $bins) {
                $candidate = Join-Path $bin.FullName ("bin\" + $name + '.exe')
                if (Test-Path -LiteralPath $candidate) { return $candidate }
            }
        }
    }
    Fail "Nie znaleziono $name.exe (PATH ani Program Files\PostgreSQL)."
}

try {
    Set-Location -LiteralPath $root
    Step "HotelGroup | tryb: $(if ($Reset) {'RESET'} else {'PIERWSZA INSTALACJA'}) | baza: $databaseName"

    $envPath = Join-Path $root '.env'
    if (-not (Test-Path -LiteralPath $envPath -PathType Leaf)) {
        Fail 'Brak lokalnego .env. Skopiuj .env.example do .env i ustaw wlasne PG_HOST/PORT/USER/PASSWORD.'
    }
    $settings = @{}
    foreach ($line in [System.IO.File]::ReadAllLines($envPath, [System.Text.Encoding]::UTF8)) {
        $trimmed = $line.Trim()
        if (-not $trimmed -or $trimmed.StartsWith('#')) { continue }
        $parts = $trimmed.Split('=', 2)
        if ($parts.Count -ne 2) { continue }
        $key = $parts[0].Trim()
        $value = $parts[1].Trim()
        if (($value.StartsWith('"') -and $value.EndsWith('"')) -or
            ($value.StartsWith("'") -and $value.EndsWith("'"))) {
            $value = $value.Substring(1, $value.Length - 2)
        }
        $settings[$key] = $value
    }
    foreach ($required in @('PG_HOST','PG_PORT','PG_DATABASE','PG_USER','PG_PASSWORD')) {
        if (-not $settings.ContainsKey($required) -or [string]::IsNullOrWhiteSpace($settings[$required])) {
            Fail "Brak $required w .env."
        }
    }
    if ($settings['PG_DATABASE'] -cne $databaseName) {
        Fail "Odmowa: PG_DATABASE musi byc $databaseName (skrypty US-03-04 zawieraja kontrole nazwy bazy)."
    }
    if ($settings['PG_PASSWORD'] -eq 'TU_WPISZ_SWOJE_HASLO') { Fail 'Ustaw prawdziwe PG_PASSWORD w .env.' }
    if ($env:ETL_DATABASE_URL) { Fail 'Usun ETL_DATABASE_URL ze zmiennych sesji: moze przekierowac ETL na inna baze.' }
    $pgHost = $settings['PG_HOST']; $pgPort = $settings['PG_PORT']; $pgUser = $settings['PG_USER']
    if ($pgHost -notin @('localhost', '127.0.0.1', '::1')) {
        Fail 'Odmowa: lokalny setup dopuszcza tylko PG_HOST=localhost, 127.0.0.1 lub ::1.'
    }
    $portValue = 0
    if (-not [int]::TryParse($pgPort, [ref]$portValue) -or $portValue -lt 1 -or $portValue -gt 65535) {
        Fail 'PG_PORT musi byc numerem portu 1..65535.'
    }
    foreach ($entry in $settings.GetEnumerator()) {
        if ($entry.Key -match '^PG_(HOST|PORT|DATABASE|USER|PASSWORD)$') {
            [Environment]::SetEnvironmentVariable($entry.Key, $entry.Value, 'Process')
        }
    }
    $env:PGPASSWORD = $settings['PG_PASSWORD']
    $env:PGCLIENTENCODING = 'UTF8'
    $env:PYTHONUTF8 = '1'
    $env:PYTHONIOENCODING = 'utf-8'

    $python = Join-Path $root '.venv\Scripts\python.exe'
    if (-not (Test-Path -LiteralPath $python)) {
        Step 'Tworzenie .venv'
        & python -m venv (Join-Path $root '.venv')
        if ($LASTEXITCODE -ne 0) { Fail 'Nie udalo sie utworzyc .venv; wymagany Python w PATH.' }
    }
    if (-not $SkipInstall) {
        Execute $python @('-m','pip','install','--disable-pip-version-check','-r',(Join-Path $root 'requirements.txt')) 'Instalacja zaleznosci Python'
    }

    $psql = Get-Tool 'psql'
    $dump = Get-Tool 'pg_dump'
    Execute $psql @('-X','-w','-h',$pgHost,'-p',$pgPort,'-U',$pgUser,'-d','postgres','-c','SELECT current_user, version();') 'Test polaczenia PostgreSQL'

    $exists = & $psql -X -w -A -t -h $pgHost -p $pgPort -U $pgUser -d postgres -c "SELECT 1 FROM pg_database WHERE datname = '$databaseName';"
    if ($LASTEXITCODE -ne 0) { Fail 'Nie mozna sprawdzic istnienia bazy.' }
    $databaseExists = @($exists) -contains "1"
    if ($Reset) {
        Write-Host "UWAGA: -Reset usuwa WSZYSTKIE dane w lokalnej bazie $databaseName." -ForegroundColor Yellow
        Write-Host 'Automatycznie wykonamy backup .backup, jesli baza istnieje.' -ForegroundColor Yellow
        $answer = Read-Host "Wpisz dokladnie USUN $databaseName, aby potwierdzic reset"
        if ($answer -cne "USUN $databaseName") { Fail 'Reset anulowany. Nie zmieniono bazy.' }
    } elseif ($databaseExists) {
        Fail "Baza $databaseName juz istnieje. Domyslny setup niczego nie nadpisuje. Uzyj -Reset (backup + potwierdzenie), jesli naprawde chcesz ja odtworzyc."
    }

    # Generator PMS tworzy plik wzgledem aktualnego katalogu, inaczej niz generatory CM/CSV.
    $generatorDir = Join-Path $root 'database\generator'
    $generated = @('pms_source.db','channel_manager.json','financial_data.csv')
    if ($ReuseGenerated) {
        foreach ($item in $generated) {
            $file = Join-Path $generatorDir $item
            if (-not (Test-Path -LiteralPath $file -PathType Leaf) -or (Get-Item -LiteralPath $file).Length -eq 0) {
                Fail "-ReuseGenerated: brak lub pusty plik $file"
            }
        }
        Step 'Ponowne wykorzystanie trzech lokalnych plikow danych (bez generowania)'
    } else {
        Push-Location -LiteralPath $generatorDir
        try {
            Execute $python @((Join-Path $generatorDir 'generate_pms_data.py')) 'Generator PMS -> pms_source.db'
        } finally { Pop-Location }
        Execute $python @((Join-Path $generatorDir 'generate_channel_manager.py')) 'Generator Channel Manager -> JSON'
        Execute $python @((Join-Path $generatorDir 'generate_financial_data.py')) 'Generator finansow -> CSV'
        foreach ($item in $generated) {
            $file = Join-Path $generatorDir $item
            if (-not (Test-Path -LiteralPath $file -PathType Leaf) -or (Get-Item -LiteralPath $file).Length -eq 0) {
                Fail "Generator nie utworzyl poprawnego pliku: $file"
            }
        }
    }

    $configFile = Join-Path $root 'etl\config.json'
    if (-not (Test-Path -LiteralPath $configFile -PathType Leaf)) {
        $config = @'
{
  "source_timezone": "Europe/Warsaw",
  "source_currencies": {
    "pms_reservations": "PLN",
    "cm_channels": "PLN",
    "fin_budgets_costs": "PLN"
  }
}
'@
        [System.IO.File]::WriteAllText($configFile, $config, (New-Object System.Text.UTF8Encoding($false)))
        Step 'Utworzono lokalny etl/config.json (PLN)'
    }
    $configObject = Get-Content -LiteralPath $configFile -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($configObject.source_timezone -ne 'Europe/Warsaw') {
        Fail 'etl/config.json: wymagana source_timezone=Europe/Warsaw; sprawdz konfiguracje.'
    }
    foreach ($source in @('pms_reservations','cm_channels','fin_budgets_costs')) {
        if ($configObject.source_currencies.$source -cne 'PLN') {
            Fail "etl/config.json: dla $source oczekiwano PLN."
        }
    }

    # Skrypt bazowy zawiera CREATE DATABASE w pierwszej linii; wykonywany wewnatrz bazy
    # nie moze zawierac tego polecenia. Usuwamy JEDYNIE pierwsze CREATE DATABASE z kopii tymczasowej.
    $schemaPath = Join-Path $root 'database\Skrypty_do_odtworzenia_bazy.sql'
    $schemaText = [System.IO.File]::ReadAllText($schemaPath, [System.Text.Encoding]::UTF8)
    $createDb = New-Object System.Text.RegularExpressions.Regex('(?im)^CREATE\s+DATABASE\s+hotelgroup_dw\s*;[ \t]*(?:\r?\n)?')
    if ($createDb.Matches($schemaText).Count -ne 1) { Fail 'Nieoczekiwana liczba CREATE DATABASE w skrypcie bazowym (wymagane dokladnie 1).' }
    $baseText = $createDb.Replace($schemaText, '', 1)
    if ([regex]::IsMatch($baseText,'(?im)^\s*(DROP\s+(DATABASE|SCHEMA)|CREATE\s+DATABASE)\b')) {
        Fail 'Bazowy skrypt zawiera niebezpieczne DROP DATABASE/SCHEMA lub dodatkowe CREATE DATABASE.'
    }
    $tempSql = Join-Path ([System.IO.Path]::GetTempPath()) ("hotelgroup_schema_" + [guid]::NewGuid().ToString('N') + '.sql')
    [System.IO.File]::WriteAllText($tempSql, $baseText, (New-Object System.Text.UTF8Encoding($false)))

    if ($Reset -and $databaseExists) {
        $backupDir = Join-Path $root 'backups'
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
        $backupPath = Join-Path $backupDir ("${databaseName}_" + (Get-Date -Format 'yyyyMMdd_HHmmss') + '_' + [guid]::NewGuid().ToString('N').Substring(0,6) + '.backup')
        Execute $dump @('-w','-Fc','-h',$pgHost,'-p',$pgPort,'-U',$pgUser,'-d',$databaseName,'-f',$backupPath) 'Backup aktualnej bazy przed resetem'
        if (-not (Test-Path -LiteralPath $backupPath) -or (Get-Item $backupPath).Length -eq 0) { Fail 'Nie udalo sie potwierdzic kopii zapasowej.' }
        Write-Host "Kopia zapasowa: $backupPath" -ForegroundColor Green
        Execute $psql @('-X','-w','-v','ON_ERROR_STOP=1','-h',$pgHost,'-p',$pgPort,'-U',$pgUser,'-d','postgres','-c',"DROP DATABASE $databaseName;") 'Usuniecie lokalnej bazy po backupie'
    }

    Execute $psql @('-X','-w','-v','ON_ERROR_STOP=1','-h',$pgHost,'-p',$pgPort,'-U',$pgUser,'-d','postgres','-c',"CREATE DATABASE $databaseName;") 'Utworzenie pustej bazy HotelGroup'
    Execute $psql @('-X','-w','-v','ON_ERROR_STOP=1','-1','-h',$pgHost,'-p',$pgPort,'-U',$pgUser,'-d',$databaseName,'-f',$tempSql) 'Schematy staging / core / mart i tabele bazowe'

    # Importy musza odbyc sie PRZED migracja ETL, ktora zamienia daty/kwoty staging na TEXT.
    $importers = Join-Path $generatorDir 'Implementacja_Generatora'
    Execute $python @((Join-Path $importers 'load_staging_pms.py')) 'Import SQLite PMS -> staging'
    Execute $python @((Join-Path $importers 'load_staging_channel_manager.py')) 'Import Channel Manager JSON -> staging'
    Execute $python @((Join-Path $importers 'load_staging_financial.py')) 'Import finansow CSV -> staging'
    Execute $python @('-m','etl.check_staging') 'Odczyt kontrolny kontraktu staging'
    Execute $python @('-m','etl.run_cleaning','--config','etl/config.json','--migrate') 'Migracja US-02-02 staging -> core.clean_*'
    Execute $python @('-m','etl.run_cleaning','--config','etl/config.json') 'Oczyszczanie i walidacja US-02-02'

    $etlStatus = & $psql -X -w -A -t -h $pgHost -p $pgPort -U $pgUser -d $databaseName -c 'SELECT status FROM core.etl_runs ORDER BY started_at DESC LIMIT 1;'
    if ($LASTEXITCODE -ne 0) { Fail 'Nie mozna odczytac statusu US-02-02.' }
    $etlStatus = ([string]($etlStatus | Select-Object -First 1)).Trim()
    if ($etlStatus -notin @('completed','completed_with_rejections')) { Fail "ETL nie opublikowal danych; status: $etlStatus" }
    Write-Host "Status ETL: $etlStatus" -ForegroundColor Green

    if (-not $CoreOnly) {
        $migrationDir = Join-Path $root 'database\migrations'
        $seedsDir = Join-Path $root 'database\seeds'
        SqlFile (Join-Path $migrationDir 'US-03-04_migracja_fct_reservations.sql') 'Migracja struktury FactReservation'
        SqlFile (Join-Path $migrationDir 'US-03-04_dim_date_unknown.sql') 'DimDate: UNKNOWN / NOT_APPLICABLE'
        SqlFile (Join-Path $seedsDir 'US-03-04_load_dimensions.sql') 'Zasilenie 5 wymiarow'
        SqlFile (Join-Path $seedsDir 'US-03-05_load_room_dimensions.sql') 'Zasilenie DimRoom i DimRoomType'
        SqlFile (Join-Path $seedsDir 'US-03-04_load_fct_reservations.sql') 'Zasilenie FactReservation'
    }

    $verify = @'
DO $check$
DECLARE
    source_count bigint;
    fact_count bigint;
    no_links bigint;
    source_cancels bigint;
    fact_cancels bigint;
BEGIN
    SELECT count(*) INTO source_count FROM core.clean_pms_reservations;
    IF source_count < 50000 THEN
        RAISE EXCEPTION 'Za malo zaakceptowanych rezerwacji: %', source_count;
    END IF;
    IF EXISTS (SELECT 1 FROM core.clean_pms_reservations
               HAVING max(booking_date) < min(booking_date) + INTERVAL '24 months') THEN
        RAISE EXCEPTION 'Zbyt krotki zakres dat rezerwacji';
    END IF;
    IF EXISTS (SELECT 1 FROM core.clean_pms_reservations WHERE currency IS DISTINCT FROM 'PLN') THEN
        RAISE EXCEPTION 'Wykryto walute inna niz PLN';
    END IF;
    IF current_setting('hotelgroup.check_mart', true) = 'yes' THEN
        SELECT count(*), coalesce(sum(cancellation_count), 0)
        INTO fact_count, fact_cancels FROM mart.fct_reservations;
        SELECT count(*) INTO source_cancels
        FROM core.clean_pms_reservations WHERE status = 'Anulowana';
        IF fact_count <> source_count OR fact_cancels <> source_cancels THEN
            RAISE EXCEPTION 'Niezgodna liczba rezerwacji/anulacji: core %, mart % / core anulacje %, mart %',
                source_count, fact_count, source_cancels, fact_cancels;
        END IF;
        SELECT count(*) INTO no_links FROM mart.fct_reservations
        WHERE hotel_sk IS NULL OR channel_sk IS NULL OR primary_guest_sk IS NULL
           OR segment_sk IS NULL OR booking_date_sk IS NULL OR arrival_date_sk IS NULL
           OR departure_date_sk IS NULL OR cancellation_date_sk IS NULL
           OR currency_code IS DISTINCT FROM 'PLN';
        IF no_links <> 0 THEN RAISE EXCEPTION 'Brakujace klucze / niepoprawna waluta: %', no_links; END IF;
    END IF;
    RAISE NOTICE 'PASS: core % zaakceptowanych rezerwacji; mart kontrolowany: %', source_count,
      current_setting('hotelgroup.check_mart', true);
END
$check$;
SELECT 'staging.pms_reservations' AS tabela, count(*) AS rekordy FROM staging.pms_reservations
UNION ALL SELECT 'core.clean_pms_reservations', count(*) FROM core.clean_pms_reservations
UNION ALL SELECT 'mart.fct_reservations', count(*) FROM mart.fct_reservations;
'@
    $tempVerify = Join-Path ([System.IO.Path]::GetTempPath()) ("hotelgroup_verify_" + [guid]::NewGuid().ToString('N') + '.sql')
    [System.IO.File]::WriteAllText($tempVerify, $verify, (New-Object System.Text.UTF8Encoding($false)))
    $martFlag = if ($CoreOnly) { 'no' } else { 'yes' }
    # SET w tej samej sesji; walidacja po kazdym kroku zatrzymuje dalsza prace.
    Execute $psql @('-X','-w','-v','ON_ERROR_STOP=1','-h',$pgHost,'-p',$pgPort,'-U',$pgUser,'-d',$databaseName,
        '-c',"SET hotelgroup.check_mart = '$martFlag';",'-f',$tempVerify) 'Weryfikacja koncowa staging/core/mart'

    Write-Host "`nGOTOWE: $databaseName. Tryb: $(if ($CoreOnly) {'staging + core'} else {'staging + core + mart'})." -ForegroundColor Green
    Write-Host 'UWAGA: Instalator nie zasila automatycznie FactRoomNight i FactRoomInventory (US-03-05A/B). Skrypty znajduja sie w repozytorium i wymagaja osobnego uruchomienia.' -ForegroundColor Yellow

}
catch {
    Write-Host "`nBLAD: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host 'Skrypt przerwal prace. Nie uruchamiaj nastepnych etapow bez zdiagnozowania bledu.' -ForegroundColor Yellow
    exit 1
}
finally {
    if ($tempSql -and (Test-Path -LiteralPath $tempSql)) { Remove-Item -LiteralPath $tempSql -Force }
    if ($tempVerify -and (Test-Path -LiteralPath $tempVerify)) { Remove-Item -LiteralPath $tempVerify -Force }
    [Environment]::SetEnvironmentVariable('PGPASSWORD', $originalPassword, 'Process')
    [Environment]::SetEnvironmentVariable('PGCLIENTENCODING', $originalEncoding, 'Process')
    [Environment]::SetEnvironmentVariable('PYTHONUTF8', $originalPythonUtf8, 'Process')
    [Environment]::SetEnvironmentVariable('PYTHONIOENCODING', $originalPythonIo, 'Process')
    foreach ($key in $originalPgSettings.Keys) {
        [Environment]::SetEnvironmentVariable($key, $originalPgSettings[$key], 'Process')
    }
    Set-Location -LiteralPath $originalLocation
}

