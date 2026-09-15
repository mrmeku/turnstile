defmodule Turnstile.Dev.MixProject do
  use Mix.Project

  def project do
    [
      app: :turnstile_dev,
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
      test_coverage: [summary: [threshold: 90], ignore_modules: [~r/TestRepos\./]],
      aliases: aliases(),
      hex: hex(),
      deps: deps(),
      docs: docs(),
      turnstile: turnstile(Mix.env())
    ]
  end

  def cli do
    [preferred_envs: [quality: :test, "turnstile.schema_dump": :test]]
  end

  def application do
    # `:inets` carries `httpc`, which the launchers ask a server's health
    # endpoint with. It ships with OTP, so it is no pin.
    [extra_applications: [:logger, :inets]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  # The schema-dump task reads this key from the application that runs it.
  # This package's own run points it at a test repo and the test table as a
  # migration.
  defp turnstile(:test) do
    [
      schema_dump: [
        repo: Turnstile.Dev.TestRepos.Dump,
        output: "tmp/schema/dev.sql",
        migrations: [{1, Turnstile.Dev.TestMigration}]
      ]
    ]
  end

  defp turnstile(_env), do: []

  # This package is never published, so what it needs sits here in every
  # environment rather than being optional: `muontrap` runs a sidecar and
  # kills it with the run, `nimble_options` validates what a caller passes,
  # and `ecto_sql` carries the sandbox and the migrator the cluster and the
  # dump run. `postgrex` is the driver this package's own suite connects
  # with. Core is no dependency, so core can take this package in its test
  # environment without a cycle. Every pin is exact. Versions verified
  # against https://hex.pm/api/packages/<name> on 2026-09-08.
  defp deps do
    [
      {:nimble_options, "1.1.1"},
      {:muontrap, "2.0.0"},
      {:ecto_sql, "3.14.0"},
      {:postgrex, "0.22.4", only: :test},
      {:boundary, "0.10.4", runtime: false},
      {:credo, "1.7.19", only: [:dev, :test], runtime: false},
      {:turnstile_credo, in_umbrella: true, only: [:dev, :test], runtime: false},
      {:styler, "1.12.2", only: [:dev, :test], runtime: false},
      {:ex_doc, "0.40.4", only: [:dev, :test], runtime: false},
      {:mix_audit, "2.1.5", only: [:dev, :test], runtime: false}
    ]
  end

  defp docs do
    [main: "readme", extras: ["README.md": [title: "Turnstile dev"]]]
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
