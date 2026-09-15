defmodule Turnstile.Fga.Relay.Options do
  @moduledoc """
  The options one runner takes, and the validation every entry point runs
  them through. The job's own options are validated by the job's
  `c:Turnstile.Fga.Relay.Job.options_schema/0`, so a job's mistake is reported
  where the runner is configured rather than on the first pass.

  A name is an atom, because it is a name the application writes down: it is
  the row the cursor is kept in, the advisory lock a pass takes, and, unless
  `register:` says otherwise, what the runner's process is registered under.
  """

  @schema NimbleOptions.new!(
            name: [
              type: :atom,
              required: true,
              doc: "What this runner is called, in the cursor table, in the lock, and as a process."
            ],
            repo: [type: :atom, required: true, doc: "The Ecto repo the cursor and the rows are read through."],
            job: [type: :atom, required: true, doc: "The `Turnstile.Fga.Relay.Job` module."],
            job_options: [
              type: :keyword_list,
              default: [],
              doc: "The job's own options, validated by its `c:Turnstile.Fga.Relay.Job.options_schema/0`."
            ],
            batch: [type: :pos_integer, default: 100, doc: "The most entries one pass reads and delivers."],
            idle: [
              type: :pos_integer,
              default: 1_000,
              doc: "Milliseconds before the next pass when there was nothing to do."
            ],
            backoff: [
              type: :pos_integer,
              default: 1_000,
              doc: "Milliseconds before the pass that follows a failure, doubling with each."
            ],
            backoff_max: [type: :pos_integer, default: 30_000, doc: "The longest a doubling backoff waits."],
            first: [type: :non_neg_integer, doc: "Milliseconds before the first pass; the idle interval when absent."],
            timeout: [type: :timeout, default: 30_000, doc: "The timeout of the transaction one pass runs in."],
            clock: [
              type: {:fun, 0},
              default: &DateTime.utc_now/0,
              doc: "The zero-arity function a pass reads the moment it finished from."
            ],
            register: [
              type: :boolean,
              default: true,
              doc: "Whether the runner's process is registered under its name. A test starts one unregistered."
            ]
          )

  @doc "The schema itself, for the documentation an adopter reads and for a test to assert a default from."
  @spec schema() :: NimbleOptions.t()
  def schema, do: @schema

  @doc "Validate a runner's options, and the job's options with them. Raises what is wrong with either."
  @spec validate!(keyword()) :: keyword()
  def validate!(options) when is_list(options) do
    options = NimbleOptions.validate!(options, @schema)
    job_options = NimbleOptions.validate!(options[:job_options], options[:job].options_schema())

    Keyword.put(options, :job_options, job_options)
  end
end
