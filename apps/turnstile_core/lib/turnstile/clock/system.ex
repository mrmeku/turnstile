defmodule Turnstile.Clock.System do
  @moduledoc "The system clock."

  @behaviour Turnstile.Clock

  @impl Turnstile.Clock
  def now, do: DateTime.utc_now()
end
