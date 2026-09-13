defmodule Turnstile.Conformance.RepoCaseTest do
  use Turnstile.Conformance.RepoCase,
    repo: Turnstile.TestRepos.Sandboxed,
    rows: Turnstile.Fixture.Rows,
    async: true
end
