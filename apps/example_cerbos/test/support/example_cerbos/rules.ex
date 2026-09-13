defmodule ExampleCerbos.Rules do
  @moduledoc """
  The policy operations the scenarios need from this binding. The rules are
  policy files a sidecar reads, so a rule change is a file written into the
  directory the sidecar watches and a commit the binding names from then on.
  Publishing writes the file, overrides the commit, and appends the version;
  restoring puts the file back and waits for the sidecar to be serving the
  boot rules again, since the scenario asks its next question with no poll.
  """

  @behaviour Example.Scenarios.Rules

  use Boundary,
    top_level?: true,
    deps: [
      Example,
      Example.Scenarios,
      Example.Scenarios.Support,
      ExampleCerbos.Tightened,
      Turnstile,
      Turnstile.Cerbos,
      Turnstile.Test
    ]

  alias Example.Scenarios.Rules
  alias Example.Scenarios.Support
  alias ExampleCerbos.Tightened
  alias Turnstile.Cerbos.Binding
  alias Turnstile.Cerbos.Client
  alias Turnstile.Cerbos.Propagation
  alias Turnstile.Cerbos.Request
  alias Turnstile.Cerbos.Version
  alias Turnstile.Config
  alias Turnstile.Test

  @swapped {__MODULE__, :swapped}

  @impl Rules
  def publish_tightened do
    {:ok, binding} = Binding.resolve()
    previous = Propagation.swap!(binding.policies, [{Tightened.path(), Tightened.document()}])
    _replaced = Process.put(@swapped, {binding.policies, previous})
    :ok = Binding.override(commit: Tightened.commit())

    with {:ok, _published} <- Turnstile.Cerbos.publish() do
      {:ok, tightened} = Binding.resolve()
      {:ok, config} = Config.resolve()
      Version.of(Turnstile.Cerbos, tightened, config, config.clock.())
    end
  end

  @impl Rules
  def restore do
    case Process.get(@swapped) do
      {directory, previous} ->
        :ok = Propagation.restore!(directory, previous)
        _swapped = Process.delete(@swapped)
        :ok

      nil ->
        :ok
    end

    :ok = Binding.override(commit: Application.fetch_env!(:example_cerbos, :commit))
    in_force!()
  end

  @impl Rules
  def publish_boot do
    {:ok, _published} = Turnstile.Cerbos.publish()
    :ok
  end

  # Nothing tells a sidecar that its directory changed and nothing answers
  # whether it has read it, so being in force is a question the boot rules
  # answer one way and the tightened rules the other: a program member reads
  # a document under nothing else. The question carries its own values, so it
  # touches no table and holds no connection.
  defp in_force! do
    {:ok, config} = Config.resolve()
    {Turnstile.Cerbos, options} = Config.adapter(config)
    body = Request.logged(principal(config), resource(), ["read"])
    true = Test.poll(fn -> allowed?(options[:address], body) end, Support.propagation_deadline())
    :ok
  end

  defp allowed?(address, body) do
    case Client.check_resources(address, body) do
      {:ok, %{"results" => [result | _rest]}} -> result["actions"]["read"] == "EFFECT_ALLOW"
      _unanswered -> false
    end
  end

  defp principal(config) do
    now = DateTime.to_iso8601(DateTime.truncate(config.clock.(), :second))

    %{
      id: "turnstile.restore",
      roles: ["user"],
      attr: %{
        employment: "federal",
        nationality: "US",
        environment: %{now: now, reauthenticated_at: nil}
      }
    }
  end

  defp resource do
    %{
      kind: "document",
      id: "0",
      attr: %{
        program_roles: ["member"],
        office_roles: [],
        effective_controls: [],
        releasable_to: [],
        agency_nationalities: ["US"],
        listed: [],
        decontrol: nil
      }
    }
  end
end
