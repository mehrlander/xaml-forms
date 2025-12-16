#Requires -Version 5.1
<#
.SYNOPSIS
    WPF Bill Tracking Dashboard for Washington State Legislature
.DESCRIPTION
    Tracks legislative bills with annotations for budget analysis work.
    Integrates with Leg.psm1 module for bill import and management.
#>

[CmdletBinding()]
param()

#region Assembly Loading
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
#endregion

#region Module Import
$LegModulePath = Join-Path $PSScriptRoot "Leg.psm1"
if (Test-Path $LegModulePath) {
    Import-Module $LegModulePath -Force
} else {
    Write-Warning "Leg.psm1 not found at: $LegModulePath"
    Write-Warning "Some features will not work without the Leg module."
}
#endregion

#region Annotation Management
$script:AnnotationPath = Join-Path $env:USERPROFILE "OneDrive\Documents\WindowsPowerShell\Leg\Annotations.json"
$script:Annotations = @{}

function Load-Annotations {
    if (Test-Path $script:AnnotationPath) {
        try {
            $json = Get-Content $script:AnnotationPath -Raw | ConvertFrom-Json
            $script:Annotations = @{}
            # Convert PSCustomObject to hashtable
            $json.PSObject.Properties | ForEach-Object {
                $script:Annotations[$_.Name] = $_.Value
            }
            Write-Verbose "Loaded annotations from $script:AnnotationPath"
        } catch {
            Write-Warning "Failed to load annotations: $_"
            $script:Annotations = @{}
        }
    } else {
        $script:Annotations = @{}
        Write-Verbose "No existing annotations file found"
    }
}

function Save-Annotations {
    try {
        $annotationDir = Split-Path $script:AnnotationPath -Parent
        if (-not (Test-Path $annotationDir)) {
            New-Item -Path $annotationDir -ItemType Directory -Force | Out-Null
        }

        $script:Annotations | ConvertTo-Json -Depth 10 | Set-Content $script:AnnotationPath -Force
        Write-Verbose "Saved annotations to $script:AnnotationPath"
    } catch {
        Write-Warning "Failed to save annotations: $_"
    }
}

function Get-BillAnnotation {
    param([string]$BillKey)

    if ($script:Annotations.ContainsKey($BillKey)) {
        return $script:Annotations[$BillKey]
    }

    # Return default annotation
    return [PSCustomObject]@{
        affectsDRS = $false
        fiscalNote = "None"
        notes = ""
        tags = @()
        reviewed = $null
    }
}

function Set-BillAnnotation {
    param(
        [string]$BillKey,
        [PSCustomObject]$Annotation
    )

    $script:Annotations[$BillKey] = $Annotation
    Save-Annotations
}

function Get-BillKey {
    param($Bill)
    # Create unique key: Biennium/BillType/Name
    $billType = $Bill.BillType -replace '\s', '_'
    return "$($Bill.Biennium)/$billType/$($Bill.Name)"
}
#endregion

#region XAML Definition
[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="WA Legislative Bill Tracking Dashboard"
        Width="1200" Height="800"
        WindowStartupLocation="CenterScreen">
    <Window.Resources>
        <Style TargetType="Button">
            <Setter Property="Padding" Value="8,4"/>
            <Setter Property="Margin" Value="4,2"/>
            <Setter Property="MinWidth" Value="80"/>
        </Style>
        <Style TargetType="TextBlock">
            <Setter Property="VerticalAlignment" Value="Center"/>
            <Setter Property="Margin" Value="4,2"/>
        </Style>
        <Style TargetType="TextBox">
            <Setter Property="Padding" Value="4"/>
            <Setter Property="Margin" Value="4,2"/>
        </Style>
        <Style TargetType="CheckBox">
            <Setter Property="VerticalAlignment" Value="Center"/>
            <Setter Property="Margin" Value="4,2"/>
        </Style>
        <Style TargetType="ComboBox">
            <Setter Property="Padding" Value="4"/>
            <Setter Property="Margin" Value="4,2"/>
            <Setter Property="MinWidth" Value="120"/>
        </Style>
    </Window.Resources>

    <DockPanel Margin="8">
        <!-- Top Toolbar -->
        <DockPanel DockPanel.Dock="Top" Margin="0,0,0,8">
            <StackPanel Orientation="Horizontal" DockPanel.Dock="Left">
                <Button Name="btnRefresh" Content="Refresh"/>
                <Button Name="btnImport" Content="Import New"/>
                <TextBlock Text="Status:" Margin="12,2,2,2"/>
                <TextBlock Name="txtStatus" Text="Ready" Foreground="Green" FontWeight="Bold"/>
            </StackPanel>

            <StackPanel Orientation="Horizontal" DockPanel.Dock="Right" HorizontalAlignment="Right">
                <TextBlock Text="Bill Type:"/>
                <ComboBox Name="cmbBillType" Width="150"/>
                <TextBlock Text="Chamber:"/>
                <ComboBox Name="cmbChamber" Width="100"/>
                <TextBlock Text="Filter:"/>
                <TextBox Name="txtFilter" Width="200"/>
                <Button Name="btnClearFilter" Content="Clear"/>
            </StackPanel>
        </DockPanel>

        <!-- Bottom Detail Panel -->
        <Grid DockPanel.Dock="Bottom" Margin="0,8,0,0" Height="250">
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
                <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>

            <!-- Selected Bill Header -->
            <TextBlock Grid.Row="0" Name="txtSelectedBill"
                      FontWeight="Bold" FontSize="14"
                      Text="No bill selected" Margin="0,0,0,8"/>

            <!-- Annotation Controls Row 1 -->
            <Grid Grid.Row="1">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>

                <CheckBox Grid.Column="0" Name="chkAffectsDRS"
                         Content="Affects DRS" FontWeight="Bold"/>

                <StackPanel Grid.Column="2" Orientation="Horizontal" HorizontalAlignment="Right">
                    <TextBlock Text="Fiscal Note:"/>
                    <ComboBox Name="cmbFiscalNote" Width="150">
                        <ComboBoxItem Content="None" IsSelected="True"/>
                        <ComboBoxItem Content="Requested"/>
                        <ComboBoxItem Content="Received"/>
                        <ComboBoxItem Content="Reviewed"/>
                        <ComboBoxItem Content="Not Required"/>
                    </ComboBox>
                </StackPanel>
            </Grid>

            <!-- Tags Row -->
            <DockPanel Grid.Row="2" Margin="0,4">
                <TextBlock DockPanel.Dock="Left" Text="Tags:" Width="50"/>
                <Button Name="btnAddTag" DockPanel.Dock="Right" Content="+ Add Tag" Width="80"/>
                <TextBox Name="txtTags" IsReadOnly="True" Background="WhiteSmoke"/>
            </DockPanel>

            <!-- Notes -->
            <DockPanel Grid.Row="3" Margin="0,4">
                <TextBlock DockPanel.Dock="Top" Text="Notes:" Margin="0,0,0,4"/>
                <TextBox Name="txtNotes"
                        TextWrapping="Wrap"
                        AcceptsReturn="True"
                        VerticalScrollBarVisibility="Auto"/>
            </DockPanel>

            <!-- Bill Details -->
            <DockPanel Grid.Row="4" Margin="0,4,0,0">
                <TextBlock DockPanel.Dock="Top" Text="RCW Links / Details:"
                          FontWeight="Bold" Margin="0,0,0,4"/>
                <TextBlock Name="txtBillDetails"
                          TextWrapping="Wrap"
                          Background="WhiteSmoke"
                          Padding="4"/>
            </DockPanel>
        </Grid>

        <!-- Main DataGrid -->
        <DataGrid Name="dgBills"
                 AutoGenerateColumns="False"
                 IsReadOnly="True"
                 SelectionMode="Single"
                 CanUserResizeColumns="True"
                 CanUserSortColumns="True"
                 GridLinesVisibility="Horizontal"
                 AlternatingRowBackground="WhiteSmoke"
                 Margin="0,8">
            <DataGrid.Columns>
                <DataGridTextColumn Header="Bill #" Binding="{Binding BillNum}" Width="80"/>
                <DataGridTextColumn Header="Title" Binding="{Binding ShortTitle}" Width="*"/>
                <DataGridTextColumn Header="Chamber" Binding="{Binding Chamber}" Width="80"/>
                <DataGridTextColumn Header="Type" Binding="{Binding BillType}" Width="120"/>
                <DataGridCheckBoxColumn Header="DRS" Binding="{Binding AffectsDRS}" Width="50"/>
                <DataGridTextColumn Header="Fiscal" Binding="{Binding FiscalNote}" Width="90"/>
                <DataGridTextColumn Header="Modified" Binding="{Binding LastModified}" Width="100"/>
                <DataGridTextColumn Header="Notes" Binding="{Binding NotesPreview}" Width="150"/>
            </DataGrid.Columns>
        </DataGrid>
    </DockPanel>
</Window>
'@
#endregion

#region Window Initialization
$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)

# Element discovery
$WPF = @{}
$xaml.SelectNodes("//*[@*[local-name()='Name']]") | ForEach-Object {
    $name = $_.Attributes['Name'].Value
    if ($null -eq $name) {
        $name = $_.Attributes['x:Name'].Value
    }
    if ($null -ne $name) {
        $WPF[$name] = $window.FindName($name)
    }
}
#endregion

#region Data Management
$script:AllBills = @()
$script:CurrentBiennium = "2025-26"

function Load-Bills {
    param([string]$Biennium = $script:CurrentBiennium)

    $WPF.txtStatus.Text = "Loading bills..."
    $WPF.txtStatus.Foreground = "Orange"

    try {
        # Get all bills from local store
        $bills = @()

        if (Get-Command Get-Bill -ErrorAction SilentlyContinue) {
            # Get bill types
            $billTypes = @("House Bills", "Senate Bills", "Session Laws")

            foreach ($billType in $billTypes) {
                Write-Verbose "Loading $billType..."
                $typeBills = Get-Bill -Biennium $Biennium | Where-Object {
                    $_.BillType -eq $billType
                }

                if ($null -ne $typeBills) {
                    $bills += $typeBills
                }
            }
        } else {
            Write-Warning "Get-Bill command not available"
        }

        # Enrich with annotations and metadata
        $script:AllBills = $bills | ForEach-Object {
            $bill = $_
            $billKey = Get-BillKey -Bill $bill
            $annotation = Get-BillAnnotation -BillKey $billKey

            # Extract bill number and chamber from name
            if ($bill.Name -match '^(\d+)') {
                $billNum = $matches[1]
            } else {
                $billNum = $bill.Name
            }

            $chamber = "Unknown"
            if ($bill.BillType -match 'House') {
                $chamber = "House"
                $billNum = "HB $billNum"
            } elseif ($bill.BillType -match 'Senate') {
                $chamber = "Senate"
                $billNum = "SB $billNum"
            } elseif ($bill.BillType -match 'Session Law') {
                $chamber = "Law"
                $billNum = "SL $billNum"
            }

            # Try to get title from XML if available
            $shortTitle = $bill.Name
            if (Get-Command Get-BillXml -ErrorAction SilentlyContinue) {
                try {
                    $xmlPath = $bill.Path -replace '\.htm\.gz$', '.xml.gz'
                    if (Test-Path $xmlPath) {
                        $billXml = Get-BillXml -Path $xmlPath -ErrorAction SilentlyContinue
                        if ($null -ne $billXml -and $billXml.Title) {
                            $shortTitle = $billXml.Title
                        }
                    }
                } catch {
                    # Silently continue if XML parsing fails
                }
            }

            # Format modified date
            $modifiedStr = ""
            if ($null -ne $bill.Modified) {
                $modifiedStr = $bill.Modified.ToString("yyyy-MM-dd")
            }

            # Notes preview (first 50 chars)
            $notesPreview = ""
            if ($null -ne $annotation.notes -and $annotation.notes.Length -gt 0) {
                $notesPreview = $annotation.notes.Substring(0, [Math]::Min(50, $annotation.notes.Length))
                if ($annotation.notes.Length -gt 50) {
                    $notesPreview += "..."
                }
            }

            [PSCustomObject]@{
                BillNum = $billNum
                ShortTitle = $shortTitle
                Chamber = $chamber
                BillType = $bill.BillType
                AffectsDRS = $annotation.affectsDRS
                FiscalNote = $annotation.fiscalNote
                LastModified = $modifiedStr
                NotesPreview = $notesPreview
                FullBill = $bill
                Annotation = $annotation
                BillKey = $billKey
            }
        }

        $WPF.txtStatus.Text = "Loaded $($script:AllBills.Count) bills"
        $WPF.txtStatus.Foreground = "Green"

        Update-BillGrid

    } catch {
        $WPF.txtStatus.Text = "Error loading bills"
        $WPF.txtStatus.Foreground = "Red"
        Write-Warning "Error loading bills: $_"
    }
}

function Update-BillGrid {
    # Apply filters
    $filtered = $script:AllBills

    # Bill Type filter
    $selectedType = $WPF.cmbBillType.SelectedItem
    if ($null -ne $selectedType -and $selectedType.Content -ne "All") {
        $filtered = $filtered | Where-Object { $_.BillType -eq $selectedType.Content }
    }

    # Chamber filter
    $selectedChamber = $WPF.cmbChamber.SelectedItem
    if ($null -ne $selectedChamber -and $selectedChamber.Content -ne "All") {
        $filtered = $filtered | Where-Object { $_.Chamber -eq $selectedChamber.Content }
    }

    # Text filter
    $filterText = $WPF.txtFilter.Text
    if (-not [string]::IsNullOrWhiteSpace($filterText)) {
        $filtered = $filtered | Where-Object {
            $_.BillNum -like "*$filterText*" -or
            $_.ShortTitle -like "*$filterText*" -or
            $_.NotesPreview -like "*$filterText*"
        }
    }

    # Update grid
    $WPF.dgBills.ItemsSource = $filtered
}

function Update-AnnotationPanel {
    param($SelectedItem)

    if ($null -eq $SelectedItem) {
        $WPF.txtSelectedBill.Text = "No bill selected"
        $WPF.chkAffectsDRS.IsChecked = $false
        $WPF.cmbFiscalNote.SelectedIndex = 0
        $WPF.txtTags.Text = ""
        $WPF.txtNotes.Text = ""
        $WPF.txtBillDetails.Text = ""

        # Disable controls
        $WPF.chkAffectsDRS.IsEnabled = $false
        $WPF.cmbFiscalNote.IsEnabled = $false
        $WPF.txtNotes.IsEnabled = $false
        $WPF.btnAddTag.IsEnabled = $false
        return
    }

    # Enable controls
    $WPF.chkAffectsDRS.IsEnabled = $true
    $WPF.cmbFiscalNote.IsEnabled = $true
    $WPF.txtNotes.IsEnabled = $true
    $WPF.btnAddTag.IsEnabled = $true

    # Update header
    $WPF.txtSelectedBill.Text = "Selected: $($SelectedItem.BillNum) - $($SelectedItem.ShortTitle)"

    # Load annotation
    $annotation = $SelectedItem.Annotation
    $WPF.chkAffectsDRS.IsChecked = $annotation.affectsDRS

    # Set fiscal note dropdown
    $fiscalIdx = 0
    switch ($annotation.fiscalNote) {
        "None" { $fiscalIdx = 0 }
        "Requested" { $fiscalIdx = 1 }
        "Received" { $fiscalIdx = 2 }
        "Reviewed" { $fiscalIdx = 3 }
        "Not Required" { $fiscalIdx = 4 }
    }
    $WPF.cmbFiscalNote.SelectedIndex = $fiscalIdx

    # Tags
    if ($null -ne $annotation.tags -and $annotation.tags.Count -gt 0) {
        $WPF.txtTags.Text = $annotation.tags -join ", "
    } else {
        $WPF.txtTags.Text = ""
    }

    # Notes
    $WPF.txtNotes.Text = $annotation.notes

    # Bill details - try to get RCW links
    $details = ""
    try {
        if (Get-Command Get-BillHtm -ErrorAction SilentlyContinue) {
            $htmPath = $SelectedItem.FullBill.Path
            if (Test-Path $htmPath) {
                $billHtm = Get-BillHtm -Path $htmPath -ErrorAction SilentlyContinue
                if ($null -ne $billHtm -and $null -ne $billHtm.RcwLinks -and $billHtm.RcwLinks.Count -gt 0) {
                    $details = "RCW Links: " + ($billHtm.RcwLinks -join ", ")
                }
            }
        }
    } catch {
        # Silently continue
    }

    if ([string]::IsNullOrWhiteSpace($details)) {
        $details = "File: $($SelectedItem.FullBill.Path)"
    }

    $WPF.txtBillDetails.Text = $details
}

function Save-CurrentAnnotation {
    $selected = $WPF.dgBills.SelectedItem
    if ($null -eq $selected) { return }

    # Build annotation object
    $tags = @()
    if (-not [string]::IsNullOrWhiteSpace($WPF.txtTags.Text)) {
        $tags = $WPF.txtTags.Text -split ',' | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    }

    $fiscalNote = $WPF.cmbFiscalNote.SelectedItem.Content

    $annotation = [PSCustomObject]@{
        affectsDRS = $WPF.chkAffectsDRS.IsChecked
        fiscalNote = $fiscalNote
        notes = $WPF.txtNotes.Text
        tags = $tags
        reviewed = (Get-Date).ToString("yyyy-MM-dd")
    }

    Set-BillAnnotation -BillKey $selected.BillKey -Annotation $annotation

    # Update the in-memory representation
    $selected.Annotation = $annotation
    $selected.AffectsDRS = $annotation.affectsDRS
    $selected.FiscalNote = $annotation.fiscalNote

    # Update notes preview
    $notesPreview = ""
    if ($null -ne $annotation.notes -and $annotation.notes.Length -gt 0) {
        $notesPreview = $annotation.notes.Substring(0, [Math]::Min(50, $annotation.notes.Length))
        if ($annotation.notes.Length -gt 50) {
            $notesPreview += "..."
        }
    }
    $selected.NotesPreview = $notesPreview

    # Refresh grid to show updated values
    $WPF.dgBills.Items.Refresh()
}
#endregion

#region Event Handlers
$WPF.btnRefresh.Add_Click({
    Load-Bills
})

$WPF.btnImport.Add_Click({
    if (-not (Get-Command Import-Bill -ErrorAction SilentlyContinue)) {
        [System.Windows.MessageBox]::Show(
            "Import-Bill command not available. Please ensure Leg.psm1 is loaded.",
            "Error",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Error
        )
        return
    }

    $result = [System.Windows.MessageBox]::Show(
        "Import new bills? This will download from lawfilesext.leg.wa.gov.`n`nBill Type: Session Laws`nFormat: XML and HTM",
        "Import Bills",
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Question
    )

    if ($result -eq [System.Windows.MessageBoxResult]::Yes) {
        $WPF.txtStatus.Text = "Importing bills..."
        $WPF.txtStatus.Foreground = "Orange"

        try {
            # Run import in background (simplified - could use runspace for true async)
            Import-Bill -BillType "Session Laws" -Format xml
            Import-Bill -BillType "Session Laws" -Format htm

            $WPF.txtStatus.Text = "Import complete"
            $WPF.txtStatus.Foreground = "Green"

            # Reload bills
            Load-Bills
        } catch {
            $WPF.txtStatus.Text = "Import failed"
            $WPF.txtStatus.Foreground = "Red"
            [System.Windows.MessageBox]::Show(
                "Import failed: $_",
                "Error",
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Error
            )
        }
    }
})

$WPF.btnClearFilter.Add_Click({
    $WPF.txtFilter.Text = ""
    $WPF.cmbBillType.SelectedIndex = 0
    $WPF.cmbChamber.SelectedIndex = 0
    Update-BillGrid
})

$WPF.txtFilter.Add_TextChanged({
    Update-BillGrid
})

$WPF.cmbBillType.Add_SelectionChanged({
    Update-BillGrid
})

$WPF.cmbChamber.Add_SelectionChanged({
    Update-BillGrid
})

$WPF.dgBills.Add_SelectionChanged({
    Update-AnnotationPanel -SelectedItem $WPF.dgBills.SelectedItem
})

# Save annotation on changes
$WPF.chkAffectsDRS.Add_Checked({
    Save-CurrentAnnotation
})

$WPF.chkAffectsDRS.Add_Unchecked({
    Save-CurrentAnnotation
})

$WPF.cmbFiscalNote.Add_SelectionChanged({
    if ($WPF.cmbFiscalNote.IsEnabled) {
        Save-CurrentAnnotation
    }
})

$WPF.txtNotes.Add_LostFocus({
    Save-CurrentAnnotation
})

$WPF.btnAddTag.Add_Click({
    $selected = $WPF.dgBills.SelectedItem
    if ($null -eq $selected) { return }

    # Simple input dialog using VB
    Add-Type -AssemblyName Microsoft.VisualBasic
    $tag = [Microsoft.VisualBasic.Interaction]::InputBox(
        "Enter a new tag:",
        "Add Tag",
        ""
    )

    if (-not [string]::IsNullOrWhiteSpace($tag)) {
        $currentTags = $WPF.txtTags.Text
        if ([string]::IsNullOrWhiteSpace($currentTags)) {
            $WPF.txtTags.Text = $tag
        } else {
            $WPF.txtTags.Text = "$currentTags, $tag"
        }
        Save-CurrentAnnotation
    }
})
#endregion

#region Initialization
# Populate filter dropdowns
$billTypeItems = @("All", "House Bills", "Senate Bills", "Session Laws")
foreach ($item in $billTypeItems) {
    $comboItem = New-Object System.Windows.Controls.ComboBoxItem
    $comboItem.Content = $item
    if ($item -eq "All") {
        $comboItem.IsSelected = $true
    }
    $WPF.cmbBillType.Items.Add($comboItem) | Out-Null
}

$chamberItems = @("All", "House", "Senate", "Law")
foreach ($item in $chamberItems) {
    $comboItem = New-Object System.Windows.Controls.ComboBoxItem
    $comboItem.Content = $item
    if ($item -eq "All") {
        $comboItem.IsSelected = $true
    }
    $WPF.cmbChamber.Items.Add($comboItem) | Out-Null
}

# Load data
Load-Annotations
Load-Bills

# Show window
Write-Verbose "Showing dashboard window..."
[void]$window.ShowDialog()
#endregion
