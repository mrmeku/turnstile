defmodule Turnstile.Postgres.MixProject do
  use Mix.Project

  def project do
    [
      app: :turnstile_postgres,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.20.4",
      elixirc_paths: elixirc_paths(Mix.env()),
      elixirc_options: [warnings_as_errors: true, infer_signatures: true, no_warn_undefined: []],
      compilers: [:boundary] ++ Mix.compilers(),
      start_permanent: Mix.env() == :prod,
      test_coverage: [summary: [threshold: 90], ignore_modules: [~r/\.Generated\./, ~r/TestRepos\./]],
      aliases: aliases(),
      hex: hex(),
      deps: deps(),
      docs: docs()
    ]
  end

  def cli do
    [preferred_envs: [quality: :test]]
  end

  def application do
    [extra_applications: [:logger]]
  end

  # The conformance artifacts under priv/conformance are modules the test run
  # compiles; an application never loads them.
  defp elixirc_paths(:test), do: ["lib", "test/support", "priv/conformance"]
  defp elixirc_paths(_env), do: ["lib"]

  # lib depends on core, ecto, and telemetry alone: every statement it runs
  # goes through the mediated repo's raw bucket, so ecto_sql, postgrex, and
  # stream_data serve the test run. Every pin is exact. Versions verified
  # against https://hex.pm/api/packages/<name> on 2026-09-08.
  defp deps do
    [
      {:turnstile_core, in_umbrella: true},
      {:ecto, "3.14.2"},
      {:nimble_options, "1.1.1"},
      {:telemetry, "1.4.2"},
      {:ecto_sql, "3.14.0", only: :test},
      {:postgrex, "0.22.4", only: :test},
      {:stream_data, "1.4.0", only: :test},
      {:boundary, "0.10.4", runtime: false},
      {:credo, "1.7.19", only: [:dev, :test], runtime: false},
      {:styler, "1.12.2", only: [:dev, :test], runtime: false},
      {:ex_doc, "0.40.4", only: [:dev, :test], runtime: false},
      {:mix_audit, "2.1.5", only: [:dev, :test], runtime: false}
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md": [title: "Turnstile on row-level security"], "glossary.md": [title: "Glossary"]]
    ]
  end

  # CVE-2026-32686 (GHSA-rhv4-8758-jx7v): an unbounded exponent when decimal
  # parses an untrusted string. Every decimal release is in the advisory's
  # range and none is patched (checked at https://api.osv.dev/v1/vulns/EEF-CVE-2026-32686
  # and https://hex.pm/api/packages/decimal on 2026-09-08). Turnstile parses
  # no decimals and declares no decimal field, so the advisory is acknowledged
  # here rather than fixed, and reviewed when a patched release appears.
  defp hex do
    [ignore_advisories: ["CVE-2026-32686"]]
  end

  defp aliases do
    [
      quality: [
        # First: Hex requires it before any task that loads the application.
        "hex.audit",
        "format --check-formatted",
        "compile --force --warnings-as-errors --all-warnings",
        "credo --strict --all",
        "xref graph --label compile-connected --fail-above 0",
        "xref graph --format cycles --fail-above 0",
        "deps.audit --ignore-advisory-ids GHSA-rhv4-8758-jx7v",
        "docs --warnings-as-errors",
        "test --warnings-as-errors --cover"
      ]
    ]
  end
end
