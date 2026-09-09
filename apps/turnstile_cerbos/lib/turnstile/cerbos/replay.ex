defmodule Turnstile.Cerbos.Replay do
  @moduledoc """
  A policy version put back, in a policy directory of its own, and a stored
  decision asked again under it.

  The version's content is the policy files as text, each preceded by its
  path, so putting a version back is writing those files into a directory
  and taking every other policy file out of it: a directory that kept one
  file of another version would answer under rules the decision was never
  made under. The directory belongs to a sidecar the caller raised and
  throws away, because a sidecar reads one directory and the run's own
  sidecar is answering other questions from its own.

  Asking again takes the facts from the record rather than from the tables,
  which is what makes the answer the past. A decision was made over
  attribute values, and those values are in the request the sidecar logged;
  a caller with a fold of its own passes the values it folded. Either way
  nothing is read from a repository here, so state that moved since the
  decision cannot reach the answer.

  What comes back is the answer that version gives to that question, for a
  caller to set beside the answer the record holds.
  """

  alias Turnstile.Answer
  alias Turnstile.Cerbos.Client
  alias Turnstile.Cerbos.Decide
  alias Turnstile.Cerbos.Decisions.Line
  alias Turnstile.Cerbos.Request
  alias Turnstile.Cerbos.Version
  alias Turnstile.Decision
  alias Turnstile.Error
  alias Turnstile.Object

  @schema NimbleOptions.new!(
            to: [
              type: :string,
              required: true,
              doc: "The policy directory of the sidecar the version is put back in."
            ],
            policies: [
              type: :string,
              required: true,
              doc: "The version's content: the policy files as text, each preceded by its path."
            ]
          )

  @doc "The schema of the options a build takes: #{NimbleOptions.docs(@schema)}"
  @spec options_schema() :: NimbleOptions.t()
  def options_schema, do: @schema

  @doc """
  Writes the version's policy files into the directory `to:` names, having
  taken every policy file already there out of it. A sidecar started on that
  directory afterwards reads them at boot, and one already running reads
  them on its watch, which takes the propagation
  `Turnstile.Cerbos.Propagation` measures.
  """
  @spec build!(keyword()) :: :ok
  def build!(options) when is_list(options) do
    validated = NimbleOptions.validate!(options, @schema)
    directory = validated[:to]
    File.mkdir_p!(directory)

    existing =
      directory
      |> Path.join("**/*.{yaml,yml}")
      |> Path.wildcard()

    Enum.each(existing, &File.rm!/1)
    Enum.each(Version.from_text(validated[:policies]), &write!(directory, &1))
  end

  @doc """
  The answer the sidecar at the address gives to the question a stored
  decision holds, with the attribute values the caller folded: `principal`
  for the subject, `resource` for the object.
  """
  @spec ask(Client.address(), Decision.t(), map(), map()) :: {:ok, Answer.t()} | {:error, Error.Engine.t()}
  def ask(address, %Decision{} = decision, principal, resource)
      when is_binary(address) and is_map(principal) and is_map(resource) do
    {type, id} = decision.object
    object = %Object{type: type, id: id}
    body = Request.check(decision.subject, decision.operation, principal, [{object, resource}])
    asked(address, body, Atom.to_string(decision.operation), decision.policy_version)
  end

  @doc """
  The answer the sidecar at the address gives to the question one line of a
  decision log holds, sent as that line holds it.
  """
  @spec ask(Client.address(), Line.t()) :: {:ok, Answer.t()} | {:error, Error.Engine.t()}
  def ask(address, %Line{} = line) when is_binary(address) do
    principal = %{id: line.subject, roles: line.roles, attr: line.principal}
    resource = %{kind: line.kind, id: line.id, attr: line.resource}
    asked(address, Request.logged(principal, resource, [line.operation]), line.operation, nil)
  end

  defp asked(address, body, action, version) do
    with {:ok, answered} <- called(address, body) do
      answer(answered, action, version)
    end
  end

  defp called(address, body) do
    case Client.check_resources(address, body) do
      {:ok, answered} -> {:ok, answered}
      {:error, detail} -> {:error, engine(detail)}
    end
  end

  defp answer(%{"results" => [result | _rest]}, action, version) do
    {:ok, Decide.answer(result["actions"][action], Decide.matched(result, action), version)}
  end

  defp answer(other, _action, _version) do
    {:error, engine("cerbos answered no result: " <> String.slice(inspect(other), 0, 200))}
  end

  defp write!(directory, {path, text}) do
    full = Path.join(directory, path)
    File.mkdir_p!(Path.dirname(full))
    File.write!(full, text)
  end

  defp engine(detail), do: %Error.Engine{adapter: Turnstile.Cerbos, operation: :replay, detail: detail}
end
