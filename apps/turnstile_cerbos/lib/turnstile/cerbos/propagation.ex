defmodule Turnstile.Cerbos.Propagation do
  @moduledoc """
  How long a rule change takes to reach the sidecar, measured rather than
  declared.

  The sidecar reads its policies from a directory and reloads them when the
  directory changes. Nothing tells it to reload and nothing answers whether
  it has: a caller learns that a change is in force by asking a question the
  change answers differently. That interval is this adapter's
  `policy_propagation` component of revocation latency
  (`docs/reference.md` §4), and a measurement of it is a publish, then
  polling until the answer changes, then the clock.

  Two moves, so a caller can do both. Writing policy text into the
  directory and putting back what was there, which is a file operation and
  nothing more. And the measurement, which takes the publish as a function,
  runs it, and polls with `Turnstile.Test.poll/2` until the caller's
  question answers the new way. The poll interval is the floor of any
  number this produces, and the deadline is generous, because a directory
  watch is not instant.

  Nothing here asserts a number. The measurement comes back as a struct of
  milliseconds for whoever asked to record.
  """

  alias Turnstile.Test

  @schema NimbleOptions.new!(
            timeout: [
              type: :pos_integer,
              default: 30_000,
              doc: "How long to poll for the change to be in force, in milliseconds."
            ]
          )

  @enforce_keys [:total, :publish, :poll, :floor]
  defstruct [:total, :publish, :poll, :floor]

  @typedoc "Milliseconds: the whole measurement, the publish, the polling, and the poll interval under it."
  @type t :: %__MODULE__{
          total: non_neg_integer(),
          publish: non_neg_integer(),
          poll: non_neg_integer(),
          floor: pos_integer()
        }

  @doc "The schema of the options a measurement takes: #{NimbleOptions.docs(@schema)}"
  @spec options_schema() :: NimbleOptions.t()
  def options_schema, do: @schema

  @doc """
  Runs `publish`, then polls `until` for the change to be in force, and
  comes back with what the publish returned and how long each part took.
  The poll carries the deadline through, so a change that never arrives ends
  the measurement rather than waiting on it.
  """
  @spec measure((-> result), (-> term()), keyword()) :: {result, t()} when result: term()
  def measure(publish, until, options \\ []) when is_function(publish, 0) and is_function(until, 0) do
    validated = NimbleOptions.validate!(options, @schema)
    started = System.monotonic_time(:millisecond)
    published = publish.()
    at_publish = System.monotonic_time(:millisecond)
    _in_force = Test.poll(until, validated[:timeout])
    finished = System.monotonic_time(:millisecond)

    {published,
     %__MODULE__{
       total: finished - started,
       publish: at_publish - started,
       poll: finished - at_publish,
       floor: Test.poll_interval()
     }}
  end

  @doc "The measurement as the parts a report names, in milliseconds."
  @spec to_keyword(t()) :: keyword()
  def to_keyword(%__MODULE__{} = measurement) do
    [total: measurement.total, publish: measurement.publish, poll: measurement.poll, floor: measurement.floor]
  end

  @doc """
  Writes each `{path, text}` pair under the directory, where a path is
  relative to it, and comes back with what those paths held before, `nil`
  for a path that held nothing.
  """
  @spec swap!(Path.t(), [{Path.t(), String.t()}]) :: [{Path.t(), String.t() | nil}]
  def swap!(directory, files) when is_binary(directory) and is_list(files) do
    Enum.map(files, fn {path, text} -> {path, written!(Path.join(directory, path), text)} end)
  end

  @doc "Puts back what `swap!/2` came back with: the text where there was text, no file where there was none."
  @spec restore!(Path.t(), [{Path.t(), String.t() | nil}]) :: :ok
  def restore!(directory, previous) when is_binary(directory) and is_list(previous) do
    Enum.each(previous, fn {path, text} -> put_back!(Path.join(directory, path), text) end)
  end

  defp written!(full, text) do
    previous = read(full)
    File.mkdir_p!(Path.dirname(full))
    File.write!(full, text)
    previous
  end

  defp put_back!(full, nil) do
    _removed = File.rm_rf!(full)
    :ok
  end

  defp put_back!(full, text), do: File.write!(full, text)

  defp read(full) do
    case File.read(full) do
      {:ok, text} -> text
      {:error, _absent} -> nil
    end
  end
end
