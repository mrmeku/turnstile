defmodule Turnstile.Fga.Infrastructure.Store do
  @moduledoc false
  # The store as this adapter touches it: what the configuration and the
  # binding together say about it, what it holds for one object, and what it
  # is told so that it holds what the tables require.
  #
  # Every call to the server is here. The arithmetic of a difference is
  # `Turnstile.Fga.Domain.Drain`'s and is tested without a server; what is left
  # is reading a page, writing a call, and the order the two go in, which
  # needs one.
  #
  # An object is brought into step on its own: the tuples its rows require
  # are read from the tables, the tuples the store holds for it are read from
  # the server, and the difference between them is written. Nothing about a
  # change is turned into a write directly, which is why delivering the same
  # marker twice costs a read and no write.

  alias Turnstile.Config
  alias Turnstile.Error
  alias Turnstile.Fga.Binding
  alias Turnstile.Fga.Client
  alias Turnstile.Fga.Client.Page
  alias Turnstile.Fga.Client.Read
  alias Turnstile.Fga.Client.Write
  alias Turnstile.Fga.Domain.Drain
  alias Turnstile.Fga.Drift
  alias Turnstile.Fga.TupleKey

  @enforce_keys [:client, :endpoint, :store, :mapping, :repo, :batch]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          client: module(),
          endpoint: Client.endpoint(),
          store: Client.store(),
          mapping: module(),
          repo: module(),
          batch: pos_integer()
        }

  @doc """
  The store the configuration entry and the binding together describe. The
  adapter is the caller's to name: a configuration naming another adapter
  answers an error, since the store this would write is not the one
  answering questions.
  """
  @spec resolve(module()) :: {:ok, t()} | {:error, Error.t()}
  def resolve(adapter) when is_atom(adapter) do
    with {:ok, %Binding{} = binding} <- Binding.resolve(),
         {:ok, %Config{} = config} <- Config.resolve(),
         {:ok, options} <- entry(config, adapter) do
      {:ok, built(binding, options)}
    end
  end

  @doc """
  The store the configuration describes, whichever adapter it names. What a
  drain writes is the store that answers questions, and which adapter that
  is the configuration says rather than the caller, which is what lets a
  runner deliver a marker without naming an adapter of its own.
  """
  @spec configured() :: {:ok, t()} | {:error, Error.t()}
  def configured do
    with {:ok, %Config{} = config} <- Config.resolve() do
      {adapter, _options} = Config.adapter(config)

      resolve(adapter)
    end
  end

  @doc "Every object of every type the mapping names, in the order the mapping gives them."
  @spec objects(t()) :: [String.t()]
  def objects(%__MODULE__{} = store) do
    Enum.flat_map(store.mapping.object_types(), &store.mapping.objects(store.repo, &1))
  end

  @doc "Bring each object into step with what its rows require, one object at a time."
  @spec converge(t(), [String.t()]) :: :ok | {:error, Error.t()}
  def converge(%__MODULE__{} = store, objects) when is_list(objects) do
    Enum.reduce_while(objects, :ok, fn object, :ok ->
      case object(store, object) do
        :ok -> {:cont, :ok}
        {:error, %Error{} = error} -> {:halt, {:error, error}}
      end
    end)
  end

  @doc "The tuples every table requires against the tuples the store holds, as of this position."
  @spec drift(t(), non_neg_integer()) :: {:ok, Drift.t()} | {:error, Error.t()}
  def drift(%__MODULE__{} = store, position) when is_integer(position) do
    with {:ok, present} <- present(store) do
      wanted =
        store
        |> objects()
        |> Enum.flat_map(&store.mapping.tuples(store.repo, &1))
        |> MapSet.new()

      have = MapSet.new(present)

      {:ok,
       %Drift{
         missing: Drain.sorted(MapSet.difference(wanted, have)),
         extra: Drain.sorted(MapSet.difference(have, wanted)),
         checked_to: position
       }}
    end
  end

  @doc "A store of this name, carrying the bound model, for a rebuild to write into."
  @spec created(t(), String.t(), map()) :: {:ok, t()} | {:error, Error.t()}
  def created(%__MODULE__{} = store, name, model) when is_binary(name) do
    with {:ok, reference} <- store.client.create_store(store.endpoint, name),
         {:ok, _model} <- store.client.write_model(store.endpoint, reference, model) do
      {:ok, %{store | store: reference}}
    end
  end

  @doc "The tuples the store holds for one object, paged."
  @spec held(t(), String.t()) :: {:ok, [TupleKey.t()]} | {:error, Error.t()}
  def held(%__MODULE__{} = store, object) when is_binary(object) do
    [type | id] = String.split(object, ":", parts: 2)

    pages(store, %Read{object_type: type, object_id: List.first(id), limit: store.batch}, [])
  end

  @doc """
  Every tuple of every type the mapping names, which is what the store holds
  of its own: a type the mapping leaves out is a type this adapter does not
  write, and a reconcile says nothing about one.
  """
  @spec present(t()) :: {:ok, [TupleKey.t()]} | {:error, Error.t()}
  def present(%__MODULE__{} = store) do
    Enum.reduce_while(store.mapping.object_types(), {:ok, []}, fn type, {:ok, done} ->
      case pages(store, %Read{object_type: type, limit: store.batch}, []) do
        {:ok, tuples} -> {:cont, {:ok, done ++ tuples}}
        {:error, %Error{} = error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp object(%__MODULE__{} = store, object) do
    with {:ok, present} <- held(store, object) do
      {deletes, writes} = Drain.difference(store.mapping.tuples(store.repo, object), present)

      calls(store, Drain.calls(deletes, writes, store.batch))
    end
  end

  defp calls(_store, []), do: :ok

  defp calls(%__MODULE__{} = store, [%Write{} = call | rest]) do
    case store.client.write(store.endpoint, store.store, call) do
      {:ok, _count} -> calls(store, rest)
      {:error, %Error{} = error} -> {:error, error}
    end
  end

  defp pages(%__MODULE__{} = store, %Read{} = request, done) do
    case store.client.read(store.endpoint, store.store, request) do
      {:ok, %Page{continuation: nil} = page} -> {:ok, Enum.concat(Enum.reverse([page.tuples | done]))}
      {:ok, %Page{} = page} -> pages(store, %{request | continuation: page.continuation}, [page.tuples | done])
      {:error, %Error{} = error} -> {:error, error}
    end
  end

  defp built(%Binding{} = binding, options) do
    %__MODULE__{
      client: Keyword.get(options, :client, Client.Http),
      endpoint: Keyword.fetch!(options, :endpoint),
      store: Keyword.fetch!(options, :store_id),
      mapping: binding.mapping,
      repo: binding.repo,
      batch: Client.max_tuples_per_write()
    }
  end

  defp entry(%Config{} = config, adapter) do
    case Config.adapter(config) do
      {^adapter, options} -> {:ok, options}
      {other, _options} -> {:error, Error.invalid(:store, "#{inspect(other)} is the configured adapter, not this one")}
    end
  end
end
