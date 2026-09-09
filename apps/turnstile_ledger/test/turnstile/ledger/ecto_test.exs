defmodule Turnstile.Ledger.EctoTest do
  use ExUnit.Case, async: true

  alias Turnstile.Error
  alias Turnstile.FactEvent
  alias Turnstile.Ledger
  alias Turnstile.Ledger.Reader
  alias Turnstile.Ledger.TestRepos
  alias Turnstile.Ledger.TestSupport.Boot
  alias Turnstile.PolicyVersion
  alias Turnstile.Subject
  alias Turnstile.Test

  setup tags do
    Boot.setup(tags)
  end

  test "the head of a ledger whose counter row does not exist is an engine error, not a zero", context do
    Test.with_config(ledger_counter: "missing")

    assert {:error, %Error.Engine{operation: :head, detail: detail}} = Ledger.Ecto.head(options(context))
    assert detail =~ "no counter row named"
  end

  test "an append of nothing takes no position and answers nothing", context do
    assert {:ok, []} = Ledger.Ecto.append(options(context), [])
    assert {:ok, 0} = Ledger.Ecto.head(options(context))
  end

  test "a policy version reads back as the struct that was published", context do
    version = %PolicyVersion{
      adapter: Turnstile.Adapter.Fake,
      version: "abc123",
      content_hash: "sha256-1",
      content: "allow nothing",
      pointer: nil,
      author: "an author",
      approval: "a change ticket",
      at: ~U[2026-09-08 00:00:00.000000Z]
    }

    {:ok, [appended]} = Ledger.Ecto.append(options(context), [published(version)])

    assert {:ok, [read]} = Ledger.Ecto.read(options(context), 0, 10)
    assert read == appended
    assert read.new == version
  end

  test "a fact value of every shape the codec tags reads back as the term that was written", context do
    values = ["text", 3, 4.5, true, :editor, ~U[2026-09-08 01:02:03.000004Z], [:a, "b"], %{role: :editor}]
    events = Enum.map(values, &event(&1))

    {:ok, _appended} = Ledger.Ecto.append(options(context), events)

    assert {:ok, read} = Ledger.Ecto.read(options(context), 0, 10)
    assert Enum.map(read, & &1.new) == values
  end

  test "the reader pages through a ledger longer than one page and answers every event in position order", context do
    count = Reader.page() + 100
    {:ok, appended} = Ledger.Ecto.append(options(context), Enum.map(1..count, &event(&1)))

    assert {:ok, read} = Reader.all({Ledger.Ecto, options(context)})
    assert length(read) == count
    assert Enum.map(read, & &1.position) == Enum.map(appended, & &1.position)
    assert Ledger.Ecto.count(TestRepos.App) == count
  end

  test "the options answer the repo, the dialect, and the lock clause the ledger was configured with", context do
    assert Ledger.Ecto.repo(options(context)) == TestRepos.App
    assert Ledger.Ecto.dialect(options(context)) == Turnstile.Ledger.Dialect.Postgres
    assert Ledger.Ecto.lock(options(context)) == "FOR UPDATE"
    unlocked = Keyword.put(options(context), :lock, nil)
    assert Ledger.Ecto.lock(unlocked) == nil
  end

  defp options(%{ledger: {Ledger.Ecto, options}}), do: options

  defp event(value) do
    %FactEvent{
      kind: :subject_attribute,
      subject_ref: {:user, "11111111-1111-1111-1111-111111111111"},
      object_ref: nil,
      attribute: :clearance,
      old: nil,
      new: value,
      position: nil,
      operation_id: "22222222-2222-2222-2222-222222222222",
      at: ~U[2026-09-08 00:00:00.000000Z],
      by: Subject.library()
    }
  end

  defp published(%PolicyVersion{} = version) do
    %{event(nil) | kind: :policy_version, subject_ref: nil, attribute: nil, new: version}
  end
end
