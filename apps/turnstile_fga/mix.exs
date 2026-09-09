defmodule Turnstile.Fga.MixProject do
  use Mix.Project

  def project do
    [
      app: :turnstile_fga,
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

  # The fake client, the probe that appends fact events, and the checkpoint
  # migration are test support; the tuple mapping over the neutral fixture is
  # conformance, so a thin application reads it as the worked example.
  defp elixirc_paths(:test), do: ["lib", "test/support", "priv/conformance"]
  defp elixirc_paths(_env), do: ["lib"]

  # The projector reads fact events through the ledger's reader, so the
  # ledger package is a dependency of lib rather than of the test run.
  # ecto_sql is unrestricted because the checkpoint migration helper ships in
  # lib, and postgrex because the ledger package carries it in every
  # environment, so a narrower `only` here would not match what the umbrella
  # calculates. stream_data is unrestricted because core's
  # conformance templates ship in lib, so core carries it in every
  # environment. telemetry is unrestricted because the real client emits one
  # event per call from lib, and muontrap serves the test run alone, where it
  # starts the one server the suite asks for. Every pin is exact. Versions
  # verified against https://hex.pm/api/packages/<name> on 2026-09-09.
  defp deps do
    [
      {:turnstile_core, in_umbrella: true},
      {:turnstile_ledger, in_umbrella: true},
      {:ecto, "3.14.2"},
      {:ecto_sql, "3.14.0"},
      {:nimble_options, "1.1.1"},
      {:postgrex, "0.22.4"},
      {:stream_data, "1.4.0"},
      {:telemetry, "1.4.2"},
      {:muontrap, "2.0.0", only: :test},
      {:boundary, "0.10.4", runtime: false},
      {:credo, "1.7.19", only: [:dev, :test], runtime: false},
      {:styler, "1.12.2", only: [:dev, :test], runtime: false},
      {:ex_doc, "0.40.4", only: [:dev, :test], runtime: false},
      {:mix_audit, "2.1.5", only: [:dev, :test], runtime: false}
    ]
  end

  defp docs do
    [main: "readme", extras: ["README.md": [title: "Turnstile FGA"], "glossary.md": [title: "Glossary"]]]
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
