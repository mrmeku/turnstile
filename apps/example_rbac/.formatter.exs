[
  plugins: [Styler],
  import_deps: [:ecto, :ecto_sql, :turnstile_core, :turnstile_rbac],
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}", "priv/repo/migrations/*.exs"]
]
