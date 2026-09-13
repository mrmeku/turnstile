defmodule Example.RepoTest do
  use Turnstile.Conformance.RepoCase, repo: Example.Repo, rows: Example.Fixture.Rows, async: true
end
