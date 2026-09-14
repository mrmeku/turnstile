defmodule Turnstile.Postgres.Version do
  @moduledoc """
  The policy version of row-level security: the migration number. A
  migration that changes a policy appends its own version in the same
  transaction as its DDL, so the rules and the record of what they became
  commit together or not at all, and a decision made afterwards names that
  number.

  The content is the policies as `pg_policy` renders them, carried by value
  when it is under the cap the caller gives and left as a pointer to the
  tables above it. The content hash is the SHA-256 of that text either way.
  """

  alias Turnstile.PolicyVersion
  alias Turnstile.Postgres.Adapter
  alias Turnstile.Postgres.Catalog
  alias Turnstile.Postgres.Policy

  @doc "The telemetry event `publish/1` emits, once per call."
  @spec telemetry_event() :: [atom()]
  def telemetry_event, do: Adapter.Version.telemetry_event()

  @doc """
  The version a migration publishes, from the policies it read back.
  Requires `version:`, `author:`, `approval:`, `at:`, and `content_bytes:`.
  """
  @spec of(module(), [Policy.t()], keyword()) :: PolicyVersion.t()
  def of(adapter, policies, options) when is_atom(adapter) and is_list(policies) and is_list(options) do
    text = Catalog.to_text(policies)
    carried? = byte_size(text) <= Keyword.fetch!(options, :content_bytes)

    %PolicyVersion{
      adapter: adapter,
      version: to_string(Keyword.fetch!(options, :version)),
      content_hash: Base.encode16(:crypto.hash(:sha256, text), case: :lower),
      content: if(carried?, do: text),
      pointer: if(carried?, do: nil, else: pointer(policies)),
      author: Keyword.fetch!(options, :author),
      approval: Keyword.fetch!(options, :approval),
      at: Keyword.fetch!(options, :at)
    }
  end

  @doc "Emit the version, once per call, answering the version emitted."
  @spec publish(PolicyVersion.t()) :: {:ok, PolicyVersion.t()}
  def publish(%PolicyVersion{} = version), do: Adapter.Version.publish(version)

  defp pointer(policies) do
    tables =
      policies
      |> Enum.map(& &1.table)
      |> Enum.uniq()
      |> Enum.sort()

    "policies on " <> Enum.join(tables, ", ")
  end
end
