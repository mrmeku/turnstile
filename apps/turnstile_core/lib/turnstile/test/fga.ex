defmodule Turnstile.Test.Fga do
  @moduledoc """
  One `openfga run` per test run, and one of its own for a test that needs a
  server it can throw away.

  `start_shared/1` starts the server under `MuonTrap.Daemon`, which kills the
  operating-system process when the Erlang process that owns it dies and when
  the virtual machine exits, so no server outlives the run that started it.
  The datastore is the in-memory one, so a run leaves nothing on disk and the
  next run starts empty; isolation between tests is the store, which each test
  creates for itself. Called from `test_helper.exs`, once for the run; a
  second call returns the first server.

  `start_supervised!/1` is a server of one test's own, through `ExUnit`'s
  supervisor, for a test that replays a stored decision: a replay writes the
  tuples of a past state into a store and asks under the model in force then,
  and the tuples are the past rather than the present, so they belong to a
  server the test throws away. It stops when the test ends.

  Both listen on free ports of the loopback interface and wait for the health
  endpoint to answer before returning, so a caller that gets a struct back has
  a server that answers. The playground and the metrics listener are off: they
  bind ports of their own that a second server on the same machine would
  collide on. Nothing here speaks the model language or the decision API; the
  adapter package does that.
  """

  @schema NimbleOptions.new!(
            dir: [
              type: :string,
              doc: "The working directory of the server process; a directory under `tmp/` by default."
            ],
            timeout: [
              type: :pos_integer,
              default: 20_000,
              doc: "How long to wait for the health endpoint, in milliseconds."
            ]
          )

  @enforce_keys [:address, :grpc_address, :dir]
  defstruct [:address, :grpc_address, :dir, :daemon]

  @type t :: %__MODULE__{
          address: String.t(),
          grpc_address: String.t(),
          dir: Path.t(),
          daemon: pid() | nil
        }

  @doc "The schema of the options both starts take: #{NimbleOptions.docs(@schema)}"
  @spec options_schema() :: NimbleOptions.t()
  def options_schema, do: @schema

  @doc "The run's server, started on the first call and returned on every call after it."
  @spec start_shared(keyword()) :: t()
  def start_shared(options \\ []) when is_list(options) do
    case :persistent_term.get(__MODULE__, nil) do
      %__MODULE__{} = shared ->
        shared

      nil ->
        server = prepare(options)
        daemon = start_daemon!(server)
        shared = await!(%{server | daemon: daemon}, timeout(options))
        :persistent_term.put(__MODULE__, shared)
        stop_with_suite()
        shared
    end
  end

  @doc "A server of the calling test's own, stopped when the test ends."
  @spec start_supervised!(keyword()) :: t()
  def start_supervised!(options \\ []) when is_list(options) do
    server = prepare(options)
    daemon = ExUnit.Callbacks.start_supervised!(child_spec(server))
    ExUnit.Callbacks.on_exit(fn -> File.rm_rf!(server.dir) end)
    await!(%{server | daemon: daemon}, timeout(options))
  end

  @doc "The run's server, for a test that reads its address."
  @spec info() :: t()
  def info do
    case :persistent_term.get(__MODULE__, nil) do
      %__MODULE__{} = shared -> shared
      nil -> raise "no shared server; call Turnstile.Test.Fga.start_shared/1 from test_helper.exs"
    end
  end

  @doc """
  The child specification of the server's daemon, the options this module
  gives `MuonTrap.Daemon` for an `openfga run`.
  """
  @spec child_spec(t()) :: Supervisor.child_spec()
  def child_spec(%__MODULE__{} = server) do
    Supervisor.child_spec(
      {MuonTrap.Daemon, ["openfga", arguments(server), daemon_options(server)]},
      id: {__MODULE__, server.address}
    )
  end

  @doc "Stops the server and removes its directory. Safe to call twice."
  @spec stop(t()) :: :ok
  def stop(%__MODULE__{} = server) do
    if is_pid(server.daemon) and Process.alive?(server.daemon), do: GenServer.stop(server.daemon)
    File.rm_rf!(server.dir)
    if :persistent_term.get(__MODULE__, nil) == server, do: :persistent_term.erase(__MODULE__)
    :ok
  end

  @doc "Stops the run's server; registered with `ExUnit.after_suite/1` and `System.at_exit/1`."
  @spec stop_shared(term()) :: :ok
  def stop_shared(_status) do
    case :persistent_term.get(__MODULE__, nil) do
      %__MODULE__{} = shared -> stop(shared)
      nil -> :ok
    end
  end

  @doc "Whether the server at an address answers its health endpoint."
  @spec healthy?(String.t()) :: boolean()
  def healthy?(address) when is_binary(address) do
    request = {~c"http://#{address}/healthz", []}

    case :httpc.request(:get, request, [timeout: 1_000, connect_timeout: 1_000], body_format: :binary) do
      {:ok, {{_version, 200, _reason}, _headers, body}} -> body =~ "SERVING"
      _unhealthy -> false
    end
  end

  # A free port of the loopback interface: the operating system names one for
  # a listener asking for port zero, and the server takes it after the
  # listener closes. Two runs on one machine never meet, because each asks.
  @spec free_port() :: pos_integer()
  defp free_port do
    {:ok, socket} = :gen_tcp.listen(0, ip: {127, 0, 0, 1}, reuseaddr: true)
    {:ok, port} = :inet.port(socket)
    :ok = :gen_tcp.close(socket)
    port
  end

  defp prepare(options) do
    options = NimbleOptions.validate!(options, @schema)
    dir = options[:dir] || Path.join([File.cwd!(), "tmp", "openfga-" <> suffix()])

    server = %__MODULE__{
      address: "127.0.0.1:#{free_port()}",
      grpc_address: "127.0.0.1:#{free_port()}",
      dir: dir
    }

    File.mkdir_p!(dir)
    server
  end

  # The datastore is in memory, so nothing is configured but the addresses.
  # The playground and the metrics listener bind ports this module did not
  # ask for, and a second server on the same machine would collide on them.
  defp arguments(%__MODULE__{} = server) do
    [
      "run",
      "--datastore-engine",
      "memory",
      "--http-addr",
      server.address,
      "--grpc-addr",
      server.grpc_address,
      "--playground-enabled=false",
      "--metrics-enabled=false",
      "--log-level=error"
    ]
  end

  # The environment of the calling shell must not redirect the server to
  # another datastore or another address.
  defp daemon_options(%__MODULE__{} = server) do
    cleared =
      ~w(OPENFGA_DATASTORE_ENGINE OPENFGA_DATASTORE_URI OPENFGA_HTTP_ADDR OPENFGA_GRPC_ADDR
         OPENFGA_PLAYGROUND_ENABLED OPENFGA_METRICS_ENABLED OPENFGA_AUTHN_METHOD OPENFGA_LOG_LEVEL)

    [
      cd: server.dir,
      env: Enum.map(cleared, &{&1, nil}),
      stderr_to_stdout: true,
      log_output: :debug,
      log_prefix: "openfga: "
    ]
  end

  defp start_daemon!(%__MODULE__{} = server) do
    %{start: {module, function, arguments}} = child_spec(server)
    {:ok, daemon} = apply(module, function, arguments)
    daemon
  end

  defp await!(%__MODULE__{} = server, timeout) do
    Turnstile.Test.poll(fn -> healthy?(server.address) end, timeout)
    server
  end

  defp timeout(options), do: Keyword.get(options, :timeout, @schema.schema[:timeout][:default])

  defp suffix, do: Base.url_encode64(:crypto.strong_rand_bytes(8), padding: false)

  # Registered once per virtual machine. Remote captures, not closures:
  # coverage recompiles this module and a closure from the old code would be
  # invalid by the time the callbacks run.
  defp stop_with_suite do
    if !:persistent_term.get({__MODULE__, :callbacks}, false) do
      _loaded = Application.load(:ex_unit)
      ExUnit.after_suite(&__MODULE__.stop_shared/1)
      System.at_exit(&__MODULE__.stop_shared/1)
      :persistent_term.put({__MODULE__, :callbacks}, true)
    end
  end
end
