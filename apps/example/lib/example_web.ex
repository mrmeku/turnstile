defmodule ExampleWeb do
  @moduledoc """
  The example over JSON: the routes, the two controllers, and the plug that
  identifies the caller. It authorizes nothing. Every rule is asked at the
  port by the contexts of `Example`, and what this layer does is read who
  is asking from the headers an authenticating proxy sets, hand the subject
  and the facts to a context, and turn what the context answered into a
  status and a body.
  """

  use Boundary, deps: [Example, Phoenix, Plug], exports: [DocumentController, Identity, ProposalController, Router]
end
