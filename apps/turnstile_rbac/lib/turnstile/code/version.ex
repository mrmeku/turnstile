defmodule Turnstile.Code.Version do
  @moduledoc """
  The policy version of RBAC in code. Its identifier is the `version:` the
  policy module gave, or the content hash: a digest of the policy module and
  every predicate module, so a change to a rule is a new version whether or
  not anyone said so. The content is the role table and the module list as
  text when it is under the configured cap, and a pointer to the modules
  otherwise.

  One event per version: `Turnstile.Code.publish/0` reads the ledger's
  latest policy version for this adapter and appends only when it is older
  or missing, inside the ledger's transaction when it offers one, so many
  nodes booting at once append it once. In ledger mode none it emits
  `telemetry_event/0` and appends nothing.
  """

  alias Turnstile.Code.Policy
  alias Turnstile.Config
  alias Turnstile.PolicyVersion

  @telemetry [:turnstile, :code, :policy_version]

  @doc "The telemetry event `Turnstile.Code.publish/0` emits."
  @spec telemetry_event() :: [atom()]
  def telemetry_event, do: @telemetry

  @doc "The version identifier a decision names."
  @spec ref(Policy.t()) :: PolicyVersion.ref()
  def ref(policy) when is_atom(policy), do: Policy.options(policy)[:version] || content_hash(policy)

  @doc "The digest of the policy module and every predicate module."
  @spec content_hash(Policy.t()) :: String.t()
  def content_hash(policy) when is_atom(policy) do
    digest = Enum.map_join(Policy.modules(policy), "", &(&1.module_info(:md5) <> Atom.to_string(&1)))
    Base.encode16(:crypto.hash(:sha256, digest), case: :lower)
  end

  @doc "The role table and the module list as text."
  @spec content(Policy.t()) :: String.t()
  def content(policy) when is_atom(policy) do
    roles =
      Enum.map_join(Policy.table(policy), "", fn {name, permissions} -> "  #{name}: #{Enum.join(permissions, ", ")}\n" end)

    "modules: #{Enum.map_join(Policy.modules(policy), ", ", &inspect/1)}\nroles:\n" <> roles
  end

  @doc "The version as the ledger records it for `adapter`, with the content by value when under the cap."
  @spec of(module(), Policy.t(), Config.t(), DateTime.t()) :: PolicyVersion.t()
  def of(adapter, policy, %Config{caps: caps}, %DateTime{} = at) when is_atom(adapter) and is_atom(policy) do
    options = Policy.options(policy)
    text = content(policy)
    under_cap? = byte_size(text) <= caps[:policy_content_bytes]

    %PolicyVersion{
      adapter: adapter,
      version: ref(policy),
      content_hash: content_hash(policy),
      content: if(under_cap?, do: text),
      pointer: if(under_cap?, do: nil, else: "modules " <> Enum.map_join(Policy.modules(policy), ", ", &inspect/1)),
      author: options[:author],
      approval: options[:approval],
      at: at
    }
  end
end
