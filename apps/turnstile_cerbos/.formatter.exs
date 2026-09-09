locals_without_parens = [attribute: 2, principal: 3, resource: 3]

[
  plugins: [Styler],
  import_deps: [:ecto, :nimble_options, :turnstile_core],
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}", "priv/conformance/**/*.ex"],
  locals_without_parens: locals_without_parens,
  export: [locals_without_parens: locals_without_parens]
]
