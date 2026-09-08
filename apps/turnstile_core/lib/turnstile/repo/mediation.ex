defmodule Turnstile.Repo.Mediation do
  @moduledoc """
  The `turnstile:` option, resolved. A Repo override validates the option
  the caller passed, resolves it against the call's root source, and puts
  this struct back in the options in its place, so `prepare_query/3` and a
  nested call Ecto makes on the caller's behalf see one shape.

  The option accepts a `%Turnstile.Decision{}`, `{:exempt, reason}` with a
  non-empty reason, or `{:exempt, :library}`, the last only from a
  `Turnstile.*` caller. On an owner-role repo every call is library-exempt
  and the option is not read.

  `carried` is the set of schemas the decision covers beyond the root: the
  closure of the root's carried associations, filled only when the decision
  names the root's own object type.
  """

  alias Turnstile.Decision
  alias Turnstile.Error
  alias Turnstile.Exemption
  alias Turnstile.Repo.Caller
  alias Turnstile.Schema

  @schema NimbleOptions.new!(
            turnstile: [
              type: {:custom, __MODULE__, :validate_option, []},
              doc:
                "A `%Turnstile.Decision{}`, `{:exempt, reason}` with a non-empty reason, " <>
                  "or `{:exempt, :library}` from a `Turnstile.*` caller."
            ]
          )

  @enforce_keys [:call, :decision, :exemption, :caller, :carried]
  defstruct @enforce_keys

  @type call :: {atom(), non_neg_integer()}
  @type root :: module() | String.t() | nil

  @type t :: %__MODULE__{
          call: call(),
          decision: Decision.t() | nil,
          exemption: Exemption.t() | nil,
          caller: module() | :any | nil,
          carried: [module()]
        }

  @doc "The schema of the `turnstile:` option."
  @spec schema() :: NimbleOptions.t()
  def schema, do: @schema

  @doc """
  Resolve the option in `opts` for a call on `repo` whose root source is
  `root`. Returns the mediation, empty when no option was given, and the
  options with the struct in the option's place.
  """
  @spec resolve(module(), call(), root(), keyword()) :: {t(), keyword()}
  def resolve(repo, {name, arity} = call, root, opts) when is_atom(repo) and is_atom(name) and is_list(opts) do
    if repo.__turnstile__(:role) == :owner do
      put(library(call, root, repo), opts)
    else
      given(repo, {name, arity}, root, opts, Keyword.fetch(opts, :turnstile))
    end
  end

  @doc """
  Run `fun` with `mediation` as the ambient mediation of the process: the
  one a call with no option inside it reuses. Ecto hands a nested
  association write only the parent's `timeout`, `log`, `telemetry_event`,
  `prefix`, and `allow_stale` options, so the parent's mediation reaches
  the child this way, for the parent's own duration.
  """
  @spec with_ambient(t(), (-> result)) :: result when result: term()
  def with_ambient(%__MODULE__{} = mediation, fun) when is_function(fun, 0) do
    previous = Process.put(__MODULE__, mediation)

    try do
      fun.()
    after
      restore(previous)
    end
  end

  @doc "Whether the mediation admits a call outright: an exemption of either kind."
  @spec exempt?(t() | nil) :: boolean()
  def exempt?(%__MODULE__{exemption: %Exemption{}}), do: true
  def exempt?(_other), do: false

  @doc "The object type the decision names, or `nil`."
  @spec object_type(t() | nil) :: atom() | nil
  def object_type(%__MODULE__{decision: %Decision{object: {type, _id}}}), do: type
  def object_type(_other), do: nil

  @doc "The schemas a root's decision covers: the closure of its carried associations."
  @spec carried_closure(module()) :: [module()]
  def carried_closure(root) when is_atom(root), do: closure([root], [])

  @doc "The schema an association leads to, through `through:` chains where needed."
  @spec related(module(), atom()) :: module() | nil
  def related(schema, name) when is_atom(schema) and is_atom(name) do
    case schema.__schema__(:association, name) do
      %{related: related} -> related
      %{through: [first | rest]} -> Enum.reduce(rest, related(schema, first), &related(&2, &1))
      _other -> nil
    end
  end

  @doc "A mediation with no decision and no exemption, so a refusal can name the call."
  @spec empty(call()) :: t()
  def empty(call), do: %__MODULE__{call: call, decision: nil, exemption: nil, caller: nil, carried: []}

  @doc false
  @spec validate_option(term()) :: {:ok, term()} | {:error, String.t()}
  def validate_option(%Decision{} = decision), do: {:ok, decision}
  def validate_option({:exempt, reason} = value) when is_binary(reason) and reason != "", do: {:ok, value}
  def validate_option({:exempt, :library} = value), do: {:ok, value}
  def validate_option(%__MODULE__{} = mediation), do: {:ok, mediation}

  def validate_option(other) do
    {:error, "expected a %Turnstile.Decision{}, {:exempt, reason}, or {:exempt, :library}, got: " <> inspect(other)}
  end

  defp given(_repo, call, _root, opts, :error), do: ambient(call, opts)
  defp given(_repo, call, _root, opts, {:ok, %__MODULE__{} = nested}), do: put(%{nested | call: call}, opts)
  defp given(repo, call, root, opts, {:ok, value}), do: resolved(repo, call, root, opts, validate!(value))

  defp ambient(call, opts) do
    case Process.get(__MODULE__) do
      %__MODULE__{} = outer -> put(%{outer | call: call}, opts)
      nil -> put(empty(call), opts)
    end
  end

  defp put(%__MODULE__{} = mediation, opts), do: {mediation, Keyword.put(opts, :turnstile, mediation)}

  defp restore(nil), do: Process.delete(__MODULE__)
  defp restore(%__MODULE__{} = previous), do: Process.put(__MODULE__, previous)

  defp resolved(_repo, _call, _root, _opts, %Decision{verdict: :deny} = decision) do
    raise Error.NotAuthorized,
      subject: decision.subject,
      operation: decision.operation,
      object: decision.object,
      reason: decision.reason
  end

  defp resolved(_repo, call, root, opts, %Decision{} = decision) do
    mediation = %__MODULE__{
      call: call,
      decision: decision,
      exemption: nil,
      caller: nil,
      carried: carried(root, decision)
    }

    {mediation, Keyword.put(opts, :turnstile, mediation)}
  end

  defp resolved(repo, call, root, opts, {:exempt, :library}) do
    caller = Caller.module(repo)

    if Caller.library?(caller) do
      mediation = library(call, root, caller)
      {mediation, Keyword.put(opts, :turnstile, mediation)}
    else
      {name, arity} = call

      raise Error.Unmediated,
        function: name,
        arity: arity,
        schema: schema_of(root),
        caller: caller,
        detail: "{:exempt, :library} is accepted only from a Turnstile.* caller"
    end
  end

  defp resolved(repo, call, root, opts, {:exempt, reason}) do
    caller = Caller.module(repo)

    mediation = %__MODULE__{
      call: call,
      decision: nil,
      exemption: %Exemption{on: root, caller: caller, reason: reason, kind: :declared},
      caller: caller,
      carried: []
    }

    {mediation, Keyword.put(opts, :turnstile, mediation)}
  end

  defp library(call, root, caller) do
    %__MODULE__{
      call: call,
      decision: nil,
      exemption: %Exemption{on: root, caller: caller, reason: "library", kind: :library},
      caller: caller,
      carried: []
    }
  end

  defp validate!(value) do
    [turnstile: value]
    |> NimbleOptions.validate!(@schema)
    |> Keyword.fetch!(:turnstile)
  end

  defp carried(root, %Decision{object: {type, _id}}) when is_atom(root) and not is_nil(root) do
    if Schema.object_type_of(root) == type, do: carried_closure(root), else: []
  end

  defp carried(_root, _decision), do: []

  defp schema_of(root) when is_atom(root), do: root
  defp schema_of(_root), do: nil

  defp closure([], seen), do: Enum.reverse(seen)

  defp closure([schema | rest], seen) do
    related =
      schema
      |> Schema.carries_of()
      |> Enum.map(&related(schema, &1))
      |> Enum.reject(&(is_nil(&1) or &1 in seen or &1 in rest))

    closure(rest ++ related, [schema | seen])
  end
end
