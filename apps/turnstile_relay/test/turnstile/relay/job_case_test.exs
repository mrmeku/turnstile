defmodule Turnstile.Relay.JobCaseTest do
  use Turnstile.Relay.JobCase,
    async: true,
    job: Turnstile.Relay.TestJob,
    repo: Turnstile.TestRepos.Sandboxed,
    rows: Turnstile.Relay.TestJob,
    sandbox: Turnstile.Relay.TestSandbox
end
