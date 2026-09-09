defmodule Turnstile.Fga.Binding do
  @moduledoc """
  What `Turnstile.Fga` needs beyond the configuration entry, which carries
  the endpoint and the store alone: the mediated repo the checkpoint is read
  through, the model text the store is published from, the module that maps
  facts to tuples, who wrote and approved that model, and the guard, where
  the application has a precondition the model cannot hold.

  `bind/1` validates them and keeps them for the life of the VM, as
  `Turnstile.Config.boot!/1` keeps the configuration; `override/1` puts a
  binding in the calling process for the rest of its life, read from the
  caller and from its `$callers` chain, so a test binds a store and a model
  of its own without touching the boot binding.

  The repo is here rather than in the configuration entry because the
  checkpoint is the application's row, not the engine's: a decision names
  the position the store has been drained to, and that position is read
  where the application's own tables are. The model path is here for the
  same reason it is not the store's id: the store holds tuples under a model
  the server names by id, and the text those ids come from is the
  application's file.
  """

  alias Turnstile.Error
  alias Turnstile.Fga.Guard
  alias Turnstile.Fga.Model
  alias Turnstile.Fga.TupleMapping

  @schema NimbleOptions.new!(
            repo: [type: :atom, required: true, doc: "The mediated repo holding the checkpoint table."],
            model: [
              type: :string,
              required: true,
              doc: "The file holding the model text the store is published from."
            ],
            mapping: [
              type: :atom,
              required: true,
              doc: "The `Turnstile.Fga.TupleMapping` implementation for this application's facts."
            ],
            guard: [
              type: :atom,
              default: nil,
              doc: "The `Turnstile.Fga.Guard` every callback consults before it asks, where there is one."
            ],
            author: [type: {:or, [:string, nil]}, default: nil, doc: "Who wrote the model."],
            approval: [type: {:or, [:string, nil]}, default: nil, doc: "The approval the model carries."]
          )

  @enforce_keys [:repo, :model, :mapping]
  defstruct [:repo, :model, :mapping, :guard, :author, :approval]

  @type t :: %__MODULE__{
          repo: module(),
          model: Path.t(),
          mapping: module(),
          guard: module() | nil,
          author: String.t() | nil,
          approval: String.t() | nil
        }

  @doc "The schema of the binding's options. Fields: #{NimbleOptions.docs(@schema)}"
  @spec options_schema() :: NimbleOptions.t()
  def options_schema, do: @schema

  @doc "Validate the options into the struct."
  @spec new(keyword()) :: {:ok, t()} | {:error, Error.Invalid.t()}
  def new(options) when is_list(options) do
    with {:ok, validated} <- validate(options),
         :ok <- implements?(validated[:mapping], TupleMapping),
         :ok <- implements?(validated[:guard], Guard) do
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
      model: binding.model,
      mapping: binding.mapping,
      guard: binding.guard,
      author: binding.author,
      approval: binding.approval
    ]
  end

  @doc "The bound model as text, read from the file the binding names."
  @spec text(t()) :: {:ok, String.t()} | {:error, Error.Invalid.t()}
  def text(%__MODULE__{model: path}) do
    case File.read(path) do
      {:ok, text} -> {:ok, text}
      {:error, reason} -> {:error, invalid("#{path} could not be read: #{:file.format_error(reason)}")}
    end
  end

  @doc "The bound model as the server takes it."
  @spec compiled(t()) :: {:ok, Model.t()} | {:error, Error.Invalid.t()}
  def compiled(%__MODULE__{} = binding) do
    with {:ok, text} <- text(binding), do: Model.compile(text)
  end

  defp validate(options) do
    case NimbleOptions.validate(options, @schema) do
      {:ok, validated} -> {:ok, validated}
      {:error, %NimbleOptions.ValidationError{} = error} -> {:error, invalid(Exception.message(error))}
    end
  end

  defp implements?(nil, _behaviour), do: :ok

  defp implements?(module, behaviour) do
    if behaviour in behaviours(module) do
      :ok
    else
      {:error, invalid("#{inspect(module)} is no #{inspect(behaviour)}")}
    end
  end

  defp behaviours(module) do
    if Code.ensure_loaded?(module) do
      for {:behaviour, list} <- module.module_info(:attributes), behaviour <- list, do: behaviour
    else
      []
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
