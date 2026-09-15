defmodule Turnstile.Fga.Conformance.Versions do
  @moduledoc """
  The change-management artifact of the OpenFGA adapter: tightening writes
  the conformance model with `can_read` narrowed to a reader alone to a
  file of its own, binds that file, publishes it to the test's store, and
  pins the configuration to the model id the server answered with;
  restoring binds the boot model again and pins the boot id. The server
  keeps every model, so a question pinned to an id is answered under that
  model at once, and neither waits.
  """

  @behaviour Turnstile.Conformance.Versions

  alias Turnstile.Config
  alias Turnstile.Conformance.Versions
  alias Turnstile.Fga
  alias Turnstile.Fga.Binding
  alias Turnstile.Fga.Version
  alias Turnstile.PolicyVersion
  alias Turnstile.Test

  @model "priv/conformance/model.fga"
  @clause "define can_read: reader or editor"
  @tightened "define can_read: reader"
  @boot {__MODULE__, :boot}

  @impl Versions
  def event, do: Version.telemetry_event()

  @impl Versions
  def tighten do
    {Fga, options} = adapter()
    path = Path.join(System.tmp_dir!(), "turnstile-fga-tightened-#{System.unique_integer([:positive])}.fga")
    File.write!(path, tightened!())
    Process.put(@boot, {Keyword.fetch!(options, :model_id), path})
    :ok = Binding.override(model: path)

    with {:ok, %PolicyVersion{} = version} <- Fga.publish() do
      :ok = pin(options, version.version)
      {:ok, version}
    end
  end

  @impl Versions
  def restore do
    {Fga, options} = adapter()
    {boot, path} = Process.delete(@boot)
    File.rm!(path)
    :ok = Binding.override(model: @model)
    pin(options, boot)
  end

  defp tightened! do
    text = File.read!(@model)

    if String.contains?(text, @clause) do
      String.replace(text, @clause, @tightened)
    else
      raise ArgumentError, "#{@model} no longer holds `#{@clause}`, which the tightening narrows"
    end
  end

  defp adapter do
    {:ok, %Config{} = config} = Config.resolve()
    Config.adapter(config)
  end

  defp pin(options, model_id), do: Test.with_config(adapter: {Fga, Keyword.put(options, :model_id, model_id)})
end
