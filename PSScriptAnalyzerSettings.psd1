# PSScriptAnalyzer settings for this repository.
# All default rules apply, except the ones excluded below (each with its reason).
# Run the analysis locally with: .\tests\Invoke-ScriptAnalysis.ps1
@{
    Severity     = @('Error', 'Warning', 'Information')

    ExcludeRules = @(
        # The setup scripts are interactive: they print colored progress to the console on purpose.
        'PSAvoidUsingWriteHost',

        # Internal helper functions are called with positional arguments for readability.
        'PSAvoidUsingPositionalParameters'
    )
}
