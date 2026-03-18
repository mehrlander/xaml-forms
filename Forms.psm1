Add-Type -AssemblyName PresentationFramework, WindowsBase, PresentationCore

Import-Module XML -Force

$Script:ThemePath = Join-Path $PSScriptRoot 'Theme.xaml'
$Script:ThemeDict = if (Test-Path $Script:ThemePath) {
    [Windows.Markup.XamlReader]::Parse((Get-Content $Script:ThemePath -Raw))
}

$writeLevel = 0
$timers = @{}

function Write-Nice {
    param(
        [string]$Message,
        [string]$Type = '',
        [int]$Level = 1,
        [switch]$NoNewLine,
        [switch]$PassThruLength
    )

    $f = @{ info='White','  •'; section='Cyan','>>>'; success='Green','  ✓'; warning='Yellow','  !'; error='Red','  X' }
    $color, $glyph = if ($f[$Type]) { $f[$Type] } else { 'White','' }

    $ts   = Get-Date -Format 'HH:mm:ss'
    $text = (' ' * (($writeLevel + $Level) * 2)) + $glyph + ' ' + $Message

    Write-Host "$ts " -NoNewline -ForegroundColor DarkGray
    $splat = @{ Object = $text; ForegroundColor = $color }
    if ($NoNewLine) { $splat.NoNewline = $true }
    Write-Host @splat

    if ($PassThruLength) { return ($ts.Length + 1 + $text.Length) }
}

function Write-Section($Name) { 
    Write-Nice "Starting $Name" -Type section
    $timers[$Name] = [System.Diagnostics.Stopwatch]::StartNew() 
}
function Write-SectionEnd($Name) { 
    if ($t = $timers[$Name]) { 
        $t.Stop()
        Write-Nice "Finished $Name ($($t.Elapsed.TotalSeconds.ToString('0.000'))s)" -Type section
        $timers.Remove($Name) 
    } 
}

function New-XamlTemplate {
    param(
        [Parameter(Mandatory=$true)][string]$TagName, 
        [Parameter(Mandatory=$true)][string]$Content, 
        [Parameter()][hashtable]$Attributes = @{}
    )
    
    $attrString = ""
    foreach ($key in $Attributes.Keys) {
        $value = $Attributes[$key] -replace '"', '&quot;'
        $attrString += "`n        $key=`"$value`""
    }
    
    return @"
<$TagName xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"$attrString>
    $Content
</$TagName>
"@
}

function New-ViewModel {
    param([hashtable]$Data, [string]$ClassName = "ViewModel_$([DateTime]::Now.Ticks)")
    
    $props = foreach ($key in $Data.Keys) {
        $fieldName = "_$($key.ToLower())"
        $type = switch ($Data[$key].GetType().Name) {
            'Int32' { 'int' }; 'Boolean' { 'bool' }; 'String' { 'string' }
            default { 'object' }
        }
        @"
    private $type $fieldName;
    public $type $key { 
        get { return $fieldName; } 
        set { if ($fieldName != value) { $fieldName = value; OnPropertyChanged("$key"); } } 
    }
"@
    }
    
    Add-Type @"
using System;
using System.ComponentModel;
public class $ClassName : INotifyPropertyChanged {
$($props -join "`n")
    public event PropertyChangedEventHandler PropertyChanged;
    protected void OnPropertyChanged(string name) {
        if (PropertyChanged != null) PropertyChanged(this, new PropertyChangedEventArgs(name));
    }
}
"@
    
    $vm = New-Object $ClassName
    $Data.Keys | ForEach-Object { $vm.$_ = $Data[$_] }
    return $vm
}

function New-Wpf {
    param(
        [Parameter(Mandatory=$true)][string]$XamlContent,
        [Parameter()][string]$WrapAs,
        [Parameter()][hashtable]$Attributes = @{},
        [Parameter()][object]$DataContext,
        [Parameter()][switch]$IsComponent
    )
    
    if (-not $IsComponent) {
        Write-Section 'New-Wpf'
    }
    
    try {
        if ($WrapAs -or $Attributes.Count -gt 0) {
            if (-not $WrapAs -and $Attributes.Count -gt 0) {
                $WrapAs = "Window"
                Write-Nice "Attributes provided without WrapAs - defaulting to Window wrapper" -Type info
            }
            
            $XamlContent = New-XamlTemplate -TagName $WrapAs -Content $XamlContent -Attributes $Attributes
            Write-Nice "Wrapped content in <$WrapAs> with namespaces" -Type info
        } else {
            Write-Nice "Loading XAML as-is (no wrapping)" -Type info
        }
        
        [xml]$refreshedXml = $XamlContent
        $reader = New-Object System.Xml.XmlNodeReader $refreshedXml
        $xamlObject = [Windows.Markup.XamlReader]::Load($reader)

        if ($Script:ThemeDict -and $xamlObject -is [System.Windows.Window]) {
            $xamlObject.Resources.MergedDictionaries.Add($Script:ThemeDict)
            Write-Nice 'Merged module theme dictionary' -Type info
        }
        
        Write-Nice "XAML loaded successfully as [$($xamlObject.GetType().Name)]" -Type success
        
        $wrapper = [PSCustomObject]@{
            Element = $xamlObject
            Window = $null
            Tag = @{}
            FormResult = $null
            DataContext = $DataContext
            Components = @{}
        }
        
        if ($xamlObject -is [System.Windows.Window]) {
            $wrapper.Window = $xamlObject
            if ($DataContext) {
                $xamlObject.DataContext = $DataContext
            }
        }
        
        $wrapper | Add-Member -MemberType ScriptMethod -Name Return -Value {
            param($Result = $this.FormResult)
            $this.FormResult = $Result
            if ($this.Window) { $this.Window.Close() }
        } -Force
        
        $wrapper | Add-Member -MemberType ScriptMethod -Name SetDataContext -Value {
            param($DataContext)
            $this.DataContext = $DataContext
            if ($this.Window) {
                $this.Window.DataContext = $DataContext
            } elseif ($this.Element -and $this.Element.DataContext -ne $null) {
                $this.Element.DataContext = $DataContext
            }
            Write-Nice "Updated DataContext to [$($DataContext.GetType().Name)]" -Type info -Level 2
        } -Force
        
        $wrapper | Add-Member -MemberType ScriptMethod -Name CreateVariables -Value {
            $properties = $this.PSObject.Properties | Where-Object { 
                $_.Name -notin @('Element', 'Window', 'Tag', 'FormResult', 'DataContext', 'Components') -and 
                $_.Value -ne $null
            }
            
            foreach ($prop in $properties) {
                Set-Variable -Name $prop.Name -Value $prop.Value -Scope Global
                Write-Nice "Created global variable `$$($prop.Name)" -Type info -Level 2
            }
            
            if ($this.Window -and ($windowName = $this.Element.Name)) {
                Set-Variable -Name $windowName -Value $this.Window -Scope Global
                Write-Nice "Created global variable `$$windowName for window" -Type info -Level 2
            }
        } -Force

        $wrapper | Add-Member -MemberType ScriptMethod -Name On -Value {
            param(
                [Parameter(Mandatory=$true)][string]$ControlName,
                [Parameter(Mandatory=$true)][string]$EventName,
                [Parameter(Mandatory=$true)][ScriptBlock]$Action,
                [Parameter()][ScriptBlock]$CanExecute = { $true }
            )
    
            $control = $this.$ControlName
            if (-not $control) {
                throw "Control '$ControlName' not found on wrapper"
            }
    
            $wrapper = $this
    
            $handler = {
                param($sender, $e)
        
                if (-not (& $CanExecute $sender $e $wrapper)) { return }
        
                & $Action $sender $e $wrapper
            }.GetNewClosure()
    
            $addMethod = "Add_$EventName"
            $control.$addMethod($handler)
        } -Force

        $Wrapper | Add-Member ScriptMethod SetTimeout {
            param([scriptblock]$Action, [int]$DelaySeconds = 1)

            $wrapper = $this
            $timer   = New-Object Windows.Threading.DispatcherTimer
            $timer.Interval = [TimeSpan]::FromSeconds($DelaySeconds)
            $timer.Add_Tick({
                & $Action $wrapper
                $timer.Stop()
            }.GetNewClosure())
            $timer.Start()
        } -Force

        $Wrapper | Add-Member ScriptMethod Defer {
            param([scriptblock]$Action)
            $this.SetTimeout($Action, 0)
        } -Force

        $Wrapper | Add-Member ScriptMethod CopyToClipboard {
            param([string]$Text, [string]$ControlName, [string]$SuccessMessage = '✓ Copied', [int]$ResetSeconds = 1)
            $w = $this
            $control = $w.$ControlName
            $original = $control.Content
            $control.Content = $SuccessMessage
            # SetText blocks ~1s in WebBrowser context; defer so WPF paints first
            $w.Defer({
                try { [Windows.Clipboard]::SetText($Text) } catch {}
                $w.SetTimeout({ param($w) $w.$ControlName.Content = $original }, $ResetSeconds)
            }.GetNewClosure())
        } -Force
        
        $wrapper | Add-Member -MemberType ScriptMethod -Name AddComponent -Value {
            param(
                [Parameter(Mandatory=$true)][string]$ComponentName,
                [Parameter(Mandatory=$true)][string]$ParentPanelName,
                [Parameter()][hashtable]$ControllerParameters = @{},
                [Parameter()][object]$DataContext
            )
    
            Write-Nice "Adding component: $ComponentName to $ParentPanelName" -Type info -Level 2
    
            $panel = $this.$ParentPanelName
            if (-not $panel) {
                throw "Panel '$ParentPanelName' not found on wrapper"
            }
    
            $componentDir = if ($this.PSObject.Properties['FormDirectory']) { 
                $this.FormDirectory 
            } else { 
                throw "FormDirectory not set. Components can only be loaded from Import-Form context."
            }
    
            $xamlPath = Join-Path $componentDir "$ComponentName.xaml"
            $controllerPath = Join-Path $componentDir "$ComponentName.ps1"
    
            if (-not (Test-Path $xamlPath)) {
                throw "Component XAML not found: $xamlPath"
            }
    
            $xamlContent = Get-Content -Path $xamlPath -Raw
            Write-Nice "Loading component XAML: $ComponentName.xaml" -Type info -Level 3
    
            $oldWriteLevel = $writeLevel
            $writeLevel = 3
            $componentWrapper = New-Wpf -XamlContent $xamlContent -DataContext $DataContext -IsComponent
            $writeLevel = $oldWriteLevel
    
            $componentWrapper | Add-Member -NotePropertyName FormDirectory -NotePropertyValue $componentDir -Force
    
            if (Test-Path $controllerPath) {
                Write-Nice "Loading component controller: $ComponentName.ps1" -Type info -Level 3
        
                $controllerParams = @{ 'Wrapper' = $componentWrapper }
                if ($ControllerParameters.Count -gt 0) {
                    $controllerParams += $ControllerParameters
                }
        
                & $controllerPath @controllerParams
                Write-Nice "Component controller loaded successfully" -Type success -Level 3
            } else {
                Write-Nice "No controller found for component: $ComponentName" -Type info -Level 3
            }
    
            $panel.Children.Add($componentWrapper.Element) | Out-Null
            Write-Nice "Attached component to $ParentPanelName" -Type success -Level 3
    
            Write-Nice "Component '$ComponentName' added successfully" -Type success -Level 2
            return $componentWrapper
        } -Force
        
        if ($DataContext) {
            Write-Nice "Set DataContext to [$($DataContext.GetType().Name)]" -Type info
        }
        
        Write-Nice "Finding named controls" -Type info
        
        $ok = 0
        $ignore = 0
        $fail = 0

        $namedElements = Get-XmlNamedElements $refreshedXml
        
        foreach ($elem in $namedElements) {
            $control = $xamlObject.FindName($elem.Name)
            
            if ($control) {
                $wrapper | Add-Member -NotePropertyName $elem.Name -NotePropertyValue $control -Force
                $prefixLen = Write-Nice "[$($control.GetType().Name)] $($elem.Name)" -Type success -Level 2 -NoNewLine -PassThruLength
                $ok++
            }
            elseif ($elem.IsTemplateScoped) {
                $prefixLen = Write-Nice "Ignored [$($elem.Type)] '$($elem.Name)' (template)" -Type info -Level 2 -NoNewLine -PassThruLength
                $ignore++
            }
            else {
                $prefixLen = Write-Nice "Control [$($elem.Type)] '$($elem.Name)' not found" -Type warning -Level 2 -NoNewLine -PassThruLength
                $fail++
            }

            $padWidth = [Math]::Max(1, 55 - $prefixLen)
            $pad      = ' ' * $padWidth
            Write-Host ($pad + $elem.Path)
        }

        Write-Nice "Added $ok control properties to wrapper" -Type info
        if ($ignore) { Write-Nice "Ignored $ignore template-scoped names" -Type info }
        if ($fail)   { Write-Nice "Failed to find $fail controls" -Type warning }

        if (-not $IsComponent) {
            Write-SectionEnd 'New-Wpf'
        }
        return $wrapper
    }
    catch {
        Write-Nice "Failed to load XAML: $_" -Type error
        if (-not $IsComponent) {
            Write-SectionEnd 'New-Wpf'
        }
        throw
    }
}

function Import-Form {
    param(
        [Parameter(Mandatory=$true,Position=0)][string]$FormName,
        [Parameter()][string]$FromPath,
        [Parameter()][hashtable]$ControllerParameters = @{},
        [Parameter()][object]$DataContext
    )
    
    Write-Section 'Import-Form'
    
    try {
        if ($FromPath) {
            if (-not (Test-Path $FromPath -PathType Container)) {
                throw "Specified path does not exist or is not a directory: $FromPath"
            }
            
            $xamlDir = (Resolve-Path $FromPath).Path
            Write-Nice "Loading from specified path: $xamlDir" -Type info
            
        } else {
            $formsBase = Join-Path (Split-Path $PROFILE) "Forms"
            $xamlDir = Join-Path $formsBase $FormName
            
            if (-not (Test-Path $xamlDir -PathType Container)) {
                throw "Form folder not found: $xamlDir`nEnsure the form exists in the WindowsPowerShell\Forms directory"
            }
            
            Write-Nice "Loading form: $xamlDir" -Type info
        }
        
        $xamlPath = Join-Path $xamlDir "$FormName.xaml"
        
        if (-not (Test-Path $xamlPath)) {
            throw "XAML file not found: $xamlPath"
        }
        
        $xamlContent = Get-Content -Path $xamlPath -Raw
        Write-Nice "Loading XAML: $FormName.xaml" -Type info
        
        $writeLevel = 1
        Write-Host "════════"
        $wrapper = New-Wpf -XamlContent $xamlContent -DataContext $DataContext
        $writeLevel = 0
        Write-Host "════════"

        $wrapper | Add-Member -NotePropertyName FormDirectory -NotePropertyValue $xamlDir -Force
        
        $controls = $wrapper.PSObject.Properties.Name | Where-Object { 
            $_ -notin 'Element','Window','Tag','FormResult','DataContext','Components','FormDirectory'
        }
        Write-Nice "Created WpfWrapper" -Type success

        if ($wrapper.Window) {
            $wrapper.Window.Add_PreviewKeyDown({
                param($sender, $e)
                if ($e.Key -eq 'F12') {
                    Start-Process explorer.exe $xamlDir
                    $e.Handled = $true
                }
            }.GetNewClosure())
            Write-Nice "Added F12 to open form directory" -Type success
        }
        
        if ($ControllerParameters.Count -gt 0) {
            Write-Nice "Controller parameters provided: $($ControllerParameters.Keys -join ', ')" -Type info
        }
        
        $controllerPath = Join-Path $xamlDir "$FormName.ps1"
        
        if (Test-Path $controllerPath) {
            Write-Host "════════"
            $writeLevel = 1
            Write-Section "$FormName.ps1"

            $controllerParams = @{ Wrapper = $wrapper } + $ControllerParameters
            & $controllerPath @controllerParams

            Write-SectionEnd "$FormName.ps1"
            $writeLevel = 0
            Write-Host "════════"
        } else {
            Write-Nice "No controller found at: $controllerPath" -Type warning
        }
        
        Write-SectionEnd 'Import-Form'
        return $wrapper
    }
    catch {
        Write-Nice "Failed to load form: $_" -Type error
        Write-SectionEnd 'Import-Form'
        throw
    }
}

function Show-Form {
    param(
        [Parameter(Mandatory=$true, Position=0, ValueFromPipeline=$true)]$WindowOrWrapper,
        [Parameter(Mandatory=$false)][switch]$HideConsole,
        [Parameter(Mandatory=$false)][switch]$PassThru
    )
    
    Write-Section "Show-Form"
    $window = if ($WindowOrWrapper.Window) { $WindowOrWrapper.Window } elseif ($WindowOrWrapper -is [System.Windows.Window]) { $WindowOrWrapper } else { $null }
    
    if (-not $window) {
        throw "Input must be a Window or a wrapper object with a Window property"
    }
    
    try {
        if ($psISE) {
            Write-Nice "Launching from PowerShell ISE" -Type info
            $result = $window.Dispatcher.InvokeAsync{ $window.ShowDialog() }.Wait()
            Write-SectionEnd "Show-Form"
        } else {
            Write-Nice "Launching from PowerShell console" -Type info
            
            if ($HideConsole) {
                Add-Type '[DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr hWnd,int nCmdShow);' -Name Win32 -Namespace P -PassThru | Out-Null
                [P.Win32]::ShowWindowAsync((Get-Process -Id $pid).MainWindowHandle, 0) | Out-Null
            }
            
            $app = New-Object Windows.Application
            $result = $app.Run($window)
            Write-SectionEnd "Show-Form"
        }
    }
    catch {
        Write-Error "Failed to show window: $_"
        Write-SectionEnd "Show-Form"
    }
    
    if ($PassThru) {
        return $WindowOrWrapper
    }
}

function Show-FormResource {
    [CmdletBinding()]
    param([Parameter(Mandatory, Position=0)] [string]$FormName)
    
    try {
        Import-Module Forms -Force
        $form = Get-Resource -Type Form -Name $FormName
        if (-not $form) {
            Write-Warning "Form '$FormName' not found"
            return
        }
        
        Write-Host ""
        Write-Host "Launching form: $FormName" -ForegroundColor Cyan
        Write-Host "  Controller: $(if ($form.Details.HasController) {'Found'} else {'Not found'})" -ForegroundColor $(if ($form.Details.HasController) {'Green'} else {'Yellow'})
        Write-Host "  Files: $($form.FileCount)`n" -ForegroundColor Gray
        
        Import-Form $FormName | Show-Form
    } catch {
        Write-Host "Failed to launch form: $_" -ForegroundColor Red
    }
}
Set-Alias launch Show-FormResource

Export-ModuleMember -Function * -Alias *