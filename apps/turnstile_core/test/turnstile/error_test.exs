defmodule Turnstile.ErrorTest do
  use ExUnit.Case, async: true

  alias Turnstile.Adapter.Fake
  alias Turnstile.Error

  test "an engine failure names the adapter, the operation, and the detail" do
    error = %Error.Engine{adapter: Fake, operation: :read, detail: "connection refused"}
    assert Exception.message(error) == "Turnstile.Adapter.Fake failed during read: connection refused"
  end

  test "an unsupported feature names the adapter, the feature, and the note" do
    error = %Error.Unsupported{adapter: Fake, feature: :scope, note: "no scope query"}
    assert Exception.message(error) == "Turnstile.Adapter.Fake does not support scope: no scope query"
  end
end
