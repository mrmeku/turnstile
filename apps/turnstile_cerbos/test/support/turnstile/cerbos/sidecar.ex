defmodule Turnstile.Cerbos.Sidecar do
  @moduledoc """
  A sidecar of one test's own, over a policy directory of that test's own.

  The run's sidecar reads the conformance policies where they sit in the
  repository, and the tests of the whole suite ask it at the same time. A
  test that writes a policy, reads a decision log line by line, or puts a
  version back cannot use that one: it would change what another test is
  reading. So it gets a directory under `tmp/` with a copy of the
  conformance policies, or with the policy files a version's content
  carries, and a server on that directory which stops when the test ends.
  """

  use Boundary, top_level?: true, deps: [Turnstile.Cerbos, Turnstile.Test]

  alias Turnstile.Cerbos.Replay
  alias Turnstile.Test

  @conformance "priv/conformance"

  @doc "A sidecar over a copy of the conformance policies."
  @spec own!() :: Test.Cerbos.t()
  def own! do
    started(fn directory ->
      Enum.each(conformance(), fn {name, text} -> File.write!(Path.join(directory, name), text) end)
    end)
  end

  @doc "A sidecar over the policy files a version's content carries."
  @spec replayed!(String.t()) :: Test.Cerbos.t()
  def replayed!(policies) when is_binary(policies) do
    started(fn directory -> Replay.build!(to: directory, policies: policies) end)
  end

  @doc "The conformance policies, by file name, in the order the directory holds them."
  @spec conformance() :: [{String.t(), String.t()}]
  def conformance do
    paths =
      @conformance
      |> Path.join("*.yaml")
      |> Path.wildcard()
      |> Enum.sort()

    for path <- paths, do: {Path.basename(path), File.read!(path)}
  end

  defp started(write) do
    directory = Path.join([File.cwd!(), "tmp", "own-" <> suffix()])
    policies = Path.join(directory, "policies")
    File.mkdir_p!(policies)
    write.(policies)
    Test.Cerbos.start_supervised!(policies: policies, dir: directory)
  end

  defp suffix, do: Base.url_encode64(:crypto.strong_rand_bytes(8), padding: false)
end
