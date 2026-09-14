defmodule Turnstile.Relay.JobCase do
  @moduledoc """
  The case template a job is proved by. `use Turnstile.Relay.JobCase, job:
  MyApp.Markers, repo: MyApp.Repo, rows: MyApp.MarkersRows` defines a test
  module that holds the job to the three things a runner relies on: that a
  read answers entries above the position it was given, in position order,
  and no more of them than the limit; that positions rise and are unique, so
  a cursor holding the last position of a batch holds every position in it;
  and that a batch already delivered may be delivered again, since a pass
  that does not commit is read again.

  The template names no table. `rows:` is a `Turnstile.Relay.JobCase.Rows`:
  the module that puts rows where the job reads them, which is the one thing
  the template cannot know. The last test runs a whole pass through
  `Turnstile.Relay.drain_once/1`, so the repo needs the cursor table of
  `Turnstile.Relay.Migration`.

  Options:

  - `job:` the `Turnstile.Relay.Job` module, required.
  - `repo:` the repo the job reads and delivers through, required.
  - `rows:` the `Turnstile.Relay.JobCase.Rows` module, required.
  - `options:` the job's own options, default `[]`.
  - `name:` the runner's name in the pass, default the job module.
  - `sandbox:` a module answering `setup(repo, tags)`, called first in every
    test, for a repo that needs a checkout before the test runs. Omit it for
    a repo that needs none.
  - `written:` how many rows the setup writes, default 5.
  - `async:` default `true`.
  """

  import ExUnit.Assertions

  alias Turnstile.Relay.Cursor

  @doc false
  defmacro __using__(opts) do
    {opts, _binding} = Code.eval_quoted(opts, [], __CALLER__)

    config = %{
      job: Keyword.fetch!(opts, :job),
      repo: Keyword.fetch!(opts, :repo),
      rows: Keyword.fetch!(opts, :rows),
      options: Keyword.get(opts, :options, []),
      name: Keyword.get(opts, :name, Keyword.fetch!(opts, :job)),
      sandbox: Keyword.get(opts, :sandbox),
      written: Keyword.get(opts, :written, 5)
    }

    [preamble(config, Keyword.get(opts, :async, true)), reads(), deliveries(), pass()]
  end

  @doc false
  @spec __setup__(map(), map()) :: {:ok, keyword()}
  def __setup__(config, tags) do
    if config.sandbox, do: :ok = config.sandbox.setup(config.repo, tags)
    :ok = config.rows.write(config.repo, config.written)
    {:ok, job_case: config}
  end

  @doc false
  @spec options_accepted(map()) :: true
  def options_accepted(config) do
    assert({:ok, _validated} = NimbleOptions.validate(config.options, config.job.options_schema()))
  end

  @doc false
  @spec read_above(map()) :: true
  def read_above(config) do
    {:ok, batch} = read!(config, 0, 3)
    positions = Enum.map(batch, & &1.position)
    {:ok, rest} = read!(config, List.last(positions), 3)

    assert(length(batch) == 3)
    assert(positions == Enum.sort(positions))
    assert(Enum.all?(rest, &(&1.position > List.last(positions))))
  end

  @doc false
  @spec positions_rise(map()) :: true
  def positions_rise(config) do
    {:ok, entries} = read!(config, 0, 100)
    positions = Enum.map(entries, & &1.position)

    assert(length(positions) >= config.written)
    assert(positions == Enum.sort(positions))
    assert(positions == Enum.uniq(positions))
  end

  @doc false
  @spec read_past_the_end(map()) :: true
  def read_past_the_end(config) do
    {:ok, entries} = read!(config, 0, 100)
    last = List.last(entries).position

    assert(read!(config, last, 100) == {:ok, []})
  end

  @doc false
  @spec delivered_again(map()) :: true
  def delivered_again(config) do
    {:ok, entries} = read!(config, 0, 100)

    options = job_options(config)

    assert(config.job.deliver(config.repo, options, entries) == :ok)
    assert(config.job.deliver(config.repo, options, entries) == :ok)
  end

  @doc false
  @spec one_pass(map()) :: true
  def one_pass(config) do
    options = [name: config.name, repo: config.repo, job: config.job, job_options: config.options, batch: 100]
    {:ok, pass} = Turnstile.Relay.drain_once(options)
    {:ok, again} = Turnstile.Relay.drain_once(options)

    assert(pass.held?)
    assert(pass.delivered >= config.written)
    assert(pass.position == Cursor.position(config.repo, config.name))
    assert(again.delivered == 0)
    assert(again.position == pass.position)
  end

  # The job's own options as the job accepts them, which is what a runner
  # would hand it: the template is given what an application writes down,
  # and the defaults are filled in here as `Turnstile.Relay.Options` fills
  # them in there.
  defp job_options(config), do: NimbleOptions.validate!(config.options, config.job.options_schema())

  defp read!(config, from, limit), do: config.job.read(config.repo, job_options(config), from, limit)

  defp preamble(config, async) do
    quote do
      use ExUnit.Case, async: unquote(async)

      @job_case unquote(Macro.escape(config))

      setup tags do
        unquote(__MODULE__).__setup__(@job_case, tags)
      end
    end
  end

  defp reads do
    quote do
      test "the options the job is used with are the options its own schema accepts" do
        unquote(__MODULE__).options_accepted(@job_case)
      end

      test "a read answers entries above the position given, in position order, no more than the limit" do
        unquote(__MODULE__).read_above(@job_case)
      end

      test "positions rise and are unique, so the last of a batch stands for every one in it" do
        unquote(__MODULE__).positions_rise(@job_case)
      end

      test "a read above the last position answers nothing" do
        unquote(__MODULE__).read_past_the_end(@job_case)
      end
    end
  end

  defp deliveries do
    quote do
      test "a batch already delivered may be delivered again, since a pass that did not commit is read again" do
        unquote(__MODULE__).delivered_again(@job_case)
      end
    end
  end

  defp pass do
    quote do
      test "a pass delivers the entries above the cursor and leaves the cursor at the last of them" do
        unquote(__MODULE__).one_pass(@job_case)
      end
    end
  end
end

defmodule Turnstile.Relay.JobCase.Rows do
  @moduledoc """
  What `Turnstile.Relay.JobCase` writes a population through: the one thing
  the template cannot know, since where a job's rows live is the job's.
  """

  @doc "Write `count` rows where the job reads them, above every position already there."
  @callback write(repo :: module(), count :: pos_integer()) :: :ok
end
