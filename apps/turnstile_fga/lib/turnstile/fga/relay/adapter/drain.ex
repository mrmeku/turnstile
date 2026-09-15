defmodule Turnstile.Fga.Relay.Adapter.Drain do
  @moduledoc false
  # One pass: take the lock, read a batch above the cursor, deliver it,
  # advance the cursor, commit. Everything but the moment the pass finished
  # happens inside one transaction, so what the cursor says was delivered is
  # what a delivery that returned put out, and a delivery that did not
  # return leaves the cursor where it was.
  #
  # A failure the job reports rolls the transaction back through
  # `c:Ecto.Repo.rollback/1`, which carries the job's own term out as the
  # value of the pass. An exception is turned into the same kind of value
  # here rather than left to travel: this is where a runner meets the
  # database, and a database that is unreachable is a pass that failed, not
  # a process that must die. The term is carried and never read, so no
  # driver is named.
  #
  # The moment on the pass comes from the clock the runner was configured
  # with, read once the transaction has returned, so a test that stubs the
  # clock reads its own time and nothing here asks the system for one.

  alias Turnstile.Fga.Relay.Adapter.Lock
  alias Turnstile.Fga.Relay.Cursor
  alias Turnstile.Fga.Relay.Entry
  alias Turnstile.Fga.Relay.Pass

  @event [:turnstile, :relay, :pass]

  @doc "The event every pass emits, whether it delivered, stepped aside, or failed."
  @spec event() :: [atom()]
  def event, do: @event

  @doc "Run one pass with validated options and answer what it did."
  @spec once(keyword()) :: {:ok, Pass.t()} | {:error, term()}
  def once(options) when is_list(options) do
    result = reported(attempted(options), options)
    :ok = emit(result, options)

    result
  end

  defp attempted(options) do
    options[:repo].transaction(fn -> pass(options) end, timeout: options[:timeout])
  rescue
    exception -> {:error, exception}
  end

  defp pass(options) do
    if Lock.taken?(options[:repo], options[:name]) do
      drained(options, Cursor.position(options[:repo], options[:name]))
    else
      {:aside, Cursor.position(options[:repo], options[:name])}
    end
  end

  defp drained(options, from) do
    case options[:job].read(options[:repo], options[:job_options], from, options[:batch]) do
      {:ok, []} -> {:held, 0, from}
      {:ok, entries} -> delivered(options, entries)
      {:error, reason} -> options[:repo].rollback(reason)
    end
  end

  defp delivered(options, entries) do
    case options[:job].deliver(options[:repo], options[:job_options], entries) do
      :ok -> advanced(options, entries)
      {:error, reason} -> options[:repo].rollback(reason)
    end
  end

  defp advanced(options, entries) do
    %Entry{position: position} = List.last(entries)
    :ok = Cursor.advance(options[:repo], options[:name], position)

    {:held, length(entries), position}
  end

  defp reported({:ok, {:held, delivered, position}}, options), do: {:ok, finished(options, true, delivered, position)}
  defp reported({:ok, {:aside, position}}, options), do: {:ok, finished(options, false, 0, position)}
  defp reported({:error, reason}, _options), do: {:error, reason}

  defp finished(options, held?, delivered, position) do
    %Pass{
      name: options[:name],
      held?: held?,
      delivered: delivered,
      position: position,
      more?: delivered == options[:batch],
      at: options[:clock].()
    }
  end

  defp emit({:ok, %Pass{} = pass}, options) do
    :telemetry.execute(@event, %{delivered: pass.delivered, position: pass.position}, metadata(options, %{pass: pass}))
  end

  defp emit({:error, reason}, options) do
    :telemetry.execute(@event, %{delivered: 0}, metadata(options, %{error: reason}))
  end

  defp metadata(options, what), do: Map.merge(what, %{name: options[:name], job: options[:job]})
end
