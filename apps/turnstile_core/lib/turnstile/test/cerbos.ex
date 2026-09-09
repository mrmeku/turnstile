defmodule Turnstile.Test.Cerbos do
  @moduledoc """
  One `cerbos server` per test run, and one of its own for a test that
  changes what the run's sidecar must not change.

  `start_shared/1` writes a configuration file and starts the sidecar under
  `MuonTrap.Daemon`, which kills the operating-system process when the
  Erlang process that owns it dies and when the virtual machine exits, so no
  sidecar outlives the run that started it. The server reads the policy
  directory the caller names, writes its audit log to a file under `tmp/`,
  and listens on a free port of the loopback interface, which is the address
  the caller puts in the adapter's configuration entry. Called from
  `test_helper.exs`, once for the run; a second call returns the first
  sidecar.

  `start_supervised!/1` is the same server owned by one test, through
  `ExUnit`'s supervisor, for a test that publishes a policy version or reads
  the decision log: those tests write into a policy directory and read a log
  file that the run's other tests are reading at the same time. It stops
  when the test ends.

  Both wait for the health endpoint to answer before returning, so a caller
  that gets a struct back has a server that answers. Nothing here speaks the
  policy language or the decision API; the adapter package does that.
  """

  @schema NimbleOptions.new!(
            policies: [
              type: :string,
              required: true,
              doc: "The directory the server reads its policies from."
            ],
            dir: [
              type: :string,
              doc: "Where the configuration file and the audit log go; a directory under `tmp/` by default."
            ],
            watch: [
              type: :boolean,
              default: true,
              doc: "Whether the server watches the policy directory, which is how a published policy reaches it."
            ],
            timeout: [
              type: :pos_integer,
              default: 20_000,
              doc: "How long to wait for the health endpoint, in milliseconds."
            ]
          )

  @enforce_keys [:address, :dir, :policies, :audit_log, :config_file]
  defstruct [:address, :dir, :policies, :audit_log, :config_file, :daemon]

  @type t :: %__MODULE__{
          address: String.t(),
          dir: Path.t(),
          policies: Path.t(),
          audit_log: Path.t(),
          config_file: Path.t(),
          daemon: pid() | nil
        }

  @doc "The schema of the options both starts take: #{NimbleOptions.docs(@schema)}"
  @spec options_schema() :: NimbleOptions.t()
  def options_schema, do: @schema

  @doc "The run's sidecar, started on the first call and returned on every call after it."
  @spec start_shared(keyword()) :: t()
  def start_shared(options) when is_list(options) do
    case :persistent_term.get(__MODULE__, nil) do
      %__MODULE__{} = shared ->
        shared

      nil ->
        sidecar = prepare(options)
        daemon = start_daemon!(sidecar)
        shared = await!(%{sidecar | daemon: daemon}, timeout(options))
        :persistent_term.put(__MODULE__, shared)
        stop_with_suite()
        shared
    end
  end

  @doc "A sidecar of the calling test's own, stopped when the test ends."
  @spec start_supervised!(keyword()) :: t()
  def start_supervised!(options) when is_list(options) do
    sidecar = prepare(options)
    daemon = ExUnit.Callbacks.start_supervised!(child_spec(sidecar))
    ExUnit.Callbacks.on_exit(fn -> File.rm_rf!(sidecar.dir) end)
    await!(%{sidecar | daemon: daemon}, timeout(options))
  end

  @doc "The run's sidecar, for a test that reads its address or its audit log."
  @spec info() :: t()
  def info do
    case :persistent_term.get(__MODULE__, nil) do
      %__MODULE__{} = shared -> shared
      nil -> raise "no shared sidecar; call Turnstile.Test.Cerbos.start_shared/1 from test_helper.exs"
    end
  end

  @doc """
  The child specification of the sidecar's daemon, the options this module
  gives `MuonTrap.Daemon` for a `cerbos server`.
  """
  @spec child_spec(t()) :: Supervisor.child_spec()
  def child_spec(%__MODULE__{} = sidecar) do
    Supervisor.child_spec(
      {MuonTrap.Daemon, ["cerbos", ["server", "--config", sidecar.config_file], daemon_options(sidecar)]},
      id: {__MODULE__, sidecar.address}
    )
  end

  @doc "Stops the sidecar and removes its directory. Safe to call twice."
  @spec stop(t()) :: :ok
  def stop(%__MODULE__{} = sidecar) do
    if is_pid(sidecar.daemon) and Process.alive?(sidecar.daemon), do: GenServer.stop(sidecar.daemon)
    File.rm_rf!(sidecar.dir)
    if :persistent_term.get(__MODULE__, nil) == sidecar, do: :persistent_term.erase(__MODULE__)
    :ok
  end

  @doc "Stops the run's sidecar; registered with `ExUnit.after_suite/1` and `System.at_exit/1`."
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
    request = {~c"http://#{address}/_cerbos/health", []}

    case :httpc.request(:get, request, [timeout: 1_000, connect_timeout: 1_000], body_format: :binary) do
      {:ok, {{_version, 200, _reason}, _headers, body}} -> body =~ "SERVING"
      _unhealthy -> false
    end
  end

  # A free port of the loopback interface: the operating system names one for
  # a listener asking for port zero, and the sidecar takes it after the
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
    dir = options[:dir] || Path.join([File.cwd!(), "tmp", "cerbos-" <> suffix()])
    port = free_port()

    sidecar = %__MODULE__{
      address: "127.0.0.1:#{port}",
      dir: dir,
      policies: Path.expand(options[:policies]),
      audit_log: Path.join(dir, "audit.log"),
      config_file: Path.join(dir, "config.yaml")
    }

    File.mkdir_p!(dir)
    File.write!(sidecar.config_file, configuration(sidecar, port, options[:watch]))
    sidecar
  end

  # The server's configuration: the caller's policies on disk, a decision log
  # in a file this run owns, and one listener per protocol, because Cerbos
  # starts its gRPC listener whether or not anyone connects to it.
  defp configuration(%__MODULE__{} = sidecar, port, watch?) do
    """
    server:
      httpListenAddr: "127.0.0.1:#{port}"
      grpcListenAddr: "unix:#{Path.join(sidecar.dir, "grpc.sock")}"
    storage:
      driver: "disk"
      disk:
        directory: "#{sidecar.policies}"
        watchForChanges: #{watch?}
    audit:
      enabled: true
      accessLogsEnabled: false
      decisionLogsEnabled: true
      backend: "file"
      file:
        path: "#{sidecar.audit_log}"
    """
  end

  # The environment of the calling shell must not redirect the server to
  # another configuration or another policy store.
  defp daemon_options(%__MODULE__{} = sidecar) do
    [
      cd: sidecar.dir,
      env: Enum.map(~w(CERBOS_CONFIG CERBOS_HUB_DEPLOYMENT_ID CERBOS_HUB_PLAYGROUND_ID), &{&1, nil}),
      stderr_to_stdout: true,
      log_output: :debug,
      log_prefix: "cerbos: "
    ]
  end

  defp start_daemon!(%__MODULE__{} = sidecar) do
    %{start: {module, function, arguments}} = child_spec(sidecar)
    {:ok, daemon} = apply(module, function, arguments)
    daemon
  end

  defp await!(%__MODULE__{} = sidecar, timeout) do
    Turnstile.Test.poll(fn -> healthy?(sidecar.address) end, timeout)
    sidecar
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
