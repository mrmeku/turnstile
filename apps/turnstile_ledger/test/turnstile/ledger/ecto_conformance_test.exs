defmodule Turnstile.Ledger.EctoConformanceTest do
  use Turnstile.Conformance.LedgerCase,
    ledger: {Turnstile.Ledger.Ecto, repo: Turnstile.Ledger.TestRepos.App, owner_repo: Turnstile.Ledger.TestRepos.Owner},
    repo: Turnstile.Ledger.TestRepos.App,
    async: true
end
