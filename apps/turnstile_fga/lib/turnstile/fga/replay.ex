defmodule Turnstile.Fga.Replay do
  @moduledoc """
  A past state in a server that is thrown away, and a stored decision asked
  again against it.

  Replaying on this adapter costs more than replaying on one whose working
  state is the application's tables, because the state has to be loaded: the
  ledger is folded to the position the decision names, the mapping turns that
  fold into tuples, and the tuples are written into a server the caller
  raised with the in-memory datastore. What is folded to is the applied
  position rather than the head, since the applied position is the state the
  engine answered from.

  The model is the text the policy-version event carries, published into the
  throwaway store. The id it comes back with is that store's own and is not
  the id the decision names, because an id belongs to the store that issued
  it. What the two share is the text, and the ledger's version event carries
  the digest of the text, so a caller comparing a replayed answer with a
  stored one compares texts and verdicts rather than ids.

  Nothing here reads the application's tables, so state that moved since the
  decision cannot reach the answer. What comes back is the answer that state
  and those rules give to that question, for the caller to set beside the
  answer the record holds.
  """

  alias Turnstile.Answer
  alias Turnstile.Decision
  alias Turnstile.Environment
  alias Turnstile.Error
  alias Turnstile.Fga.Client
  alias Turnstile.Fga.Client.Write
  alias Turnstile.Fga.Decide
  alias Turnstile.Fga.Model
  alias Turnstile.Ledger.Fold
  alias Turnstile.Ledger.Reader
  alias Turnstile.Object

  @schema NimbleOptions.new!(
            client: [type: :atom, required: true, doc: "The `Turnstile.Fga.Client` implementation."],
            endpoint: [
              type: :any,
              required: true,
              doc: "The throwaway server the state is loaded into, raised and stopped by the caller."
            ],
            store_name: [type: :string, default: "turnstile-replay", doc: "The name the throwaway store is given."],
            model: [
              type: :string,
              required: true,
              doc: "The model text of the version in force at the cut, as the policy-version event carries it."
            ],
            mapping: [type: :atom, required: true, doc: "The `Turnstile.Fga.TupleMapping` the fold is read through."],
            ledger: [
              type: {:tuple, [:atom, :keyword_list]},
              required: true,
              doc: "The ledger as `{module, options}`, read through `Turnstile.Ledger.Reader`."
            ],
            to: [
              type: :non_neg_integer,
              required: true,
              doc: "The position to fold to: a decision's applied position, since that is what the engine saw."
            ],
            batch: [type: :pos_integer, doc: "How many tuples one write carries. Defaults to what one call may carry."]
          )

  @enforce_keys [:client, :endpoint, :store, :model, :position]
  defstruct @enforce_keys

  @typedoc "A throwaway store with a past state in it, and the model that state is asked under."
  @type t :: %__MODULE__{
          client: module(),
          endpoint: Client.endpoint(),
          store: Client.store(),
          model: Client.model(),
          position: non_neg_integer()
        }

  @doc "The schema of the options a build takes. Fields: #{NimbleOptions.docs(@schema)}"
  @spec options_schema() :: NimbleOptions.t()
  def options_schema, do: @schema

  @doc """
  A store of its own on the throwaway server, the model published into it,
  and the fold to the position written in as tuples.
  """
  @spec build(keyword()) :: {:ok, t()} | {:error, Error.Invalid.t() | Error.Engine.t()}
  def build(options) when is_list(options) do
    with {:ok, valid} <- validated(options),
         {:ok, compiled} <- Model.compile(valid[:model]),
         {:ok, replay} <- stored(valid, compiled) do
      filled(valid, replay)
    end
  end

  @doc """
  The answer the loaded state gives to the question a stored decision holds,
  under the environment the caller states. The environment defaults to the
  moment of the decision and no facts, which is what a question that reads no
  caller-supplied fact was asked under.
  """
  @spec ask(t(), Decision.t(), Environment.t() | nil) :: {:ok, Answer.t()} | {:error, Error.Engine.t()}
  def ask(%__MODULE__{} = replay, %Decision{} = decision, environment \\ nil) do
    {type, id} = decision.object

    with {:ok, entry} <- entry(replay, environment || %Environment{now: decision.at}) do
      Decide.one(entry, decision.subject, decision.operation, %Object{type: type, id: id})
    end
  end

  # A store of its own with the model in it, which is what a write is
  # validated against.
  defp stored(valid, compiled) do
    with {:ok, store} <- valid[:client].create_store(valid[:endpoint], valid[:store_name]),
         {:ok, model} <- valid[:client].write_model(valid[:endpoint], store, compiled) do
      {:ok, built(valid, store, model)}
    end
  end

  defp filled(valid, %__MODULE__{} = replay) do
    with {:ok, tuples} <- required(valid) do
      loaded(replay, tuples, valid[:batch])
    end
  end

  defp validated(options) do
    # The default is the client's to state, so it is read here rather than in
    # the schema, as the projector reads it.
    filled = Keyword.put_new(options, :batch, Client.max_tuples_per_write())

    case NimbleOptions.validate(filled, @schema) do
      {:ok, valid} -> {:ok, valid}
      {:error, error} -> {:error, %Error.Invalid{what: :replay, detail: Exception.message(error)}}
    end
  end

  defp built(valid, store, model) do
    %__MODULE__{
      client: valid[:client],
      endpoint: valid[:endpoint],
      store: store,
      model: model,
      position: valid[:to]
    }
  end

  defp entry(%__MODULE__{} = replay, %Environment{} = environment) do
    options = [
      endpoint: replay.endpoint,
      store_id: replay.store,
      model_id: replay.model,
      client: replay.client
    ]

    with {:ok, entry} <- Decide.entry(options, :replay, environment) do
      {:ok, Decide.applied(entry, replay.position)}
    end
  end

  # The objects the events up to the cut can have changed, and the tuples the
  # fold of those events requires of each. The same two questions the drain
  # asks, over a fold that stops rather than one that is current.
  defp required(valid) do
    with {:ok, events} <- Reader.all(valid[:ledger]) do
      kept = Enum.filter(events, &(is_integer(&1.position) and &1.position <= valid[:to]))
      fold = Fold.fold(kept)
      mapping = valid[:mapping]
      objects = Enum.uniq(Enum.flat_map(kept, &mapping.touched(fold, &1)))

      {:ok, Enum.flat_map(objects, &mapping.tuples(fold, &1))}
    end
  end

  defp loaded(%__MODULE__{} = replay, tuples, batch) do
    step = fn chunk, :ok -> written(replay, chunk) end

    case Enum.reduce_while(Enum.chunk_every(tuples, batch), :ok, step) do
      :ok -> {:ok, replay}
      {:error, error} -> {:error, error}
    end
  end

  defp written(%__MODULE__{} = replay, chunk) do
    case replay.client.write(replay.endpoint, replay.store, %Write{deletes: [], writes: chunk}) do
      {:ok, _count} -> {:cont, :ok}
      {:error, error} -> {:halt, {:error, error}}
    end
  end
end
