defmodule Turnstile.Test.Cluster do
  @moduledoc """
  One ephemeral Postgres cluster per `mix test` run.

  `start/1` runs `initdb` into `tmp/pg-<random>/` under the current directory,
  starts the server on a unix socket in that directory with no TCP listener,
  creates the two roles and two databases the test tiers use, runs the caller's
  migrations on each database as the owner role, then starts and configures the
  caller's repos. The cluster stops and its directory is removed when the VM exits.

  Roles: `turnstile_owner` (owns every table, runs migrations) and
  `turnstile_app` (`NOBYPASSRLS`, what the application connects as).
  Databases: `turnstile_test` (sandboxed tier) and `turnstile_committed`
  (committed tier).
  """

  alias Ecto.Adapters.SQL.Sandbox

  @enforce_keys [:dir, :socket_dir, :data_dir, :log_file, :repos]
  defstruct [:dir, :socket_dir, :data_dir, :log_file, :repos]

  @type t :: %__MODULE__{
          dir: Path.t(),
          socket_dir: Path.t(),
          data_dir: Path.t(),
          log_file: Path.t(),
          repos: [module()]
        }

  @owner "turnstile_owner"
  @app "turnstile_app"
  @databases %{sandboxed: "turnstile_test", committed: "turnstile_committed"}
  @initdb_user "postgres"

  @repo_schema NimbleOptions.new!(
                 role: [type: {:in, [:app, :owner]}, required: true, doc: "Which role the repo connects as."],
                 database: [
                   type: {:in, [:sandboxed, :committed]},
                   required: true,
                   doc:
                     "Which database the repo connects to. `:sandboxed` app repos run under `Ecto.Adapters.SQL.Sandbox`."
                 ],
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

  @doc false
  @spec validate_repo(term()) :: {:ok, {module(), keyword()}} | {:error, String.t()}
  def validate_repo({repo, config}) when is_atom(repo) and is_list(config) do
    case NimbleOptions.validate(config, @repo_schema) do
      {:ok, config} -> {:ok, {repo, config}}
      {:error, error} -> {:error, "#{inspect(repo)}: #{Exception.message(error)}"}
    end
  end

  def validate_repo(other), do: {:error, "expected {RepoModule, keyword}, got: #{inspect(other)}"}

  @doc "Starts the cluster and the repos. Raises on any failure. Options: #{NimbleOptions.docs(@schema)}"
  @spec start(keyword()) :: t()
  def start(opts) do
    opts = NimbleOptions.validate!(opts, @schema)
    dir = Path.join([File.cwd!(), "tmp", "pg-" <> random_suffix()])

    cluster = %__MODULE__{
      dir: dir,
      socket_dir: dir,
      data_dir: Path.join(dir, "data"),
      log_file: Path.join(dir, "postgres.log"),
      repos: Enum.map(opts[:repos], &elem(&1, 0))
    }

    File.mkdir_p!(dir)
    System.at_exit(fn _status -> stop(cluster) end)
    initdb!(cluster)
    pg_ctl!(cluster, ["start"])
    create_roles_and_databases!(cluster)
    Enum.each(@databases, fn {_tier, database} -> migrate!(cluster, opts, database) end)
    configure_repos!(cluster, opts)
    start_repos!(cluster, opts)
    :persistent_term.put(__MODULE__, cluster)
    cluster
  end

  @doc "The running cluster, for tests that inspect it."
  @spec info() :: t()
  def info, do: :persistent_term.get(__MODULE__)

  @doc "The database name for a tier."
  @spec database(:sandboxed | :committed) :: String.t()
  def database(tier), do: Map.fetch!(@databases, tier)

  @doc "Connection options for a role and tier, as Postgrex and Ecto accept them."
  @spec connection(t(), :app | :owner, :sandboxed | :committed) :: keyword()
  def connection(%__MODULE__{} = cluster, role, tier) do
    [socket_dir: cluster.socket_dir, username: role_name(role), database: database(tier)]
  end

  defp role_name(:app), do: @app
  defp role_name(:owner), do: @owner

  defp random_suffix do
    8 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
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
    case System.cmd(program, args, stderr_to_stdout: true) do
      {_output, 0} ->
        :ok

      {output, status} ->
        log = if File.exists?(cluster.log_file), do: File.read!(cluster.log_file), else: ""
        raise "#{program} #{Enum.join(args, " ")} exited #{status}:\n#{output}\n#{log}"
    end
  end

  defp create_roles_and_databases!(cluster) do
    {:ok, conn} = Postgrex.start_link(socket_dir: cluster.socket_dir, username: @initdb_user, database: "postgres")

    statements =
      ["CREATE ROLE #{@owner} LOGIN", "CREATE ROLE #{@app} LOGIN NOBYPASSRLS"] ++
        Enum.map(@databases, fn {_tier, database} -> "CREATE DATABASE #{database} OWNER #{@owner}" end)

    Enum.each(statements, &Postgrex.query!(conn, &1, []))
    GenServer.stop(conn)
  end

  # Migrations run through the first owner-role repo, pointed at each database
  # in turn with a dynamic instance. The repo's static instance starts later.
  defp migrate!(cluster, opts, database) do
    {repo, _config} = Enum.find(opts[:repos], fn {_repo, config} -> config[:role] == :owner end)

    {:ok, pid} =
      repo.start_link(
        name: nil,
        socket_dir: cluster.socket_dir,
        username: @owner,
        database: database,
        pool_size: 2
      )

    previous = repo.put_dynamic_repo(pid)

    try do
      :ok = opts[:migrate].(repo)
    after
      repo.put_dynamic_repo(previous)
      Supervisor.stop(pid)
    end
  end

  # Repo config lands in the application env before any repo starts, which
  # is the one place Application.put_env is allowed: boot, not a test.
  defp configure_repos!(cluster, opts) do
    Enum.each(opts[:repos], fn {repo, config} ->
      sandbox = if config[:database] == :sandboxed and config[:role] == :app, do: [pool: Sandbox], else: []

      Application.put_env(
        opts[:otp_app],
        repo,
        connection(cluster, config[:role], config[:database]) ++ [pool_size: config[:pool_size]] ++ sandbox
      )
    end)
  end

  defp start_repos!(_cluster, opts) do
    children = Enum.map(opts[:repos], fn {repo, _config} -> repo end)
    {:ok, _pid} = Supervisor.start_link(children, strategy: :one_for_one, name: __MODULE__.Supervisor)

    Enum.each(opts[:repos], fn {repo, config} ->
      if config[:database] == :sandboxed and config[:role] == :app do
        Sandbox.mode(repo, :manual)
      end
    end)
  end

  defp stop(cluster) do
    _ = System.cmd("pg_ctl", ["-D", cluster.data_dir, "-m", "immediate", "stop"], stderr_to_stdout: true)
    File.rm_rf!(cluster.dir)
  end
end
