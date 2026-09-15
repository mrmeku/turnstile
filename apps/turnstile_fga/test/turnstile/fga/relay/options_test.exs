defmodule Turnstile.Fga.Relay.OptionsTest do
  use ExUnit.Case, async: true

  alias Turnstile.Fga.Relay.Options
  alias Turnstile.Fga.Relay.TestJob
  alias Turnstile.TestRepos.Sandboxed

  test "a runner named with a repo and a job carries the rest as defaults" do
    options = Options.validate!(name: :defaults, repo: Sandboxed, job: TestJob)

    assert options[:batch] == 100
    assert options[:idle] == 1_000
    assert options[:backoff] == 1_000
    assert options[:backoff_max] == 30_000
    assert options[:timeout] == 30_000
    assert options[:register]
    assert options[:first] == nil
    assert is_function(options[:clock], 0)
  end

  test "the job's own options are validated where the runner is configured" do
    options = Options.validate!(name: :job_options, repo: Sandboxed, job: TestJob)

    assert Enum.sort(options[:job_options]) == [runner: TestJob.default(), tag: "sent"]
  end

  test "a job option the job does not know is refused before the first pass" do
    assert_raise NimbleOptions.ValidationError, fn ->
      Options.validate!(name: :wrong, repo: Sandboxed, job: TestJob, job_options: [unknown: true])
    end
  end

  test "a runner without a name is refused" do
    assert_raise NimbleOptions.ValidationError, fn -> Options.validate!(repo: Sandboxed, job: TestJob) end
  end

  test "the schema the package publishes is the one a runner is validated against" do
    assert Turnstile.Fga.Relay.options_schema() == Options.schema()
  end
end
