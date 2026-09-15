defmodule Turnstile.Fga.Infrastructure.Settle do
  @moduledoc false
  # The drain loop, run in the calling process: pass after pass until one
  # delivers nothing. A runner in a supervision tree passes on its own
  # interval; this is the same passes without the waiting, for a caller that
  # has written facts and wants to ask about them.
  #
  # A pass that did not take the lock is a pass another node is running, and
  # a second drainer of the same cursor would deliver the same markers twice
  # for no gain, so the loop stops there.
  #
  # The count of passes is capped. A pass delivers at most one batch, so a
  # loop that keeps finding markers is a table being written faster than it
  # can be drained, and a caller waiting on that has something worse than a
  # store behind its tables.

  alias Turnstile.Error
  alias Turnstile.Fga.Binding
  alias Turnstile.Fga.Client
  alias Turnstile.Fga.Outbox
  alias Turnstile.Fga.Relay
  alias Turnstile.Fga.Relay.Pass

  @passes 1_000

  @doc "Drain until a pass delivers nothing, and answer when there is nothing left."
  @spec now() :: :ok | {:error, Error.t()}
  def now do
    with {:ok, %Binding{} = binding} <- Binding.resolve(), do: loop(runner(binding), @passes)
  end

  defp loop(options, 0) do
    {:error, Error.invalid(:outbox, "#{inspect(options[:name])} still had markers after #{@passes} passes")}
  end

  defp loop(options, left) do
    case Relay.drain_once(options) do
      {:ok, %Pass{delivered: 0}} -> :ok
      {:ok, %Pass{held?: false}} -> :ok
      {:ok, %Pass{}} -> loop(options, left - 1)
      {:error, reason} -> {:error, failure(reason)}
    end
  end

  defp runner(%Binding{} = binding) do
    [name: Outbox.runner(), repo: binding.repo, job: Outbox, batch: Client.max_tuples_per_write()]
  end

  defp failure(%Error{} = error), do: error

  defp failure(other) do
    %Error{reason: :engine_unreachable, detail: "the drain of #{inspect(Outbox.runner())} failed: #{inspect(other)}"}
  end
end
