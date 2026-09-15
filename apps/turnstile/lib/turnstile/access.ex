defmodule Turnstile.Access do
  @moduledoc """
  The access event: one telemetry event for each mediated read of a
  protected schema, published by the seam after the read returns, at the
  one site every query function passes through, so `get`, `one`, `all`,
  `exists?`, `aggregate`, `stream`, `preload`, and `reload` are covered
  alike. Only a read that carried a decision publishes: an exempt read, a
  read through the owner-role repo, and a raw query publish nothing.

  The payload carries what a consumer needs to write a data-access record
  without inventing a value:

  | Key | Value |
  |---|---|
  | `object_type` | the protected schema's object type |
  | `schema`, `repo` | the Ecto schema module and the repo the call went through |
  | `call` | `{name, arity}` of the repo function |
  | `activity` | `:query` for `all`, `all_by`, `stream`, and `aggregate`; `:read` for the rest |
  | `ids` | the primary keys of the root structs returned, in order |
  | `count` | how many |
  | `shape` | `:rows`, `:value` for a scalar, a boolean, a map, or a tuple, or `:stream` |
  | `subject`, `subject_kind` | from the decision the read ran under |
  | `decision_id` | the decision's id |
  | `time` | the moment from the configured clock, after the read |
  | `operation_id` | the identifier every event of one operation shares |

  A stream is published once, when it is built, with `shape: :stream` and
  no ids; the rows it yields are not evented. A `preload` names the structs
  whose associations were loaded. A schema joined into a query appears in
  the decision, not here: the event names the root schema the decision was
  for. The one measurement is `count`. The library publishes the event and
  stores nothing.
  """

  alias Turnstile.Decision
  alias Turnstile.Schema

  @event [:turnstile, :access]
  @queries [:all, :all_by, :stream, :aggregate]

  @typedoc "What the read answered with: rows of the schema, one value, or a stream not yet run."
  @type shape :: :rows | :value | :stream

  @doc "The telemetry event an access publishes, which is what a consumer attaches to."
  @spec event() :: [atom()]
  def event, do: @event

  @doc "Publish one access: the read's result under the decision it ran under, at the moment given."
  @spec publish(module(), module(), {atom(), non_neg_integer()}, term(), Decision.t(), DateTime.t()) :: :ok
  def publish(repo, schema, {name, _arity} = call, result, %Decision{} = decision, %DateTime{} = at)
      when is_atom(repo) and is_atom(schema) do
    {shape, ids} = shape(schema, result)
    {kind, _id} = decision.subject

    payload = %{
      object_type: Schema.object_type_of(schema),
      schema: schema,
      repo: repo,
      call: call,
      activity: activity(name),
      ids: ids,
      count: length(ids),
      shape: shape,
      subject: decision.subject,
      subject_kind: kind,
      decision_id: decision.id,
      time: at,
      operation_id: decision.operation_id
    }

    :telemetry.execute(@event, %{count: length(ids)}, payload)
  end

  defp activity(name) when name in @queries, do: :query
  defp activity(_name), do: :read

  defp shape(_schema, %Stream{}), do: {:stream, []}
  defp shape(_schema, fun) when is_function(fun), do: {:stream, []}

  defp shape(schema, rows) when is_list(rows),
    do: {:rows, for(%{__struct__: ^schema} = row <- rows, do: Schema.id_of(row))}

  defp shape(schema, %{__struct__: schema} = row), do: {:rows, [Schema.id_of(row)]}
  defp shape(_schema, nil), do: {:rows, []}
  defp shape(_schema, _value), do: {:value, []}
end
