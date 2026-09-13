defmodule Turnstile.Ledger.MemoryConformanceTest do
  use Turnstile.Conformance.LedgerCase, ledger: :memory, async: true
end
