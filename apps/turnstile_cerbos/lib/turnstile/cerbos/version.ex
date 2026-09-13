defmodule Turnstile.Cerbos.Version do
  @moduledoc """
  The policy version of a sidecar: the commit of the repository the policy
  files are in, which the binding names.

  The identifier is not derived from the files, and it is not the `version`
  field inside a policy. That field runs variants of a policy side by side,
  so two variants are in force at once and neither is the history of the
  other; history is what the repository holds. The content is the policy
  files as text, each preceded by its path, carried by value when it is
  under the cap and left as a pointer to the directory and the commit
  otherwise, and the content hash is the digest of that text either way, so
  a directory that changed without a new commit is visible as a hash that
  no longer matches.

  `Turnstile.Cerbos.publish/0` appends the version when the ledger's latest
  for the adapter is older or missing, inside the ledger's transaction when
  it offers one, so many nodes booting at once append it once. In ledger
  mode none it emits `[:turnstile, :cerbos, :policy_version]` and appends
  nothing.
  """

  alias Turnstile.Cerbos.Binding
  alias Turnstile.Config
  alias Turnstile.Error
  alias Turnstile.PolicyVersion

  @marker "# turnstile-policy: "
  @telemetry [:turnstile, :cerbos, :policy_version]

  @doc "The telemetry event `Turnstile.Cerbos.publish/0` emits, once per call."
  @spec telemetry_event() :: [atom()]
  def telemetry_event, do: @telemetry

  @doc "The version identifier a decision names: the commit the binding gives."
  @spec ref(Binding.t()) :: PolicyVersion.ref()
  def ref(%Binding{commit: commit}), do: commit

  @doc "The policy files of the bound directory, by path relative to it, sorted."
  @spec files(Binding.t()) :: {:ok, [{Path.t(), String.t()}]} | {:error, Error.t()}
  def files(%Binding{policies: directory}) do
    paths =
      directory
      |> Path.join("**/*.{yaml,yml}")
      |> Path.wildcard()
      |> Enum.sort()

    step = fn path, {:ok, acc} -> read(directory, path, acc) end

    with {:ok, reversed} <- Enum.reduce_while(paths, {:ok, []}, step), do: {:ok, Enum.reverse(reversed)}
  end

  @doc "The policy files as one text, each preceded by its path."
  @spec content(Binding.t()) :: {:ok, String.t()} | {:error, Error.t()}
  def content(%Binding{} = binding) do
    with {:ok, files} <- files(binding), do: {:ok, to_text(files)}
  end

  @doc "The files as the text `from_text/1` reads back."
  @spec to_text([{Path.t(), String.t()}]) :: String.t()
  def to_text(files) when is_list(files) do
    Enum.map_join(files, "", fn {path, text} -> @marker <> path <> "\n" <> ended(text) end)
  end

  @doc "The text back to the files, by path, in the order the text carries them."
  @spec from_text(String.t()) :: [{Path.t(), String.t()}]
  def from_text(text) when is_binary(text) do
    text
    |> String.split(@marker)
    |> Enum.flat_map(&parted/1)
  end

  @doc "The digest of the content."
  @spec content_hash(String.t()) :: String.t()
  def content_hash(text) when is_binary(text), do: Base.encode16(:crypto.hash(:sha256, text), case: :lower)

  @doc "The version as the ledger records it for `adapter`, with the content by value when under the cap."
  @spec of(module(), Binding.t(), Config.t(), DateTime.t()) :: {:ok, PolicyVersion.t()} | {:error, Error.t()}
  def of(adapter, %Binding{} = binding, %Config{caps: caps}, %DateTime{} = at) when is_atom(adapter) do
    with {:ok, text} <- content(binding) do
      under_cap? = byte_size(text) <= caps[:policy_content_bytes]

      {:ok,
       %PolicyVersion{
         adapter: adapter,
         version: ref(binding),
         content_hash: content_hash(text),
         content: if(under_cap?, do: text),
         pointer: if(under_cap?, do: nil, else: pointer(binding)),
         author: binding.author,
         approval: binding.approval,
         at: at
       }}
    end
  end

  defp read(directory, path, acc) do
    case File.read(path) do
      {:ok, text} -> {:cont, {:ok, [{Path.relative_to(path, directory), text} | acc]}}
      {:error, reason} -> {:halt, {:error, invalid("#{path} could not be read: #{:file.format_error(reason)}")}}
    end
  end

  defp parted(""), do: []

  defp parted(part) do
    case String.split(part, "\n", parts: 2) do
      [path, text] -> [{path, text}]
      [_only] -> []
    end
  end

  defp ended(text) do
    if String.ends_with?(text, "\n"), do: text, else: text <> "\n"
  end

  defp pointer(%Binding{policies: directory, commit: commit}), do: "policies in #{directory} at #{commit}"

  defp invalid(detail), do: Error.invalid(:policies, detail)
end
