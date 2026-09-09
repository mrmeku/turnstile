defmodule Example.Documents.BannerViolation do
  @moduledoc "A banner that would drop a portion's marking: the union of the portions is not covered."

  @enforce_keys [:document_id, :banner, :portions]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          document_id: integer(),
          banner: Example.Controls.marking(),
          portions: Example.Controls.marking()
        }
end

defmodule Example.Documents.OverrideRefused do
  @moduledoc "Why an override was refused: the account is not privileged, lacks the permission, or gave no justification."

  @enforce_keys [:reason]
  defstruct @enforce_keys

  @type t :: %__MODULE__{reason: :not_privileged | :no_permission | :no_justification}
end

defmodule Example.Documents do
  @moduledoc """
  Documents, their banners, their portions, and the audited override. Every
  read and write asks the port first and passes the decision to the seam;
  the banner invariant (C4) is enforced here at write time; the override
  (C10) is the one path that reads outside C1, under a declared exemption,
  with its own event and its report.
  """

  import Ecto.Query, only: [from: 2, where: 2]

  alias Ecto.Changeset
  alias Example.Controls
  alias Example.Document
  alias Example.Documents.BannerViolation
  alias Example.Documents.OverrideRefused
  alias Example.Marking
  alias Example.OverrideReport
  alias Example.Portion
  alias Example.Repo
  alias Turnstile.Decision
  alias Turnstile.Error
  alias Turnstile.Object
  alias Turnstile.Subject

  @banner {:exempt, "banner invariant: the portions' markings are read to check the union"}
  @override {:exempt, "audited override: the read outside C1 that C10 permits, evented and reported"}
  @override_event [:example, :override, :read]

  @typedoc "What a context function returns when the port refuses."
  @type refusal :: Error.NotAuthorized.t() | :not_found

  @doc "The operations on a document, in the order the review prints them."
  @spec operations() :: [atom()]
  def operations, do: [:read, :read_redacted, :change_marking, :set_decontrol, :decontrol, :propose_marking]

  @doc "The telemetry event an override read emits, beside the port's own."
  @spec override_event() :: [atom()]
  def override_event, do: @override_event

  @doc "Read a document with its banner, under C1 and C2."
  @spec read(Subject.t(), integer(), keyword()) :: {:ok, Document.t()} | {:error, refusal()}
  def read(%Subject{} = subject, id, opts \\ []) when is_integer(id) and is_list(opts) do
    with {:ok, decision} <- Turnstile.authorize(subject, :read, object(id), opts) do
      fetch(id, decision)
    end
  end

  @doc "Read a document under C1 alone, with the portions the subject may read and no other."
  @spec read_redacted(Subject.t(), integer(), keyword()) :: {:ok, Document.t()} | {:error, refusal()}
  def read_redacted(%Subject{} = subject, id, opts \\ []) when is_integer(id) and is_list(opts) do
    with {:ok, decision} <- Turnstile.authorize(subject, :read_redacted, object(id), opts),
         {:ok, document} <- fetch(id, decision) do
      {:ok, %{document | portions: portions(document, subject, opts)}}
    end
  end

  @doc "The documents the subject may read, under `scope`."
  @spec list(Subject.t(), keyword()) :: [Document.t()]
  def list(%Subject{} = subject, opts \\ []) when is_list(opts) do
    case Turnstile.scope(subject, :read, :document, opts) do
      {_rule, %Decision{verdict: :deny}} ->
        []

      {rule, decision} ->
        query = from(d in Document, where: ^rule, order_by: d.id, preload: :marking)
        Repo.all(query, turnstile: decision)
    end
  end

  @doc "Change a document's banner (C7, C8); refused when it would drop a portion's control (C4)."
  @spec change_marking(Subject.t(), integer(), map(), keyword()) ::
          {:ok, Marking.t()} | {:error, refusal() | BannerViolation.t()}
  def change_marking(%Subject{} = subject, id, attrs, opts \\ []) when is_integer(id) and is_map(attrs) do
    with {:ok, decision} <- Turnstile.authorize(subject, :change_marking, object(id), opts) do
      apply_marking(id, attrs, decision)
    end
  end

  @doc """
  Apply a marking to a document's banner under a decision that admits the
  document, keeping C4. The marking is written as a nested change of the
  document, because the document's decision carries its marking and no
  other decision names it.
  """
  @spec apply_marking(integer(), map(), Decision.t()) :: {:ok, Marking.t()} | {:error, BannerViolation.t()}
  def apply_marking(id, attrs, %Decision{} = decision) when is_integer(id) and is_map(attrs) do
    Repo.transaction(fn ->
      with {:ok, document} <- fetch(id, decision),
           {:ok, change} <- marking_change(document, attrs) do
        change
        |> Repo.update!(turnstile: decision)
        |> Map.fetch!(:marking)
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @doc """
  The change of a loaded document that applies a marking to its banner,
  refused when the banner would drop a portion's control (C4). The caller
  writes it under a decision that carries the document.
  """
  @spec marking_change(Document.t(), map()) :: {:ok, Changeset.t()} | {:error, BannerViolation.t()}
  def marking_change(%Document{marking: %Marking{} = marking} = document, attrs) when is_map(attrs) do
    with :ok <- covered(document.id, attrs) do
      {:ok, Changeset.put_assoc(Changeset.change(document), :marking, Marking.changeset(marking, attrs))}
    end
  end

  @doc "A document with its marking, under a mediation that admits it; `{:error, :not_found}` for no row."
  @spec fetch(integer(), Decision.t() | {:exempt, String.t()}) :: {:ok, Document.t()} | {:error, :not_found}
  def fetch(id, mediation) when is_integer(id) do
    case Repo.get(Document, id, turnstile: mediation) do
      %Document{} = document -> {:ok, Repo.preload(document, :marking, turnstile: mediation)}
      nil -> {:error, :not_found}
    end
  end

  @doc "Set a document's decontrol date (C7, C8)."
  @spec set_decontrol(Subject.t(), integer(), DateTime.t(), keyword()) :: {:ok, Document.t()} | {:error, refusal()}
  def set_decontrol(%Subject{} = subject, id, %DateTime{} = at, opts \\ []) when is_integer(id) do
    with {:ok, decision} <- Turnstile.authorize(subject, :set_decontrol, object(id), opts),
         {:ok, document} <- fetch(id, decision) do
      {:ok, Repo.update!(Changeset.change(document, decontrol: DateTime.truncate(at, :second)), turnstile: decision)}
    end
  end

  @doc "Decontrol a document now, by the port's clock (C5, C7, C8)."
  @spec decontrol(Subject.t(), integer(), keyword()) :: {:ok, Document.t()} | {:error, refusal()}
  def decontrol(%Subject{} = subject, id, opts \\ []) when is_integer(id) do
    with {:ok, decision} <- Turnstile.authorize(subject, :decontrol, object(id), opts),
         {:ok, document} <- fetch(id, decision) do
      {:ok,
       Repo.update!(Changeset.change(document, decontrol: DateTime.truncate(decision.at, :second)), turnstile: decision)}
    end
  end

  @doc """
  Change a portion's marking (C7 on the portion and on its document) and
  recompute the document's banner in the same transaction (C4).
  """
  @spec change_portion_marking(Subject.t(), integer(), map(), keyword()) ::
          {:ok, Portion.t()} | {:error, refusal()}
  def change_portion_marking(%Subject{} = subject, portion_id, attrs, opts \\ [])
      when is_integer(portion_id) and is_map(attrs) do
    with {:ok, portion_decision} <- Turnstile.authorize(subject, :change_marking, object(:portion, portion_id), opts),
         {:ok, portion} <- fetch_portion(portion_id, portion_decision),
         {:ok, decision} <- Turnstile.authorize(subject, :change_marking, object(portion.document_id), opts) do
      Repo.transaction(fn ->
        updated = Repo.update!(Portion.changeset(portion, attrs), turnstile: portion_decision)
        :ok = widen_banner(portion.document_id, decision)
        updated
      end)
    end
  end

  @doc """
  The audited override (C10): a privileged account holding the override
  permission reads a document outside C1 with a justification. The read
  emits its own event and is reported to the designating office. Nothing
  else is reachable through it.
  """
  @spec override_read(Subject.t(), integer(), String.t(), keyword()) ::
          {:ok, Document.t()} | {:error, OverrideRefused.t() | :not_found}
  def override_read(%Subject{} = subject, id, justification, opts \\ []) when is_integer(id) and is_list(opts) do
    with :ok <- override_permitted(subject, justification),
         {:ok, document} <- fetch(id, @override) do
      operation_id = Keyword.get_lazy(opts, :operation_id, &Turnstile.Id.new/0)
      report = report_override(document, subject, justification, operation_id)
      :telemetry.execute(@override_event, %{}, %{subject: Subject.to_map(subject), report: report})
      {:ok, document}
    end
  end

  @doc "The overrides reported to an office, oldest first."
  @spec override_reports(integer()) :: [OverrideReport.t()]
  def override_reports(office_id) when is_integer(office_id) do
    query = from(r in OverrideReport, where: r.office_id == ^office_id, order_by: r.id)
    Repo.all(query)
  end

  @doc "The object reference for a document id."
  @spec object(integer()) :: Object.t()
  def object(id) when is_integer(id), do: %Object{type: :document, id: id}

  @doc "The object reference for a row of a type."
  @spec object(atom(), integer()) :: Object.t()
  def object(type, id) when is_atom(type) and is_integer(id), do: %Object{type: type, id: id}

  defp covered(document_id, attrs) do
    portions = Repo.all(where(Portion, document_id: ^document_id), turnstile: @banner)
    banner = Controls.marking(attrs)
    union = Controls.union(portions)

    if Controls.covers?(banner, union) do
      :ok
    else
      {:error, %BannerViolation{document_id: document_id, banner: banner, portions: union}}
    end
  end

  defp widen_banner(document_id, decision) do
    {:ok, %Document{marking: marking} = document} = fetch(document_id, decision)
    portions = Repo.all(where(Portion, document_id: ^document_id), turnstile: @banner)
    banner = Controls.union([marking | portions])
    change = Changeset.put_assoc(Changeset.change(document), :marking, Marking.changeset(marking, banner))
    _document = Repo.update!(change, turnstile: decision)
    :ok
  end

  defp override_permitted(%Subject{kind: kind}, _justification) when kind != :privileged do
    {:error, %OverrideRefused{reason: :not_privileged}}
  end

  defp override_permitted(%Subject{}, justification) when not is_binary(justification) or justification == "" do
    {:error, %OverrideRefused{reason: :no_justification}}
  end

  defp override_permitted(%Subject{id: id}, _justification) do
    if Example.Accounts.override_permitted?(id), do: :ok, else: {:error, %OverrideRefused{reason: :no_permission}}
  end

  defp report_override(%Document{} = document, %Subject{id: user_id}, justification, operation_id) do
    Repo.insert!(%OverrideReport{
      document_id: document.id,
      office_id: document.designating_office_id,
      user_id: user_id,
      justification: justification,
      operation_id: operation_id,
      at: DateTime.utc_now(:second)
    })
  end

  # The portions the subject may read, under a Portion `scope` of its own; none under a denied scope.
  defp portions(%Document{id: id}, subject, opts) do
    case Turnstile.scope(subject, :read, :portion, opts) do
      {_rule, %Decision{verdict: :deny}} ->
        []

      {rule, decision} ->
        query = from(p in Portion, where: p.document_id == ^id, where: ^rule, order_by: p.id)
        Repo.all(query, turnstile: decision)
    end
  end

  defp fetch_portion(portion_id, decision) do
    case Repo.get(Portion, portion_id, turnstile: decision) do
      %Portion{} = portion -> {:ok, portion}
      nil -> {:error, :not_found}
    end
  end
end
