defmodule Turnstile.Postgres.SettingsTest do
  use ExUnit.Case, async: true

  alias Turnstile.Environment
  alias Turnstile.Postgres.Settings
  alias Turnstile.Subject

  @at ~U[2026-09-08 12:00:00Z]

  test "four settings are always set, and every supplied fact is set under its own name" do
    settings = Settings.of(subject(), :read, environment(%{nationality: "us", reauthenticated_at: @at}))

    assert settings.pairs == [
             {"turnstile.subject_id", "acct-a"},
             {"turnstile.subject_kind", "user"},
             {"turnstile.operation", "read"},
             {"turnstile.now", "2026-09-08T12:00:00Z"},
             {"turnstile.nationality", "us"},
             {"turnstile.reauthenticated_at", "2026-09-08T12:00:00Z"}
           ]
  end

  test "a fact the caller did not supply is the empty string, and a list joins with commas" do
    settings = Settings.of(subject(), :read, environment(%{override: nil, categories: ["prvcy", "fouo"], level: 3}))
    values = Map.new(settings.pairs)

    assert values["turnstile.override"] == ""
    assert values["turnstile.categories"] == "prvcy,fouo"
    assert values["turnstile.level"] == "3"
  end

  test "a decision's time alone gives the same settings with no supplied fact" do
    assert Settings.of(subject(), :read, @at) == Settings.of(subject(), :read, environment(%{}))
  end

  test "the statement is one SELECT over set_config with a parameter pair per setting" do
    {statement, params} = Settings.statement(Settings.of(subject(), :edit, environment(%{})))

    assert statement ==
             "SELECT set_config($1, $2, true), set_config($3, $4, true), " <>
               "set_config($5, $6, true), set_config($7, $8, true)"

    assert params == [
             "turnstile.subject_id",
             "acct-a",
             "turnstile.subject_kind",
             "user",
             "turnstile.operation",
             "edit",
             "turnstile.now",
             "2026-09-08T12:00:00Z"
           ]
  end

  test "the hash covers every name and value, so a changed fact changes it" do
    read = Settings.of(subject(), :read, environment(%{}))
    edit = Settings.of(subject(), :edit, environment(%{}))

    assert Settings.hash(read) == Settings.hash(Settings.of(subject(), :read, environment(%{})))
    assert Settings.hash(read) != Settings.hash(edit)
    assert Settings.hash(read) =~ ~r/\A[0-9a-f]{64}\z/
  end

  test "what a call puts back holds the outer call's values and empties the names only it set" do
    outer = Settings.of(subject(), :read, environment(%{}))
    inner = Settings.of(%Subject{id: "acct-b", kind: :user}, :edit, environment(%{nationality: "fr"}))

    assert Settings.restored(inner, outer).pairs == [
             {"turnstile.nationality", ""},
             {"turnstile.subject_id", "acct-a"},
             {"turnstile.subject_kind", "user"},
             {"turnstile.operation", "read"},
             {"turnstile.now", "2026-09-08T12:00:00Z"}
           ]
  end

  defp subject, do: %Subject{id: "acct-a", kind: :user}

  defp environment(facts), do: %Environment{now: @at, facts: facts}
end
