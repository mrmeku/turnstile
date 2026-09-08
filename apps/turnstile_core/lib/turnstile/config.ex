defmodule Turnstile.Config do
  @moduledoc """
  The only runtime configuration the library reads, validated once at boot
  from a `NimbleOptions` schema. `boot!/1` validates and stores it;
  `resolve/0` is what the port and the seam call, and it answers with the
  boot struct under the overrides `Turnstile.Test.with_config/1` put in the
  process dictionary of the caller or of a process in its `$callers` chain.

  Fields: #{NimbleOptions.docs(Turnstile.Config.Schema.schema())}
  """

  alias Turnstile.Config.Schema
  alias Turnstile.Error

  @enforce_keys [:adapter, :ledger, :ledger_counter, :clock, :caps]
  defstruct @enforce_keys

  @type adapter :: module() | {module(), keyword()}
  @type ledger :: {module(), keyword()} | :none
  @type caps :: [batch_ids: pos_integer(), rule_bytes: pos_integer(), policy_content_bytes: pos_integer()]

  @type t :: %__MODULE__{
          adapter: adapter(),
          ledger: ledger(),
          ledger_counter: String.t(),
          clock: module(),
          caps: caps()
        }

  @doc "Validate a keyword list into the struct."
  @spec new(keyword()) :: {:ok, t()} | {:error, Error.Invalid.t() | Error.Unsupported.t()}
  def new(options) when is_list(options) do
    with {:ok, validated} <- validate(options),
         {:ok, adapter} <- validate_adapter(validated[:adapter]),
         {:ok, ledger} <- validate_ledger(validated[:ledger]),
         :ok <- check_ledger_requirement(adapter, ledger) do
      {:ok,
       %__MODULE__{
         adapter: adapter,
         ledger: ledger,
         ledger_counter: validated[:ledger_counter],
         clock: validated[:clock],
         caps: validated[:caps]
       }}
    end
  end

  @doc "`new/1`, raising the error."
  @spec new!(keyword()) :: t()
  def new!(options) when is_list(options) do
    case new(options) do
      {:ok, config} -> config
      {:error, error} -> raise error
    end
  end

  @doc "Validate once at boot and keep the struct for `resolve/0`."
  @spec boot!(keyword()) :: t()
  def boot!(options) when is_list(options) do
    config = new!(options)
    :persistent_term.put(__MODULE__, config)
    config
  end

  @doc "The boot struct under the calling process's overrides, or an error when neither exists."
  @spec resolve() :: {:ok, t()} | {:error, Error.Invalid.t() | Error.Unsupported.t()}
  def resolve do
    overrides = overrides()

    case :persistent_term.get(__MODULE__, nil) do
      %__MODULE__{} = base -> new(Keyword.merge(to_keyword(base), overrides))
      nil when overrides == [] -> {:error, %Error.Invalid{what: :config, detail: "nothing booted and no override"}}
      nil -> new(overrides)
    end
  end

  @doc "The struct as the keyword list `new/1` accepts."
  @spec to_keyword(t()) :: keyword()
  def to_keyword(%__MODULE__{} = config) do
    [
      adapter: config.adapter,
      ledger: config.ledger,
      ledger_counter: config.ledger_counter,
      clock: config.clock,
      caps: config.caps
    ]
  end

  @doc "The adapter module and its options."
  @spec adapter(t()) :: {module(), keyword()}
  def adapter(%__MODULE__{adapter: {module, options}}), do: {module, options}
  def adapter(%__MODULE__{adapter: module}) when is_atom(module), do: {module, []}

  @doc false
  @spec override_key() :: atom()
  def override_key, do: __MODULE__

  defp validate(options) do
    case NimbleOptions.validate(Keyword.put_new(options, :clock, Turnstile.Clock.System), Schema.schema()) do
      {:ok, validated} -> {:ok, validated}
      {:error, %NimbleOptions.ValidationError{} = error} -> {:error, invalid(:config, Exception.message(error))}
    end
  end

  defp validate_adapter({module, options}) when is_atom(module) and is_list(options) do
    with :ok <- implements(module, Turnstile.Adapter, :adapter),
         {:ok, options} <- validate_options(module, options, :adapter) do
      {:ok, {module, options}}
    end
  end

  defp validate_adapter(module) when is_atom(module), do: validate_adapter({module, []})

  defp validate_ledger(:none), do: {:ok, :none}

  defp validate_ledger({module, options}) when is_atom(module) and is_list(options) do
    with :ok <- implements(module, Turnstile.Ledger, :ledger),
         {:ok, options} <- validate_options(module, options, :ledger) do
      {:ok, {module, options}}
    end
  end

  defp check_ledger_requirement({adapter, _options}, :none) do
    if adapter.requires_ledger() do
      {:error, %Error.Unsupported{adapter: adapter, feature: :ledger_mode_none, note: "the adapter requires a ledger"}}
    else
      :ok
    end
  end

  defp check_ledger_requirement({_adapter, _options}, {_ledger, _ledger_options}), do: :ok

  defp implements(module, behaviour, what) do
    behaviours =
      if Code.ensure_loaded?(module) do
        :attributes
        |> module.module_info()
        |> Keyword.get_values(:behaviour)
        |> List.flatten()
      else
        []
      end

    if behaviour in behaviours do
      :ok
    else
      {:error, invalid(what, "#{inspect(module)} does not implement #{inspect(behaviour)}")}
    end
  end

  defp validate_options(module, options, what) do
    cond do
      function_exported?(module, :options_schema, 0) ->
        case NimbleOptions.validate(options, module.options_schema()) do
          {:ok, validated} -> {:ok, validated}
          {:error, error} -> {:error, invalid(what, "#{inspect(module)}: " <> Exception.message(error))}
        end

      options == [] ->
        {:ok, []}

      true ->
        {:error, invalid(what, "#{inspect(module)} takes no options, got: #{inspect(options)}")}
    end
  end

  defp invalid(what, detail), do: %Error.Invalid{what: what, detail: detail}

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
