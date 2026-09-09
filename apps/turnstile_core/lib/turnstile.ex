defmodule Turnstile do
  @moduledoc """
  The port: the one place an application asks whether a subject may perform
  an operation on an object, and the contracts every adapter, ledger, and
  projection implements.

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
      Adapter.Fake,
      Answer,
      Capabilities,
      Clock,
      Clock.System,
      Config,
      Decision,
      Edge,
      Environment,
      Error.Engine,
      Error.Invalid,
      Error.NotAuthorized,
      Error.Unmediated,
      Error.Unsupported,
      Exemption,
      Explanation,
      FactEvent,
      Id,
      Ledger,
      Ledger.Fold,
      Ledger.Memory,
      Object,
      PolicyVersion,
      Port,
      Projection,
      Projection.Drain,
      Projection.Drift,
      Reason,
      Repo,
      Repo.Facts,
      Repo.Mediation,
      Repo.Overrides,
      Repo.Seam,
      Repo.Surface,
      Schema,
      Schema.Fact,
      Schema.Relationship,
      Scope,
      Subject
    ]

  alias Turnstile.Decision
  alias Turnstile.Error
  alias Turnstile.Object
  alias Turnstile.Port
  alias Turnstile.Subject

  @doc "Decide for one object: the decision to hand the seam, or why not."
  @spec authorize(Subject.t(), atom(), Object.t(), Port.options()) ::
          {:ok, Decision.t()} | {:error, Error.NotAuthorized.t()}
  defdelegate authorize(subject, operation, object, opts \\ []), to: Port

  @doc "`authorize/4`, raising `Turnstile.Error.NotAuthorized` on a denial."
  @spec authorize!(Subject.t(), atom(), Object.t(), Port.options()) :: Decision.t()
  def authorize!(%Subject{} = subject, operation, %Object{} = object, opts \\ []) when is_atom(operation) do
    case Port.authorize(subject, operation, object, opts) do
      {:ok, decision} -> decision
      {:error, error} -> raise error
    end
  end

  @doc "The verdict alone for one object."
  @spec check(Subject.t(), atom(), Object.t(), Port.options()) :: boolean()
  defdelegate check(subject, operation, object, opts \\ []), to: Port

  @doc "Verdicts for many objects of one type."
  @spec batch(Subject.t(), atom(), [Object.t()], Port.options()) :: Port.verdicts()
  defdelegate batch(subject, operation, objects, opts \\ []), to: Port

  @doc "The objects the subject may perform the operation on, from a list."
  @spec filter(Subject.t(), atom(), [Object.t()], Port.options()) :: [Object.t()]
  defdelegate filter(subject, operation, objects, opts \\ []), to: Port

  @doc "The rule a row must satisfy and the decision the query carries."
  @spec scope(Subject.t(), atom(), atom(), Port.options()) :: {Ecto.Query.dynamic_expr(), Decision.t()}
  defdelegate scope(subject, operation, object_type, opts \\ []), to: Port

  @doc "What matched, where the adapter can say."
  @spec explain(Subject.t(), atom(), Object.t(), Port.options()) ::
          {:ok, Turnstile.Explanation.t(), Decision.t()} | {:error, Error.Unsupported.t()}
  defdelegate explain(subject, operation, object, opts \\ []), to: Port

  @doc "Who can do what: a rule per subject over an object type, or the allowed references per subject over a population."
  @spec review(Subject.t(), [Subject.t()], atom(), atom() | [Object.t()], Port.options()) :: Port.reviewed()
  defdelegate review(reviewer, subjects, operation, population, opts \\ []), to: Port
end
