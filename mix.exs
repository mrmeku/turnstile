defmodule Turnstile.Umbrella.MixProject do
  use Mix.Project

  def project do
    [
      apps_path: "apps",
      version: "0.1.0",
      elixir: "~> 1.20.4",
      start_permanent: Mix.env() == :prod,
      elixirc_options: [warnings_as_errors: true, infer_signatures: true, no_warn_undefined: []],
      test_coverage: [summary: [threshold: 90], ignore_modules: [~r/\.Generated\./]],
      aliases: aliases(),
      deps: deps(),
      docs: docs()
    ]
  end

  # Tools shared by every app. Each pin is exact; mix.lock holds the checksum.
  # Versions verified against https://hex.pm/api/packages/<name> on 2026-09-08.
  defp deps do
    [
      {:credo, "1.7.19", only: [:dev, :test], runtime: false},
      {:styler, "1.12.2", only: [:dev, :test], runtime: false},
      {:ex_doc, "0.40.4", only: :dev, runtime: false},
      {:mix_audit, "2.1.5", only: [:dev, :test], runtime: false}
    ]
  end

  defp docs do
    [main: "readme", extras: ["README.md": [title: "Turnstile"]]]
  end

  # docs/code.md §5. The test step is a function so CI can add --partitions
  # through MIX_TEST_PARTITION without a second alias.
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
        &run_tests/1
      ]
    ]
  end

  defp run_tests(_args) do
    partitions =
      case System.get_env("MIX_TEST_PARTITION") do
        nil -> []
        _set -> ["--partitions", System.get_env("MIX_TEST_PARTITIONS", "4")]
      end

    Mix.Task.run("test", ["--warnings-as-errors", "--cover"] ++ partitions)
  end
end
