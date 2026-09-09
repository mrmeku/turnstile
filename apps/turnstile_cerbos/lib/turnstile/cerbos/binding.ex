defmodule Turnstile.Cerbos.Binding do
  @moduledoc """
  What `Turnstile.Cerbos` needs beyond the configuration entry, which
  carries the sidecar's address alone: the mediated repo the attribute
  values are read through, the module that declares those attributes, the
  policy directory and the commit the sidecar is serving, and who wrote and
  approved that commit.

  `bind/1` validates them and keeps them for the life of the VM, as
  `Turnstile.Config.boot!/1` keeps the configuration; `override/1` puts a
  binding in the calling process for the rest of its life, read from the
  caller and from its `$callers` chain, so a test binds its own policy
  directory without touching the boot binding.

  The commit is the version identifier every decision under this binding
  names. It comes from the repository the policy files live in, so the
  application is told which commit it is serving rather than deriving one:
  a sidecar reading a directory has no opinion about history, and the
  `version` field inside a policy file is not history either, it runs
  variants side by side.
  """

  alias Turnstile.Cerbos.Attributes
  alias Turnstile.Error

  @schema NimbleOptions.new!(
            repo: [type: :atom, required: true, doc: "The mediated repo the attribute values are read through."],
            attributes: [
              type: :atom,
              required: true,
              doc: "The module that used `Turnstile.Cerbos.Attributes`."
            ],
            policies: [
              type: :string,
              required: true,
              doc: "The directory holding the policy files the sidecar is serving."
            ],
            commit: [
              type: :string,
              required: true,
              doc: "The commit of the policy repository at that directory, the version identifier."
            ],
            author: [type: {:or, [:string, nil]}, default: nil, doc: "Who wrote the commit."],
            approval: [type: {:or, [:string, nil]}, default: nil, doc: "The approval the commit carries."],
            decision_log: [
              type: {:or, [:string, nil]},
              default: nil,
              doc: "The file the sidecar writes its decision log to, which reconciliation reads."
            ]
          )

  @enforce_keys [:repo, :attributes, :policies, :commit]
  defstruct [:repo, :attributes, :policies, :commit, :author, :approval, :decision_log]

  @type t :: %__MODULE__{
          repo: module(),
          attributes: Attributes.t(),
          policies: Path.t(),
          commit: String.t(),
          author: String.t() | nil,
          approval: String.t() | nil,
          decision_log: Path.t() | nil
        }

  @doc "The schema of the binding's options."
  @spec options_schema() :: NimbleOptions.t()
  def options_schema, do: @schema

  @doc "Validate the options into the struct."
  @spec new(keyword()) :: {:ok, t()} | {:error, Error.Invalid.t()}
  def new(options) when is_list(options) do
    with {:ok, validated} <- validate(options),
         :ok <- declares?(validated[:attributes]) do
      {:ok, struct!(__MODULE__, validated)}
    end
  end

  @doc "Validate once at boot and keep the binding for `resolve/0`."
  @spec bind(keyword()) :: {:ok, t()} | {:error, Error.Invalid.t()}
  def bind(options) when is_list(options) do
    with {:ok, %__MODULE__{} = binding} <- new(options) do
      :persistent_term.put(__MODULE__, binding)
      {:ok, binding}
    end
  end

  @doc "`bind/1`, raising the error."
  @spec bind!(keyword()) :: t()
  def bind!(options) when is_list(options) do
    case bind(options) do
      {:ok, binding} -> binding
      {:error, error} -> raise error
    end
  end

  @doc "Override the binding's fields for the rest of the calling process."
  @spec override(keyword()) :: :ok
  def override(overrides) when is_list(overrides) do
    current = Process.get(__MODULE__, [])
    Process.put(__MODULE__, Keyword.merge(current, overrides))
    :ok
  end

  @doc "Override the binding's fields around a function, restoring the previous override after it."
  @spec override(keyword(), (-> result)) :: result when result: term()
  def override(overrides, fun) when is_list(overrides) and is_function(fun, 0) do
    previous = Process.get(__MODULE__, [])
    :ok = override(overrides)

    try do
      fun.()
    after
      Process.put(__MODULE__, previous)
    end
  end

  @doc "The boot binding under the calling process's overrides, or an error when neither exists."
  @spec resolve() :: {:ok, t()} | {:error, Error.Invalid.t()}
  def resolve do
    overrides = overrides()

    case :persistent_term.get(__MODULE__, nil) do
      %__MODULE__{} = base -> new(Keyword.merge(to_keyword(base), overrides))
      nil when overrides == [] -> {:error, invalid("nothing bound and no override")}
      nil -> new(overrides)
    end
  end

  @doc "The binding as the keyword list `new/1` accepts."
  @spec to_keyword(t()) :: keyword()
  def to_keyword(%__MODULE__{} = binding) do
    [
      repo: binding.repo,
      attributes: binding.attributes,
      policies: binding.policies,
      commit: binding.commit,
      author: binding.author,
      approval: binding.approval,
      decision_log: binding.decision_log
    ]
  end

  @doc "The schema of a kind, and its single primary key, or `nil` when the kind is not declared with one."
  @spec target(t(), atom()) :: {module(), atom()} | nil
  def target(%__MODULE__{attributes: attributes}, kind) when is_atom(kind) do
    case Attributes.schema_of(attributes, kind) do
      nil -> nil
      schema -> keyed(schema)
    end
  end

  # A kind whose schema has a composite key or none has no single column an
  # object identifier names, so this adapter answers nothing about it.
  defp keyed(schema) do
    case schema.__schema__(:primary_key) do
      [key] -> {schema, key}
      _none_or_composite -> nil
    end
  end

  defp validate(options) do
    case NimbleOptions.validate(options, @schema) do
      {:ok, validated} -> {:ok, validated}
      {:error, %NimbleOptions.ValidationError{} = error} -> {:error, invalid(Exception.message(error))}
    end
  end

  defp declares?(attributes) do
    if Attributes.declares?(attributes) do
      :ok
    else
      {:error, invalid("#{inspect(attributes)} did not use Turnstile.Cerbos.Attributes")}
    end
  end

  defp invalid(detail), do: %Error.Invalid{what: :binding, detail: detail}

  # The override is read from the calling process, then from each process in
  # its `$callers` chain, nearest first; the first one found wins.
  defp overrides do
    [self() | List.wrap(Process.get(:"$callers", []))]
    |> Enum.map(&overrides_of/1)
    |> Enum.find([], &(&1 != []))
  end

  defp overrides_of(pid) when pid == self(), do: Process.get(__MODULE__, [])

  defp overrides_of(pid) do
    case Process.info(pid, :dictionary) do
      {:dictionary, dictionary} -> Keyword.get(dictionary, __MODULE__, [])
      nil -> []
    end
  end
end
