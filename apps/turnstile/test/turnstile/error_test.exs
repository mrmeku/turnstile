defmodule Turnstile.ErrorTest do
  use ExUnit.Case, async: true

  alias Turnstile.Error

  test "the one error carries a reason and a detail, and the detail is the message" do
    error = %Error{reason: :unsupported, detail: "Turnstile.Adapter.Fake does not support scope"}
    assert Exception.message(error) == "Turnstile.Adapter.Fake does not support scope"
    refute :allowed in Error.reasons()
    assert :unsupported in Error.reasons()
    assert :rule_denied in Error.reasons()
  end
end
