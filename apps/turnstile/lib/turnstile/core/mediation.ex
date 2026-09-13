defmodule Turnstile.Core.Mediation do
  @moduledoc false
  # The `turnstile:` option, resolved: the struct every override puts back in
  # the options in the option's place, so `prepare_query/3` and a nested call
  # Ecto makes on the caller's behalf see one shape. What the option accepts
  # is a `%Turnstile.Decision{}`, `{:exempt, reason}` with a non-empty reason,
  # or `{:exempt, :library}`.
  #
  # `carried` is the set of schemas the decision covers beyond the root: the
  # closure of the root's carried associations, filled only when the decision
  # names the root's own object type.
  #
  # Reading the option is this module's work. Reading the caller and the
  # process it ran in is `Turnstile.Adapter.Option`'s.

  alias Turnstile.Decision
  alias Turnstile.Error
  alias Turnstile.Exemption
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

  @doc """
  The error a call the seam refuses makes: the function and its arity, the
  root source, the decision's object type where one was given, the caller
  where the seam could read it, and a detail where the reason is not the
  plain one.
  """
  @spec unmediated(keyword()) :: Error.t()
  def unmediated(parts) when is_list(parts) do
    call = "Repo.#{parts[:function]}/#{parts[:arity]}"
    %Error{reason: :unmediated, detail: call <> target(parts[:schema]) <> " " <> why(parts) <> from(parts[:caller])}
  end

  @doc "A mediation with no decision and no exemption, so a refusal can name the call."
  @spec empty(call()) :: t()
  def empty(call), do: %__MODULE__{call: call, decision: nil, exemption: nil, caller: nil, carried: []}

  @doc "The value the option holds, or a raised `NimbleOptions` error."
  @spec validate!(term()) :: Decision.t() | {:exempt, String.t()} | {:exempt, :library} | t()
  def validate!(value) do
    [turnstile: value]
    |> NimbleOptions.validate!(@schema)
    |> Keyword.fetch!(:turnstile)
  end

  @doc "The mediation a library exemption makes: the library's own channel, recorded against its caller."
  @spec library(call(), root(), module() | :any) :: t()
  def library(call, root, caller) when is_atom(caller) do
    exempted(call, caller, %Exemption{on: root, caller: caller, reason: "library", kind: :library})
  end

  @doc "The mediation a declared exemption makes: the reason the caller gave, recorded against it."
  @spec declared(call(), root(), module() | :any, String.t()) :: t()
  def declared(call, root, caller, reason) when is_atom(caller) and is_binary(reason) do
    exempted(call, caller, %Exemption{on: root, caller: caller, reason: reason, kind: :declared})
  end

  @doc """
  The mediation a decision makes, with the schemas it carries beyond the
  root. A denial raises here, so no call a denial answered reaches Ecto.
  """
  @spec decided(call(), root(), Decision.t()) :: t()
  def decided(_call, _root, %Decision{verdict: :deny} = decision) do
    raise Error.denied(decision.subject, decision.operation, decision.object, decision.reason)
  end

  def decided(call, root, %Decision{} = decision) do
    %__MODULE__{call: call, decision: decision, exemption: nil, caller: nil, carried: carried(root, decision)}
  end

  @doc false
  @spec validate_option(term()) :: {:ok, term()} | {:error, String.t()}
  def validate_option(%Decision{} = decision), do: {:ok, decision}
  def validate_option({:exempt, reason} = value) when is_binary(reason) and reason != "", do: {:ok, value}
  def validate_option({:exempt, :library} = value), do: {:ok, value}
  def validate_option(%__MODULE__{} = mediation), do: {:ok, mediation}

  def validate_option(other) do
    {:error, "expected a %Turnstile.Decision{}, {:exempt, reason}, or {:exempt, :library}, got: " <> inspect(other)}
  end

  defp exempted(call, caller, %Exemption{} = exemption) do
    %__MODULE__{call: call, decision: nil, exemption: exemption, caller: caller, carried: []}
  end

  defp carried(root, %Decision{object: {type, _id}}) when is_atom(root) and not is_nil(root) do
    if Schema.object_type_of(root) == type, do: carried_closure(root), else: []
  end

  defp carried(_root, _decision), do: []

  defp target(nil), do: ""
  defp target(schema), do: " on " <> inspect(schema)

  defp why(parts) do
    case {parts[:detail], parts[:object_type]} do
      {detail, _type} when is_binary(detail) -> detail
      {nil, nil} -> "carries no decision and no exemption"
      {nil, type} -> "carries a decision for #{inspect(type)}, which does not cover it"
    end
  end

  defp from(caller) when is_atom(caller) and caller not in [nil, :any], do: " (from #{inspect(caller)})"
  defp from(_caller), do: ""

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
