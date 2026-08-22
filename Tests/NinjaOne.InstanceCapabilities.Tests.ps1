<#
    .SYNOPSIS
        Instance capability test suite for the NinjaOne module.
#>
BeforeAll {
    Import-Module ('{0}\TestScaffold.psm1' -f $PSScriptRoot) -Force
    Import-ModuleToBeTested
    $ModuleName = Get-ModuleName
    $Module = Get-Module -Name $ModuleName
}

Describe 'Get-NinjaOneOpenApiPaths' -Tags 'Module' {
    It 'Parses YAML paths and methods' {
        Pester\InModuleScope -ModuleName $ModuleName {
            $yaml = @"
openapi: 3.0.1
info:
  title: Test
paths:
  /v2/device:
    get:
      summary: list
    post:
      summary: create
  /v2/device/{id}:
    get:
      summary: get
components:
  schemas: {}
"@
            $paths = Get-NinjaOneOpenApiPaths -OpenApiYaml $yaml

            $paths.Keys | Pester\Should -Contain '/v2/device'
            $paths['/v2/device'].Contains('GET') | Pester\Should -BeTrue
            $paths['/v2/device'].Contains('POST') | Pester\Should -BeTrue
            $paths.Keys | Pester\Should -Contain '/v2/device/{id}'
            $paths['/v2/device/{id}'].Contains('GET') | Pester\Should -BeTrue
        }
    }

    It 'Handles empty paths section' {
        Pester\InModuleScope -ModuleName $ModuleName {
            $yaml = @"
openapi: 3.0.1
info:
  title: Test
paths:
"@
            $paths = Get-NinjaOneOpenApiPaths -OpenApiYaml $yaml

            $paths.Count | Pester\Should -Be 0
        }
    }

    It 'Keeps paths without methods' {
        Pester\InModuleScope -ModuleName $ModuleName {
            $yaml = @"
openapi: 3.0.1
info:
  title: Test
paths:
  /v2/device:
"@
            $paths = Get-NinjaOneOpenApiPaths -OpenApiYaml $yaml

            $paths.Keys | Pester\Should -Contain '/v2/device'
            $paths['/v2/device'].Count | Pester\Should -Be 0
        }
    }
}

Describe 'Test-NinjaOneEndpointSupport' -Tags 'Module' {
    It 'Matches multiple placeholder segments' {
        Pester\InModuleScope -ModuleName $ModuleName {
            $previousEnabled = $Script:NRAPIInstanceCapabilityCheckEnabled
            $previousConnection = $Script:NRAPIConnectionInformation
            $previousCapabilities = $Script:NRAPIInstanceCapabilities

            $Script:NRAPIInstanceCapabilityCheckEnabled = $true
            $Script:NRAPIConnectionInformation = [PSCustomObject]@{ URL = 'https://eu.ninjarmm.com' }
            $Script:NRAPIInstanceCapabilities = @{}

            $paths = @{
                '/v2/organization/{orgId}/location/{locationId}/custom-fields' = [System.Collections.Generic.HashSet[string]]::new()
            }
            $Script:NRAPIInstanceCapabilities['https://eu.ninjarmm.com'] = [PSCustomObject]@{
                BaseUrl = 'https://eu.ninjarmm.com'
                Version = '12.0.20'
                SpecUrl = 'https://eu.ninjarmm.com/apidocs-beta/NinjaRMM-API-v2.yaml'
                RetrievedAt = Get-Date
                Paths = $paths
            }

            $result = Test-NinjaOneEndpointSupport -Method 'PATCH' -Resource '/v2/organization/2/location/5/custom-fields'
            $result | Pester\Should -BeTrue

            $Script:NRAPIInstanceCapabilityCheckEnabled = $previousEnabled
            $Script:NRAPIConnectionInformation = $previousConnection
            $Script:NRAPIInstanceCapabilities = $previousCapabilities
        }
    }
}

Describe 'Get-NinjaOneInstanceCapabilitiesInternal' -Tags 'Module' {
    It 'Refreshes cached capabilities when forced' {
        $yaml1 = @"
openapi: 3.0.1
info:
  title: Test
paths:
  /v2/device:
    get: {}
"@
        $yaml2 = @"
openapi: 3.0.1
info:
  title: Test
paths:
  /v2/device/{id}:
    get: {}
"@
        $yamlSequence = @(
            [System.Text.Encoding]::UTF8.GetBytes($yaml1),
            [System.Text.Encoding]::UTF8.GetBytes($yaml2)
        )
        $global:yamlSequence = $yamlSequence

        Pester\InModuleScope -ModuleName $ModuleName {
            $Script:NRAPIInstanceCapabilities.Clear()
            $Script:yamlIndex = 0
            $Script:yamlSequence = $global:yamlSequence

            Pester\Mock -CommandName Invoke-WebRequest -ModuleName $ModuleName -ParameterFilter { $Uri -like '*app-version.txt' } -MockWith {
                [pscustomobject]@{ Content = '8.4.0-f' }
            }
            Pester\Mock -CommandName Invoke-WebRequest -ModuleName $ModuleName -ParameterFilter { $Uri -like '*NinjaRMM-API-v2.yaml' } -MockWith {
                $bytes = $Script:yamlSequence[$Script:yamlIndex]
                $Script:yamlIndex += 1
                [pscustomobject]@{ Content = $bytes }
            }

            $first = Get-NinjaOneInstanceCapabilitiesInternal -BaseUrl 'https://fed.ninjarmm.com'
            $cached = Get-NinjaOneInstanceCapabilitiesInternal -BaseUrl 'https://fed.ninjarmm.com'
            $refreshed = Get-NinjaOneInstanceCapabilitiesInternal -BaseUrl 'https://fed.ninjarmm.com' -Force

            $first.Paths.Keys | Pester\Should -Contain '/v2/device'
            $cached.Paths.Keys | Pester\Should -Contain '/v2/device'
            $cached.Paths.Keys | Pester\Should -Not -Contain '/v2/device/{id}'
            $refreshed.Paths.Keys | Pester\Should -Contain '/v2/device/{id}'
        }

        $global:yamlSequence = $null
    }
}

Describe 'Get-NinjaOneInstanceCapabilities -IncludeCmdlets' -Tags 'Module' {
    BeforeAll {
        $capabilities = [pscustomobject]@{
            BaseUrl = 'https://fed.ninjarmm.com'
            Version = '8.4.0-f'
            SpecUrl = 'https://fed.ninjarmm.com/apidocs-beta/NinjaRMM-API-v2.yaml'
            RetrievedAt = Get-Date
            Paths = @{}
        }

        Pester\Mock -CommandName Get-NinjaOneInstanceCapabilitiesInternal -ModuleName $ModuleName -MockWith { $capabilities }
    }

    It 'Excludes private helper functions from analysis' {
        Pester\InModuleScope -ModuleName $ModuleName {
            $result = Get-NinjaOneInstanceCapabilities -BaseUrl 'https://fed.ninjarmm.com' -IncludeCmdlets
            $result.SupportedCmdlets | Pester\Should -Not -Contain 'Get-NinjaOneSecrets'
            $result.UnsupportedCmdlets | Pester\Should -Not -Contain 'Get-NinjaOneSecrets'
            $result.UnknownCmdlets | Pester\Should -Not -Contain 'Get-NinjaOneSecrets'
        }
    }
}

AfterAll {
    if (Get-Module -Name $ModuleName) {
        Remove-Module -Name $ModuleName -Force -ErrorAction SilentlyContinue
    }
}
