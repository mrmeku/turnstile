defmodule ExampleFga.OutboxTest do
  use Turnstile.Fga.OutboxCase,
    async: false,
    repo: Example.Repo,
    population: ExampleFga.Population,
    sandbox: ExampleFga.OutboxSetup
end
