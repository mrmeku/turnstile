locals_without_parens = [role: 2, object: 2, object: 3, grant: 2, grant: 3, predicate: 2]

[
  plugins: [Styler],
  import_deps: [:ecto, :nimble_options, :turnstile_core],
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}", "priv/conformance/**/*.ex"],
  locals_without_parens: locals_without_parens,
  export: [locals_without_parens: locals_without_parens]
]
