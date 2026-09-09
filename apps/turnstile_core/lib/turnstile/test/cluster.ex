defmodule Turnstile.Test.Cluster do
  @moduledoc """
  One ephemeral Postgres cluster per `mix test` run, and per schema dump.

  `start/1` runs `initdb` into `tmp/pg-<random>/` under the current
  directory, starts the server on a unix socket in that directory with no TCP
  listener, creates the two roles and two databases the test tiers use, runs
  the caller's migrations on each database as the owner role through the
  function the caller passes, then configures and starts the caller's repos.
  The cluster stops and its directory is removed when the suite ends, so a
  VM that runs several suites in turn, the umbrella root's `mix test`,
  starts each app's cluster afresh; a run that is no suite, a schema dump's,
  stops it at VM exit. `start/1` also defines `Turnstile.Test.Clock.Mock`,
  the `Mox` mock of `Turnstile.Clock` that the conformance template sets per
  test, once per VM.

  Roles: `turnstile_owner` (owns every table, runs migrations) and
  `turnstile_app` (`NOBYPASSRLS`, what the application connects as).
  Databases: `turnstile_test` (sandboxed tier) and `turnstile_committed`
  (committed tier). Everything here goes through `psql`, `initdb`, and
  `pg_ctl`, so this module needs `ecto` and nothing from `ecto_sql`; the
  sandbox mode is the caller's to set.
  """

  alias Turnstile.Test.Clock.Mock

  @owner "turnstile_owner"
  @app "turnstile_app"
  @databases [sandboxed: "turnstile_test", committed: "turnstile_committed"]
  @initdb_user "postgres"

  # The host's libpq environment must not redirect any tool to another server.
  @cmd_opts [
    stderr_to_stdout: true,
    env: Enum.map(~w(PGHOST PGHOSTADDR PGPORT PGUSER PGPASSWORD PGDATABASE PGSERVICE PGOPTIONS PGSSLMODE), &{&1, nil})
  ]

  @repo_schema NimbleOptions.new!(
                 role: [type: {:in, [:app, :owner]}, required: true, doc: "Which role the repo connects as."],
                 database: [
                   type: {:in, [:sandboxed, :committed]},
                   required: true,
                   doc: "Which database the repo connects to."
                 ],
                 pool: [type: :atom, doc: "A pool module to put in the repo's config, such as the SQL sandbox."],
                 pool_size: [type: :pos_integer, default: 10]
               )

  @schema NimbleOptions.new!(
            otp_app: [type: :atom, required: true, doc: "The application whose env receives each repo's config."],
            repos: [
              type: {:list, {:custom, __MODULE__, :validate_repo, []}},
              required: true,
              doc: "`{RepoModule, role: :app | :owner, database: :sandboxed | :committed}` per repo to start."
            ],
            migrate: [
              type: {:fun, 1},
              required: true,
              doc: "Called once per database with an owner-role repo whose dynamic instance points at that database."
            ]
          )

  @enforce_keys [:dir, :socket_dir, :data_dir, :log_file, :repos]
  defstruct [:supervisor | @enforce_keys]

  @type t :: %__MODULE__{
          dir: Path.t(),
          socket_dir: Path.t(),
          data_dir: Path.t(),
          log_file: Path.t(),
          repos: [module()],
          supervisor: pid() | nil
        }

  @type tier :: :sandboxed | :committed
  @type role :: :app | :owner

  @doc "Starts the cluster and the repos. Raises on any failure. Options: #{NimbleOptions.docs(@schema)}"
  @spec start(keyword()) :: t()
  def start(opts) when is_list(opts) do
    opts = NimbleOptions.validate!(opts, @schema)
    cluster = new(opts)
    File.mkdir_p!(cluster.dir)
    stop_with_suite()
    initdb!(cluster)
    pg_ctl!(cluster, ["start"])
    create_roles_and_databases!(cluster)
    Enum.each(@databases, fn {_tier, database} -> migrate!(cluster, opts, database) end)
    configure_repos!(cluster, opts)
    cluster = %{cluster | supervisor: start_repos!(opts)}
    :persistent_term.put(__MODULE__, [cluster | registered()])
    define_mock()
    cluster
  end

  @doc "Stops the server and removes the directory. Safe to call twice."
  @spec stop(t()) :: :ok
  def stop(%__MODULE__{} = cluster) do
    if is_pid(cluster.supervisor) and Process.alive?(cluster.supervisor), do: Supervisor.stop(cluster.supervisor)
    {_output, _status} = System.cmd("pg_ctl", ["-D", cluster.data_dir, "-m", "immediate", "stop"], @cmd_opts)
    File.rm_rf!(cluster.dir)
    :persistent_term.put(__MODULE__, List.delete(registered(), cluster))
    :ok
  end

  @doc "Stops every cluster started in this VM; registered with `System.at_exit/1`."
  @spec stop_all(term()) :: :ok
  def stop_all(_status), do: Enum.each(registered(), &stop/1)

  @doc "The most recently started cluster, for tests that inspect it."
  @spec info() :: t()
  def info, do: hd(registered())

  @doc "The database name for a tier."
  @spec database(tier()) :: String.t()
  def database(tier) when tier in [:sandboxed, :committed], do: Keyword.fetch!(@databases, tier)

  @doc "The role name for a role."
  @spec role(role()) :: String.t()
  def role(:app), do: @app
  def role(:owner), do: @owner

  @doc "Connection options for a role and tier, as Postgrex and Ecto accept them."
  @spec connection(t(), role(), tier()) :: keyword()
  def connection(%__MODULE__{} = cluster, role, tier) when role in [:app, :owner] and tier in [:sandboxed, :committed] do
    [socket_dir: cluster.socket_dir, username: role(role), database: database(tier)]
  end

  @doc "Runs a SQL statement through `psql` as the superuser. Raises on failure."
  @spec psql!(t(), String.t(), String.t()) :: String.t()
  def psql!(%__MODULE__{} = cluster, database, statement) when is_binary(database) and is_binary(statement) do
    run!(
      "psql",
      ["-h", cluster.socket_dir, "-U", @initdb_user, "-d", database, "-v", "ON_ERROR_STOP=1", "-Atc", statement],
      cluster
    )
  end

  @doc false
  @spec validate_repo(term()) :: {:ok, {module(), keyword()}} | {:error, String.t()}
  def validate_repo({repo, config}) when is_atom(repo) and is_list(config) do
    case NimbleOptions.validate(config, @repo_schema) do
      {:ok, config} -> {:ok, {repo, config}}
      {:error, error} -> {:error, "#{inspect(repo)}: #{Exception.message(error)}"}
    end
  end

  def validate_repo(other), do: {:error, "expected {RepoModule, keyword}, got: #{inspect(other)}"}

  defp random_suffix do
    Base.url_encode64(:crypto.strong_rand_bytes(8), padding: false)
  end

  defp initdb!(cluster) do
    run!(
      "initdb",
      ["-D", cluster.data_dir, "--auth=trust", "--username=#{@initdb_user}", "--no-sync", "-E", "UTF8", "--no-locale"],
      cluster
    )
  end

  # No TCP listener: only the socket in the cluster directory. Durability is
  # off because the cluster lives for one test run and is deleted afterwards.
  defp pg_ctl!(cluster, args) do
    server_options =
      Enum.join(
        [
          "-k #{cluster.socket_dir}",
          "-c listen_addresses=''",
          "-c fsync=off",
          "-c synchronous_commit=off",
          "-c full_page_writes=off",
          "-c log_min_messages=warning"
        ],
        " "
      )

    run!("pg_ctl", ["-D", cluster.data_dir, "-l", cluster.log_file, "-w", "-o", server_options] ++ args, cluster)
  end

  defp run!(program, args, cluster) do
    case System.cmd(program, args, @cmd_opts) do
      {output, 0} ->
        output

      {output, status} ->
        log = if File.exists?(cluster.log_file), do: File.read!(cluster.log_file), else: ""
        raise "#{program} #{Enum.join(args, " ")} exited #{status}:\n#{output}\n#{log}"
    end
  end

  defp create_roles_and_databases!(cluster) do
    statements =
      ["CREATE ROLE #{@owner} LOGIN", "CREATE ROLE #{@app} LOGIN NOBYPASSRLS"] ++
        Enum.map(@databases, fn {_tier, database} -> "CREATE DATABASE #{database} OWNER #{@owner}" end)

    Enum.each(statements, &psql!(cluster, "postgres", &1))
  end

  # Migrations run through the first owner-role repo, pointed at each database
  # in turn with a dynamic instance. The repo's static instance starts later.
  defp migrate!(cluster, opts, database) do
    case Enum.find(opts[:repos], fn {_repo, config} -> config[:role] == :owner end) do
      nil ->
        :ok

      {repo, _config} ->
        {:ok, pid} =
          repo.start_link(name: nil, socket_dir: cluster.socket_dir, username: @owner, database: database, pool_size: 2)

        previous = repo.put_dynamic_repo(pid)

        try do
          :ok = opts[:migrate].(repo)
        after
          repo.put_dynamic_repo(previous)
          Supervisor.stop(pid)
        end
    end
  end

  # Repo config lands in the application env before any repo starts, which
  # is the one place Application.put_env is allowed: boot, not a test.
  defp configure_repos!(cluster, opts) do
    Enum.each(opts[:repos], fn {repo, config} ->
      pool = if config[:pool], do: [pool: config[:pool]], else: []

      Application.put_env(
        opts[:otp_app],
        repo,
        connection(cluster, config[:role], config[:database]) ++ [pool_size: config[:pool_size]] ++ pool
      )
    end)
  end

  defp new(opts) do
    dir = Path.join([File.cwd!(), "tmp", "pg-" <> random_suffix()])

    %__MODULE__{
      dir: dir,
      socket_dir: dir,
      data_dir: Path.join(dir, "data"),
      log_file: Path.join(dir, "postgres.log"),
      repos: Enum.map(opts[:repos], &elem(&1, 0))
    }
  end

  defp registered, do: :persistent_term.get(__MODULE__, [])

  # Registered once per VM. Remote captures, not closures: coverage
  # recompiles this module and a closure from the old code would be invalid
  # by the time the callbacks run.
  defp stop_with_suite do
    if !:persistent_term.get({__MODULE__, :callbacks}, false) do
      _loaded = Application.load(:ex_unit)
      ExUnit.after_suite(&__MODULE__.stop_all/1)
      System.at_exit(&__MODULE__.stop_all/1)
      :persistent_term.put({__MODULE__, :callbacks}, true)
    end
  end

  defp define_mock do
    if !Code.ensure_loaded?(Mock) do
      Mox.defmock(Mock, for: Turnstile.Clock)
    end
  end

  # Unnamed, so a schema dump can start its own cluster inside a test run.
  defp start_repos!(opts) do
    children = Enum.map(opts[:repos], fn {repo, _config} -> repo end)
    {:ok, pid} = Supervisor.start_link(children, strategy: :one_for_one)
    pid
  end
end
