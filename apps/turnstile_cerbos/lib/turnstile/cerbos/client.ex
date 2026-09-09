defmodule Turnstile.Cerbos.Client do
  @moduledoc """
  The sidecar over HTTP and JSON: one function per endpoint the adapter
  uses, and one telemetry event per call, which is how a shape test counts
  the engine's own calls (`docs/reference.md` §7).

  The transport is `httpc`, which OTP ships, and the encoder is Elixir's
  `JSON`, so talking to the sidecar adds no dependency to an application
  that takes this adapter. Every call is a `POST` or a `GET` to the address
  the configuration entry names, with a deadline: a sidecar that does not
  answer within it is a failure the caller turns into a denial rather than a
  wait.

  Nothing here knows what a policy says. A call either answers with the
  body decoded, or fails with a sentence naming what went wrong, which
  becomes the detail of the engine error and the message of the denial's
  reason.
  """

  @connect_timeout 1_000
  @timeout 5_000
  @telemetry [:turnstile, :cerbos, :request]

  @typedoc "The address of a sidecar, a host and a port."
  @type address :: String.t()

  @doc "The telemetry event every call emits, once per call, whether it answered or failed."
  @spec telemetry_event() :: [atom()]
  def telemetry_event, do: @telemetry

  @doc "A decision for one principal over resources: `POST /api/check/resources`."
  @spec check_resources(address(), map()) :: {:ok, map()} | {:error, String.t()}
  def check_resources(address, body) when is_binary(address) and is_map(body) do
    post(address, "/api/check/resources", body)
  end

  @doc "A query plan for one principal, kind, and action: `POST /api/plan/resources`."
  @spec plan_resources(address(), map()) :: {:ok, map()} | {:error, String.t()}
  def plan_resources(address, body) when is_binary(address) and is_map(body) do
    post(address, "/api/plan/resources", body)
  end

  @doc "The version and the commit of the server itself: `GET /api/server_info`."
  @spec server_info(address()) :: {:ok, map()} | {:error, String.t()}
  def server_info(address) when is_binary(address), do: get(address, "/api/server_info")

  @doc "Whether the server answers that it is serving: `GET /_cerbos/health`."
  @spec serving?(address()) :: boolean()
  def serving?(address) when is_binary(address) do
    match?({:ok, %{"status" => "SERVING"}}, get(address, "/_cerbos/health"))
  end

  defp post(address, path, body) do
    request = {url(address, path), [], ~c"application/json", JSON.encode_to_iodata!(body)}
    measured(path, fn -> :httpc.request(:post, request, http_options(), options()) end)
  end

  defp get(address, path) do
    measured(path, fn -> :httpc.request(:get, {url(address, path), []}, http_options(), options()) end)
  end

  # One event per call, with the duration and the outcome, so a test can
  # count the calls a port operation made without a database query to count.
  defp measured(path, fun) do
    started = System.monotonic_time()
    result = answer(fun.())
    duration = System.monotonic_time() - started
    :telemetry.execute(@telemetry, %{duration: duration}, %{path: path, outcome: elem(result, 0)})
    result
  end

  defp answer({:ok, {{_version, 200, _phrase}, _headers, body}}), do: decoded(body)

  defp answer({:ok, {{_version, status, _phrase}, _headers, body}}) do
    {:error, "cerbos answered #{status}: #{String.slice(to_string(body), 0, 200)}"}
  end

  defp answer({:error, reason}), do: {:error, "cerbos could not be reached: #{inspect(reason)}"}

  defp decoded(body) do
    case JSON.decode(body) do
      {:ok, decoded} when is_map(decoded) -> {:ok, decoded}
      {:ok, other} -> {:error, "cerbos answered a body that is no object: #{inspect(other)}"}
      {:error, reason} -> {:error, "cerbos answered a body that is no JSON: #{inspect(reason)}"}
    end
  end

  defp url(address, path), do: String.to_charlist("http://" <> address <> path)

  defp http_options, do: [timeout: @timeout, connect_timeout: @connect_timeout]

  defp options, do: [body_format: :binary]
end
