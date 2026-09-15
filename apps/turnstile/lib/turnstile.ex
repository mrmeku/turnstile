defmodule Turnstile do
  @moduledoc """
  The port: the one place an application asks whether a subject may perform
  an operation on an object, and the contract every adapter implements.

  This module is the top-layer boundary. Everything under `Turnstile` that is
  not `Turnstile.Test` or `Turnstile.Conformance` belongs to it, and it may
  reach `Ecto` and `NimbleOptions` and nothing from `ecto_sql` or `postgrex`:
  the port decides, it does not query.
  """

  use Boundary,
    deps: [Ecto, NimbleOptions],
    check: [apps: [:ecto_sql, :postgrex]],
    exports: [
      Adapter,
      Adapter.Overrides,
      Adapter.Seam,
      Answer,
      Change,
      Config,
      Core.Surface,
      Decision,
      Error,
      Exemption,
      Id,
      PolicyVersion,
      Port,
      Repo,
      Schema,
      Schema.Fact,
      Schema.Relationship
    ]

  alias Turnstile.Decision
  alias Turnstile.Error
  alias Turnstile.Port

  @typedoc """
  What the subject asks about: an object type and an id. A decision over a
  whole type, which `scope/4` makes, carries `nil` for the id.
  """
  @type object :: {atom(), Turnstile.Id.t() | nil}

  @typedoc """
  Under what conditions the subject asks: the facts only the caller knows,
  by name, with `now` from the configured clock beside them. The port
  stamps `now`, so a decider reads the moment of the request from the
  environment rather than from a clock of its own.
  """
  @type environment :: %{required(:now) => DateTime.t(), optional(atom()) => term()}

  @typedoc "A person, software acting alone, or a person who can change the system."
  @type subject_kind :: :user | :non_person_entity | :privileged

  @typedoc """
  Who is asking: a kind and an account id. The kind travels with every
  decision record, and a kind the port does not know is refused.
  """
  @type subject :: {subject_kind(), Turnstile.Id.t()}

  @doc "Decide for one object: the decision to hand the seam, or why not."
  @spec authorize(subject(), atom(), object(), Port.options()) ::
          {:ok, Decision.t()} | {:error, Error.t()}
  defdelegate authorize(subject, operation, object, opts \\ []), to: Port

  @doc "`authorize/4`, raising `Turnstile.Error` on a denial."
  @spec authorize!(subject(), atom(), object(), Port.options()) :: Decision.t()
  def authorize!({_kind, _account} = subject, operation, {_type, _id} = object, opts \\ []) when is_atom(operation) do
    case Port.authorize(subject, operation, object, opts) do
      {:ok, decision} -> decision
      {:error, error} -> raise error
    end
  end

  @doc "The verdict alone for one object."
  @spec check(subject(), atom(), object(), Port.options()) :: boolean()
  defdelegate check(subject, operation, object, opts \\ []), to: Port

  @doc "Verdicts for many objects of one type."
  @spec batch(subject(), atom(), [object()], Port.options()) :: Port.verdicts()
  defdelegate batch(subject, operation, objects, opts \\ []), to: Port

  @doc "The objects the subject may perform the operation on, from a list."
  @spec filter(subject(), atom(), [object()], Port.options()) :: [object()]
  defdelegate filter(subject, operation, objects, opts \\ []), to: Port

  @doc "The rule a row must satisfy and the decision the query carries."
  @spec scope(subject(), atom(), atom(), Port.options()) :: {Ecto.Query.dynamic_expr(), Decision.t()}
  defdelegate scope(subject, operation, object_type, opts \\ []), to: Port

  @doc "The answer with what produced it on `meta`, where the adapter can say."
  @spec explain(subject(), atom(), object(), Port.options()) ::
          {:ok, Turnstile.Answer.t(), Decision.t()} | {:error, Error.t()}
  defdelegate explain(subject, operation, object, opts \\ []), to: Port

  @doc "Who can do what: a rule per subject over an object type, or the allowed references per subject over a population."
  @spec review(subject(), [subject()], atom(), atom() | [object()], Port.options()) :: Port.reviewed()
  defdelegate review(reviewer, subjects, operation, population, opts \\ []), to: Port
end
