# Klikne na tlacitko nahravani v Meetily - analogie click_meetily_record.applescript.
# POZOR: nejnejistejsi cast celeho portu. Mac verze hleda tlacitko podle
# velikosti (~48x48 px, jedine tlacitko teto velikosti v okne). Tenhle skript
# pouziva stejnou heuristiku pres Windows UI Automation (misto AppleScript
# System Events), ale skutecna velikost/struktura na Windows buildu appky
# NENI OVERENA - je potreba doladit na realnem Windows stroji (spustit,
# zkontrolovat, jestli $target neco najde, pripadne rozsah velikosti upravit).
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

$proc = Get-Process -Name "meetily" -ErrorAction SilentlyContinue
if (-not $proc) {
    Start-Process "meetily" -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    $proc = Get-Process -Name "meetily" -ErrorAction SilentlyContinue
}
if (-not $proc) {
    Write-Host "Meetily se nepodarilo otevrit."
    exit 1
}

Start-Sleep -Seconds 1

$root = [System.Windows.Automation.AutomationElement]::RootElement
$windowCondition = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ProcessIdProperty, $proc.Id)
$window = $root.FindFirst([System.Windows.Automation.TreeScope]::Children, $windowCondition)

if (-not $window) {
    Write-Host "Nenasel jsem okno Meetily."
    exit 1
}

$buttonCondition = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
    [System.Windows.Automation.ControlType]::Button)
$buttons = $window.FindAll([System.Windows.Automation.TreeScope]::Descendants, $buttonCondition)

$target = $null
foreach ($btn in $buttons) {
    $rect = $btn.Current.BoundingRectangle
    if ($rect.Width -gt 44 -and $rect.Width -lt 54 -and $rect.Height -gt 44 -and $rect.Height -lt 54) {
        $target = $btn
        break
    }
}

if (-not $target) {
    Write-Host "Nenasel jsem tlacitko nahravani - spust ho prosim rucne."
    exit 1
}

$invokePattern = $target.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
$invokePattern.Invoke()
