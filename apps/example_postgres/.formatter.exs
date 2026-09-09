[
  plugins: [Styler],
  import_deps: [:ecto, :ecto_sql, :turnstile_core, :turnstile_postgres],
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}", "priv/repo/migrations/*.exs"]
]
