defmodule Example.Fixture do
  @moduledoc """
  The world every scenario starts from, inserted through the seam under a
  declared exemption: two agencies, each with an office and a program;
  categories with and without implied controls; accounts holding one role
  each, so a scenario can name the account for the role it tests. Documents
  are added by the scenario through `document!/2`.

  | Account | Kind | Employment | Nationality | Holds |
  |---|---|---|---|---|
  | ann | user | federal | US | member of Alpha |
  | bob | user | contractor | US | member of Alpha |
  | carl | user | federal | FR | member of Alpha |
  | dana | user | federal | US | designator of the domestic office |
  | eve | user | federal | US | approver of the domestic office |
  | frank | user | federal | US | nothing |
  | gil | privileged | federal | US | the override permission; person gil |
  | gil-user | user | federal | US | member of Alpha; person gil |
  | hana | user | federal | US | designator of the foreign office |
  | ivan | user | federal | FR | member of the foreign program |
  """

  use Boundary, top_level?: true, deps: [Example, Ecto, Turnstile]

  import Ecto.Query, only: [from: 2]

  alias Example.Accounts
  alias Example.Agency
  alias Example.Assignment
  alias Example.Category
  alias Example.Document
  alias Example.Marking
  alias Example.Office
  alias Example.OfficeRole
  alias Example.Portion
  alias Example.Program
  alias Example.Repo
  alias Example.User
  alias Turnstile.Ledger.Fold
  alias Turnstile.Subject

  @exempt {:exempt, "fixture: the world a scenario starts from"}

  # Children before parents, which is the order rows leave in.
  @domain ~w(override_reports marking_proposals portions markings documents office_roles assignments
    account_roles users programs offices agencies categories)

  @accounts [
    {"ann", :user, :federal, "US", "ann"},
    {"bob", :user, :contractor, "US", "bob"},
    {"carl", :user, :federal, "FR", "carl"},
    {"dana", :user, :federal, "US", "dana"},
    {"eve", :user, :federal, "US", "eve"},
    {"frank", :user, :federal, "US", "frank"},
    {"gil", :privileged, :federal, "US", "gil"},
    {"gil-user", :user, :federal, "US", "gil"},
    {"hana", :user, :federal, "US", "hana"},
    {"ivan", :user, :federal, "FR", "ivan"}
  ]

  @enforce_keys [:agency, :office, :program, :foreign_agency, :foreign_office, :foreign_program]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          agency: Agency.t(),
          office: Office.t(),
          program: Program.t(),
          foreign_agency: Agency.t(),
          foreign_office: Office.t(),
          foreign_program: Program.t()
        }

  @doc "The exemption fixture writes carry."
  @spec exemption() :: {:exempt, String.t()}
  def exemption, do: @exempt

  @doc "The account ids, in the table's order."
  @spec account_ids() :: [String.t()]
  def account_ids, do: Enum.map(@accounts, fn {id, _kind, _employment, _nationality, _person} -> id end)

  @doc "Insert the world."
  @spec world!() :: t()
  def world! do
    categories!()
    {agency, office, program} = tenant!("Domestic", "US")
    {foreign_agency, foreign_office, foreign_program} = tenant!("Foreign", "FR")
    accounts!()
    Accounts.assign("ann", program.id, :member)
    Accounts.assign("bob", program.id, :member)
    Accounts.assign("carl", program.id, :member)
    Accounts.assign("gil-user", program.id, :member)
    Accounts.office_role("dana", office.id, :designator)
    Accounts.office_role("eve", office.id, :approver)
    Accounts.grant_override("gil")
    Accounts.office_role("hana", foreign_office.id, :designator)
    Accounts.assign("ivan", foreign_program.id, :member)

    %__MODULE__{
      agency: agency,
      office: office,
      program: program,
      foreign_agency: foreign_agency,
      foreign_office: foreign_office,
      foreign_program: foreign_program
    }
  end

  @doc """
  Insert a document of the world's domestic program with a banner and
  portions. Options: `title:`, `program:`, `office:`, `decontrol:`,
  `categories:`, `controls:`, `releasable_to:`, `list:`, and `portions:`,
  a list of maps with `body:` and marking fields. The banner is the union
  of the given marking and the portions'.
  """
  @spec document!(t(), keyword()) :: Document.t()
  def document!(%__MODULE__{} = world, opts \\ []) when is_list(opts) do
    program = Keyword.get(opts, :program, world.program)
    office = Keyword.get(opts, :office, world.office)

    %Document{} =
      document =
      Repo.insert!(
        %Document{
          title: Keyword.get(opts, :title, "document"),
          decontrol: opts[:decontrol] && DateTime.truncate(opts[:decontrol], :second),
          program_id: program.id,
          designating_office_id: office.id
        },
        turnstile: @exempt
      )

    portions =
      for attrs <- Keyword.get(opts, :portions, []) do
        Repo.insert!(struct!(%Portion{document_id: document.id}, attrs), turnstile: @exempt)
      end

    %{document | marking: marking!(document, opts, portions), portions: portions}
  end

  @doc "Replace a document's list of accounts, as the fixture, outside any rule."
  @spec set_list!(Document.t(), [String.t()]) :: Marking.t()
  def set_list!(%Document{id: id}, list) when is_list(list) do
    query = from(m in Marking, where: m.document_id == ^id)
    marking = Repo.one!(query, turnstile: @exempt)
    Repo.update!(Ecto.Changeset.change(marking, list: list), turnstile: @exempt)
  end

  @doc "Close a program now, as the fixture."
  @spec close_program!(Program.t()) :: Program.t()
  def close_program!(%Program{} = program) do
    now = DateTime.utc_now(:second)
    Repo.update!(Ecto.Changeset.change(program, closed_at: now), turnstile: @exempt)
  end

  @doc "The subject for an account of the world."
  @spec subject(String.t()) :: Subject.t()
  def subject(id) when is_binary(id) do
    {^id, kind, _employment, _nationality, _person} = List.keyfind!(@accounts, id, 0)
    %Subject{id: id, kind: kind}
  end

  @doc "Every account's subject."
  @spec subjects() :: [Subject.t()]
  def subjects, do: Enum.map(account_ids(), &subject/1)

  @doc "Insert an account with a nationality and an employment, holding nothing."
  @spec account!(String.t(), keyword()) :: User.t()
  def account!(id, opts \\ []) when is_binary(id) and is_list(opts) do
    Repo.insert!(
      %User{
        id: id,
        name: id,
        kind: Keyword.get(opts, :kind, :user),
        person_id: id,
        employment: Keyword.get(opts, :employment, :federal),
        nationality: Keyword.get(opts, :nationality, "US")
      },
      turnstile: @exempt
    )
  end

  @doc """
  Put back the relationships a fold holds that the tables do not, so a
  question asked now is answered from the state a replay names. Program
  assignments and office roles are the relationships the example keeps in
  rows of their own, and a revocation is the removal of one of those rows.
  Every other fact of a fold is a column of a row the replay leaves where
  it is: a marking's categories, a document's decontrol date, an account's
  nationality.
  """
  @spec restore!(Fold.t()) :: :ok
  def restore!(%Fold{facts: facts}) do
    Enum.each(facts, fn {key, value} -> restore(key, value) end)
  end

  @doc """
  Every domain table, parents before children, which is the order rows copy
  into a database that starts empty. The ledger's events are not among them:
  a copy of the rows is the state a question is asked against, and the record
  of how they got there is the ledger the copy was named from.
  """
  @spec tables() :: [String.t()]
  def tables, do: Enum.reverse(@domain)

  @doc """
  Empty every domain table and the ledger's events, and reset the counter,
  through the owner-role repo, after a committed test. The events go with
  the rows they describe: a ledger kept beside emptied tables would report
  every one of them as drift.
  """
  @spec truncate!(module()) :: :ok
  def truncate!(owner_repo) when is_atom(owner_repo) do
    tables = Enum.join(["turnstile_ledger_events" | @domain], ", ")

    _result = owner_repo.query!("TRUNCATE #{tables} RESTART IDENTITY CASCADE")
    _result = owner_repo.query!("UPDATE turnstile_ledger_counter SET position = 0 WHERE name = 'default'")
    :ok
  end

  defp restore(_key, nil), do: :ok

  defp restore({{:user, user_id}, {:program, program_id}, nil}, role) do
    if !held?(Assignment, user_id, :program_id, program_id) do
      _assignment = Accounts.assign(user_id, program_id, role)
    end

    :ok
  end

  defp restore({{:user, user_id}, {:office, office_id}, nil}, role) do
    if !held?(OfficeRole, user_id, :office_id, office_id) do
      _office_role = Accounts.office_role(user_id, office_id, role)
    end

    :ok
  end

  defp restore(_key, _value), do: :ok

  defp held?(schema, user_id, field, id) do
    query = from(row in schema, where: row.user_id == ^user_id and field(row, ^field) == ^id)
    Repo.all(query, turnstile: @exempt) != []
  end

  defp categories! do
    rows = [
      %Category{name: "PRVCY", specified: true, implied_controls: [:federal_only]},
      %Category{name: "CTI", specified: true, implied_controls: [:no_foreign]},
      %Category{name: "PROPIN", specified: false, implied_controls: [:federal_only]}
    ]

    Enum.each(rows, &Repo.insert!(&1, turnstile: @exempt))
  end

  defp tenant!(name, nationality) do
    agency = Repo.insert!(%Agency{name: name, nationality: nationality}, turnstile: @exempt)
    office = Repo.insert!(%Office{name: "#{name} office", agency_id: agency.id}, turnstile: @exempt)
    program = Repo.insert!(%Program{name: "#{name} program", office_id: office.id}, turnstile: @exempt)
    {agency, office, program}
  end

  defp accounts! do
    Enum.each(@accounts, fn {id, kind, employment, nationality, person} ->
      Repo.insert!(
        %User{id: id, name: id, kind: kind, person_id: person, employment: employment, nationality: nationality},
        turnstile: @exempt
      )
    end)
  end

  defp marking!(%Document{id: id}, opts, portions) do
    banner = Example.Controls.union([Map.new(opts) | portions])

    Repo.insert!(
      %Marking{
        document_id: id,
        categories: banner.categories,
        controls: banner.controls,
        releasable_to: banner.releasable_to,
        list: Keyword.get(opts, :list, [])
      },
      turnstile: @exempt
    )
  end
end

defmodule Example.Fixture.Clock do
  @moduledoc "A clock a test sets: `Turnstile.Test.with_config(clock: Example.Fixture.Clock)` after `set/1`."

  @behaviour Turnstile.Clock

  use Boundary, top_level?: true, deps: [Turnstile]

  @key {__MODULE__, :now}

  @doc "Set the time the calling process's port calls see."
  @spec set(DateTime.t()) :: :ok
  def set(%DateTime{} = now) do
    Process.put(@key, now)
    :ok
  end

  @impl Turnstile.Clock
  def now do
    Process.get(@key) || raise "Example.Fixture.Clock.set/1 was not called in this process"
  end
end
