defmodule Turnstile.Core.MixProject do
  use Mix.Project

  def project do
    [
      app: :turnstile_core,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.20.4",
      elixirc_paths: elixirc_paths(Mix.env()),
      elixirc_options: [warnings_as_errors: true, infer_signatures: true, no_warn_undefined: []],
      start_permanent: Mix.env() == :prod,
      test_coverage: [summary: [threshold: 90], ignore_modules: [~r/\.Generated\./]],
      aliases: aliases(),
      deps: deps()
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  # lib depends on ecto alone; ecto_sql and postgrex serve the test cluster.
  # Versions verified against https://hex.pm/api/packages/<name> on 2026-09-08.
  defp deps do
    [
      {:ecto, "3.14.2"},
      {:nimble_options, "1.1.1"},
      {:telemetry, "1.4.2"},
      {:ecto_sql, "3.14.0", only: :test},
      {:postgrex, "0.22.4", only: :test}
    ]
  end

  defp aliases do
    [
      quality: [
        "format --check-formatted",
        "compile --force --warnings-as-errors --all-warnings",
        "credo --strict --all",
        "xref graph --label compile-connected --fail-above 0",
        "xref graph --format cycles --fail-above 0",
        "deps.unlock --check-unused",
        "hex.audit",
        "deps.audit",
        "docs --warnings-as-errors",
        "test --warnings-as-errors --cover"
      ]
    ]
  end
end
