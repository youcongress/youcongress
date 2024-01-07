%{
  configs: [
    %{
      name: "default",
      checks: [
        {Credo.Check.Design.AliasUsage, if_nested_deeper_than: 4},
        {Credo.Check.Refactor.CyclomaticComplexity, max_complexity: 11},
        {Credo.Check.Readability.AliasOrder, false},
        {Credo.Check.Refactor.Nesting, max_nesting: 3}
      ]
    }
  ]
}
