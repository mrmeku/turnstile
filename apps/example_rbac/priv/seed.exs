# The world a review of a past date is asked about: one program, two
# accounts assigned to it in March, and one of those two revoked in April.
# The dates are the point. A fact event is stamped by the clock the port
# reads, so the seed moves that clock rather than the rows, and the ledger
# ends holding a grant of each account and a revocation of one.
#
#     mix ecto.migrate -r Example.OwnerRepo --migrations-path priv/repo/migrations
#     mix run priv/seed.exs
#     mix turnstile.review --at 2026-04-02
#     mix turnstile.review --at 2026-03-31

alias Example.Accounts
alias Example.Agency
alias Example.Office
alias Example.OwnerRepo
alias Example.Program
alias Example.Repo
alias Example.User

defmodule Seed.Clock do
  @moduledoc false
  @behaviour Turnstile.Clock

  @key {__MODULE__, :now}

  def set(%DateTime{} = now) do
    _previous = Process.put(@key, now)
    :ok
  end

  @impl Turnstile.Clock
  def now, do: Process.get(@key) || raise("Seed.Clock.set/1 was not called in this process")
end

exempt = {:exempt, "seed: the world the review is asked about"}
emptied = "turnstile_ledger_events, assignments, users, programs, offices, agencies"

_truncated = OwnerRepo.query!("TRUNCATE #{emptied} RESTART IDENTITY CASCADE")
_reset = OwnerRepo.query!("UPDATE turnstile_ledger_counter SET position = 0 WHERE name = 'default'")

:ok = Turnstile.Test.with_config(clock: Seed.Clock)
:ok = Seed.Clock.set(~U[2026-03-01 09:00:00.000000Z])

agency = Repo.insert!(%Agency{name: "Domestic", nationality: "US"}, turnstile: exempt)
office = Repo.insert!(%Office{name: "Domestic office", agency_id: agency.id}, turnstile: exempt)
program = Repo.insert!(%Program{name: "Domestic program", office_id: office.id}, turnstile: exempt)

for id <- ~w(ann bob) do
  account = %User{id: id, name: id, kind: :user, person_id: id, employment: :federal, nationality: "US"}
  _inserted = Repo.insert!(account, turnstile: exempt)
end

_ann = Accounts.assign("ann", program.id, :member)
_bob = Accounts.assign("bob", program.id, :member)

:ok = Seed.Clock.set(~U[2026-04-01 09:00:00.000000Z])
1 = Accounts.unassign("ann", program.id)

IO.puts("ann and bob assigned to program #{program.id} on 2026-03-01, ann revoked on 2026-04-01")
