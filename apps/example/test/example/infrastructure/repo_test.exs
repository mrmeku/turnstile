defmodule Example.Infrastructure.RepoTest do
  use Turnstile.Conformance.RepoCase, repo: Example.Infrastructure.Repo, rows: Example.Fixture.Rows, async: true
end
