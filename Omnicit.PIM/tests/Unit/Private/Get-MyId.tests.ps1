Describe-UnitTest -Name 'Get-MyId' -ScriptBlock {
    It 'should return the correct ID for valid input' {
        $result = Get-MyId -InputObject 'validInput'
        $expected = 'expectedId'
        $result | Should -Be $expected
    }

    It 'should throw an error for invalid input' {
        { Get-MyId -InputObject 'invalidInput' } | Should -Throw
    }
}