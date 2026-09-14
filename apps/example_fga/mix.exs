defmodule ExampleFga.MixProject do
  use Mix.Project

  def project do
    [
      app: :example_fga,
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
      test_coverage: test_coverage(),
      aliases: aliases(),
      hex: hex(),
      deps: deps(),
      docs: docs(),
      turnstile: turnstile()
    ]
  end

  # The dump task raises an ephemeral cluster, and the connection library the
  # cluster rests on is loaded in the test environment alone.
  def cli do
    [preferred_envs: [quality: :test, "turnstile.schema_dump": :test]]
  end

  # `:inets` carries `httpc`, which the adapter asks the server with.
  def application do
    [mod: {ExampleFga.Application, []}, extra_applications: [:logger, :inets]]
  end

  # The coverage a run measures. A run with TURNSTILE_CORE_COVERAGE set
  # ignores every module outside a `core/` and holds what is left to every
  # line, which a module that decides and touches nothing can be held to.
  # Any other run is the ordinary one, whose threshold is a floor under the
  # application as a whole.
  defp test_coverage do
    if System.get_env("TURNSTILE_CORE_COVERAGE") do
      [summary: [threshold: 100], ignore_modules: [~r/^(?!.*\.Core\.)/]]
    else
      [summary: [threshold: 90], ignore_modules: ignore_modules()]
    end
  end

  defp ignore_modules, do: [~r/\.Generated\./]

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  # What the library's tasks read: the repo whose migrations produce the
  # committed schema file.
  defp turnstile do
    [
      schema_dump: [repo: Example.OwnerRepo, output: "priv/schema/fga.sql"]
    ]
  end

  # The example, the adapter, the relay the drain is a runner of, and the
  # connection library the cluster the dump task raises rests on. `muontrap`
  # starts the server the suite asks, through the test support of the
  # adapter. Every pin is exact. Versions verified against
  # https://hex.pm/api/packages/<name> on 2026-09-09.
  defp deps do
    [
      {:turnstile, in_umbrella: true},
      {:turnstile_dev, in_umbrella: true, only: :test},
      {:example, in_umbrella: true},
      {:turnstile_fga, in_umbrella: true},
      {:turnstile_relay, in_umbrella: true},
      {:ecto, "3.14.2"},
      {:ecto_sql, "3.14.0"},
      {:postgrex, "0.22.4"},
      {:muontrap, "2.0.0", only: :test},
      {:boundary, "0.10.4", runtime: false},
      {:sobelow, "0.15.0", only: [:dev, :test], runtime: false},
      {:credo, "1.7.19", only: [:dev, :test], runtime: false},
      {:turnstile_credo, in_umbrella: true, only: [:dev, :test], runtime: false},
      {:styler, "1.12.2", only: [:dev, :test], runtime: false},
      {:ex_doc, "0.40.4", only: [:dev, :test], runtime: false},
      {:mix_audit, "2.1.5", only: [:dev, :test], runtime: false}
    ]
  end

  defp docs do
    [main: "readme", extras: ["README.md": [title: "The example on a relationship graph"]]]
  end

  # CVE-2026-32686 (GHSA-rhv4-8758-jx7v): an unbounded exponent when decimal
  # parses an untrusted string. Every decimal release is in the advisory's
  # range and none is patched (checked at https://api.osv.dev/v1/vulns/EEF-CVE-2026-32686
  # and https://hex.pm/api/packages/decimal on 2026-09-09). Turnstile parses
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
        "sobelow --config --exit",
        "docs --warnings-as-errors",
        "test --warnings-as-errors --cover"
      ]
    ]
  end
end
