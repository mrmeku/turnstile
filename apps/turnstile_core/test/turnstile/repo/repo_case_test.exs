defmodule Turnstile.Repo.RepoCaseTest do
  use Turnstile.Conformance.RepoCase, repo: Turnstile.TestRepos.Sandboxed, async: true
end
