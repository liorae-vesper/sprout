%{
  configs: [
    %{
      name: "default",
      strict: true,
      files: %{included: ["lib/", "test/", "config/", "mix.exs", ".formatter.exs", ".credo.exs"]}
    }
  ]
}
