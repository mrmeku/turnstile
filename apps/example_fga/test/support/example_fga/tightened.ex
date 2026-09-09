defmodule ExampleFga.Tightened do
  @moduledoc """
  The model with one clause taken out of `lawful_purpose`: a member of the
  document's program no longer holds it, and a member of the designating
  office still does. What the change-management and revocation scenarios
  publish, and what a store that already holds tuples is asked under
  afterwards.

  The text is the boot model's with that one line replaced rather than a copy
  of the whole of it, because every tuple in the store was written against the
  boot text and stays valid only while the rest of the model is unchanged. A
  boot text that no longer carries the line raises here, since a replacement
  that matched nothing would publish a model identical to the boot one and the
  publish would answer that the ledger is current.
  """

  use Boundary, top_level?: true, deps: [ExampleFga]

  @clause "define lawful_purpose: member from program or member from designating_office"
  @tightened "define lawful_purpose: member from designating_office"

  @doc "The tightened model as text."
  @spec text() :: String.t()
  def text do
    boot = File.read!(ExampleFga.model())

    if String.contains?(boot, @clause) do
      String.replace(boot, @clause, @tightened)
    else
      raise "#{ExampleFga.model()} carries no #{@clause}, so there is nothing to tighten"
    end
  end

  @doc """
  The tightened model in a file of its own, which is what a binding names: the
  model a binding carries is a path, and the text under review is the boot
  file, which a test leaves where it is.
  """
  @spec written() :: Path.t()
  def written do
    path = Path.join([File.cwd!(), "tmp", "tightened-" <> suffix() <> ".fga"])
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, text())
    path
  end

  defp suffix, do: Base.url_encode64(:crypto.strong_rand_bytes(8), padding: false)
end
