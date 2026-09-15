defmodule ExampleFga.Population do
  @moduledoc """
  The world `ExampleFga.Infrastructure.TupleMapping` is held to: the fixture's two tenants
  and ten accounts, a document carrying a decontrol date, a banner, and a
  list of accounts, with two portions of its own, a second document carrying
  none of those, and a marking proposal on the first. The foreign program is
  closed at the end, because a purpose that has ended requires no tuple and
  is worth being in a population as much as one that does.

  Every row is written and taken away through the seam, a row at a time, so
  each is a change the marker handler sees. Rows leave children first, which
  is the order the foreign keys allow.
  """

  @behaviour Turnstile.Fga.Population

  use Boundary, top_level?: true, deps: [Ecto, Example, Example.Fixture, Turnstile.Fga]

  alias Example.Domain.AccountRole
  alias Example.Domain.Agency
  alias Example.Domain.Assignment
  alias Example.Domain.Category
  alias Example.Domain.Document
  alias Example.Domain.Marking
  alias Example.Domain.Office
  alias Example.Domain.OfficeRole
  alias Example.Domain.Portion
  alias Example.Domain.Program
  alias Example.Domain.Proposal
  alias Example.Domain.User
  alias Example.Fixture
  alias Turnstile.Fga.Population

  @exemption {:exempt, "fga population: the world a mapping is held to"}

  # Children before parents, which is the order rows leave in.
  @tables [
    Proposal,
    Portion,
    Marking,
    Document,
    OfficeRole,
    Assignment,
    AccountRole,
    User,
    Program,
    Office,
    Agency,
    Category
  ]

  # An object of each type that no row names. The two attribute types are
  # values rather than rows: a country nobody holds and an employment
  # outside the column's set.
  @absent %{"category" => "NOSUCH", "country" => "ZZ", "employment" => "none"}

  @impl Population
  def write(repo) do
    world = Fixture.world!()

    document =
      Fixture.document!(world,
        title: "controlled",
        decontrol: DateTime.shift(DateTime.utc_now(:second), day: 365),
        categories: ["PRVCY"],
        controls: [:releasable_to, :named_list],
        releasable_to: ["US", "FR"],
        list: ["frank"],
        portions: [
          %{body: "first", categories: ["CTI"], controls: [:no_foreign]},
          %{body: "second"}
        ]
      )

    _plain = Fixture.document!(world, title: "plain", program: world.foreign_program, office: world.foreign_office)
    _proposal = insert(repo, %Proposal{document_id: document.id, proposer_id: "dana", categories: ["PROPIN"]})
    _closed = Fixture.close_program!(world.foreign_program)

    :ok
  end

  @impl Population
  def clear(repo) do
    Enum.each(@tables, fn schema ->
      Enum.each(repo.all(schema, turnstile: @exemption), &delete(repo, &1))
    end)
  end

  @impl Population
  def disturb(repo) do
    assignment = repo.get_by!(Assignment, [user_id: "ann"], turnstile: @exemption)

    delete(repo, assignment)
  end

  @impl Population
  def absent(type), do: "#{type}:#{Map.get(@absent, type, 999_999)}"

  defp insert(repo, row) do
    _inserted = repo.insert!(row, turnstile: @exemption)

    :ok
  end

  defp delete(repo, row) do
    _deleted = repo.delete!(row, turnstile: @exemption)

    :ok
  end
end
