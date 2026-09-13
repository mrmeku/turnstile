locals_without_parens = [object_type: 1, carries: 1, fact: 2, relationship: 1, scenario: 4]

[
  plugins: [Styler],
  import_deps: [:ecto, :nimble_options],
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
  locals_without_parens: locals_without_parens,
  export: [locals_without_parens: locals_without_parens]
]
