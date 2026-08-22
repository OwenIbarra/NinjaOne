<#
    .SYNOPSIS
        Core test suite for the NinjaOne module.
#>

$ModuleName = 'NinjaOne'

BeforeAll {
    $ModuleName = 'NinjaOne'
    $ManifestPath = $env:NINJAONE_MODULE_MANIFEST
    if ([string]::IsNullOrWhiteSpace($ManifestPath)) {
        $ModulePath = Resolve-Path -Path '.\Output\*\*' | Sort-Object -Property BaseName | Select-Object -Last 1 -ExpandProperty Path
        $ManifestPath = Get-ChildItem -Path ('{0}\*' -f $ModulePath) -Filter '*.psd1' | Select-Object -ExpandProperty FullName
    }

    if (-not (Get-Module -Name $ModuleName)) {
        Import-Module $ManifestPath -Verbose:$False
    }
    $Script:ModuleInformation = Get-Module -Name $ModuleName
    if (-not $Script:ModuleInformation) {
        $Script:ModuleInformation = Import-Module -Name $ManifestPath -PassThru
    }

}

Describe 'Codecov configuration generation' {
	It 'reserves fixed flag identifiers before generating folder flags' {
		$generatorPath = Join-Path -Path $PSScriptRoot -ChildPath '..\DevOps\Quality\generate-codecov-config.ps1'
		$generatorContent = Get-Content -Path $generatorPath -Raw

		$generatorContent | Pester\Should -Match '(?s)\$flagIds\s*=\s*@\{\s*(?=.*\bclasses\s*=\s*\$true)(?=.*\bprivate\s*=\s*\$true)(?=.*\bpublic\s*=\s*\$true).*?\}\s*foreach\s*\(\$folderName\s+in\s+\$folderMappings\.Keys\)'
	}
}

Describe ('{0} - Core Tests' -f $ModuleName) -Tags 'Module' {
    It 'Manifest is valid' {
        {
            Test-ModuleManifest -Path $ManifestPath -ErrorAction Stop -WarningAction SilentlyContinue
        } | Pester\Should -Not -Throw
    }

    It 'Root module is correct' {
        $Script:ModuleInformation.RootModule | Pester\Should -Be ('.\{0}.psm1' -f $ModuleName)
    }

    It 'Loads required assemblies from the manifest without script-level using statements' {
        $repoRoot = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')
        $initialisationPath = Join-Path -Path $repoRoot -ChildPath 'Source\Initialisation.ps1'
        $initialisationContent = Get-Content -Path $initialisationPath -TotalCount 5
        $requiredAssemblyNames = @(
            $Script:ModuleInformation.RequiredAssemblies |
                ForEach-Object { [System.IO.Path]::GetFileName([string]$_) }
        )

        ($initialisationContent -join "`n") | Pester\Should -Not -Match 'using assembly'
        $requiredAssemblyNames | Pester\Should -Contain 'MetadataAttribute.dll'
        $requiredAssemblyNames | Pester\Should -Contain 'ValidateNodeRoleId.dll'
    }

    It 'Has a description' {
        $Script:ModuleInformation.Description | Pester\Should -Not -BeNullOrEmpty
    }

    It 'GUID is correct' {
        $Script:ModuleInformation.GUID | Pester\Should -Be '2f88e09d-773b-441e-8ca5-5b5eff57bf3c'
    }

    It 'Version is valid' {
        $Script:ModuleInformation.Version -As [Version] | Pester\Should -Not -BeNullOrEmpty
    }

    It 'Copyright is present' {
        $Script:ModuleInformation.Copyright | Pester\Should -Not -BeNullOrEmpty
    }

    It 'License URI is correct' {
        $Script:ModuleInformation.LicenseUri | Pester\Should -Be 'https://mit.license.homotechsual.dev/'
    }

    It 'Project URI is correct' {
        $Script:ModuleInformation.ProjectUri | Pester\Should -Be 'https://docs.homotechsual.dev/modules/ninjaone'
    }

    It 'PowerShell Gallery tags is not empty' {
        $Script:ModuleInformation.Tags.count | Pester\Should -Not -BeNullOrEmpty
    }

    It 'PowerShell Gallery tags do not contain spaces' {
        foreach ($Tag in $Script:ModuleInformation.Tags) {
            $Tag -NotMatch '\s' | Pester\Should -Be $True
        }
    }
}

Describe ('{0} - Module Load Test' -f $ModuleName) -Tags 'Module' {
    It 'Passed Module load' {
        Get-Module -Name 'NinjaOne' | Pester\Should -Not -Be $null
    }
}

Describe ('{0} - DateTime Parsing' -f $ModuleName) -Tags 'Module' {
    It 'Converts ISO 8601 and Unix epoch values' {
        $module = Get-Module -Name $ModuleName
        Pester\InModuleScope $ModuleName {
            $input = [pscustomobject]@{
                createdAt = '2024-01-01T12:34:56Z'
                updatedAt = 1704112496
                createdFloat = 1769013679.4855
                nested = [pscustomobject]@{
                    time = '1704112496000'
                    lastUpdate = '1771675908.804'
                    raw = 'not-a-date'
                    smallNumber = 1234
                }
            }
            $result = ConvertFrom-NinjaOneDateTime -InputObject $input
            $result.createdAt | Pester\Should -BeOfType ([DateTime])
            $result.updatedAt | Pester\Should -BeOfType ([DateTime])
            $result.createdFloat | Pester\Should -BeOfType ([DateTime])
            $result.nested.time | Pester\Should -BeOfType ([DateTime])
            $result.nested.lastUpdate | Pester\Should -BeOfType ([DateTime])
            $result.nested.raw | Pester\Should -Be 'not-a-date'
            $result.nested.smallNumber | Pester\Should -Be 1234
        }
    }
}

AfterAll {
    Remove-Module $ModuleName -Force
}