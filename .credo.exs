%{
  configs: [
    %{
      name: "default",
      checks: [
        {Credo.Check.Design.AliasUsage, if_nested_deeper_than: 4}
      ]
    }
  ]
}
