defmodule Turnstile.Fga.OutboxTest do
  use Turnstile.Fga.OutboxCase,
    async: false,
    repo: Turnstile.TestRepos.Sandboxed,
    population: Turnstile.Fga.Conformance.Population,
    sandbox: Turnstile.Fga.Conformance.Setup
end
