defmodule Example.Scenarios.Ledger do
  @moduledoc """
  The scenarios marked `ledger` in the reference's table. They run only when
  the boot config names a ledger; their bodies arrive with the ledger stage
  and fail plainly until then, so a run that includes them cannot pass by
  accident.
  """

  use Boundary, top_level?: true, deps: [ExUnit]

  import ExUnit.Assertions

  @spec rev_07() :: no_return()
  def rev_07, do: pending("rev-07")

  @spec aud_04() :: no_return()
  def aud_04, do: pending("aud-04")

  @spec aud_05() :: no_return()
  def aud_05, do: pending("aud-05")

  @spec aud_06() :: no_return()
  def aud_06, do: pending("aud-06")

  @spec aud_08() :: no_return()
  def aud_08, do: pending("aud-08")

  @spec rvw_02() :: no_return()
  def rvw_02, do: pending("rvw-02")

  @spec rvw_03() :: no_return()
  def rvw_03, do: pending("rvw-03")

  @spec rvw_04() :: no_return()
  def rvw_04, do: pending("rvw-04")

  @spec cm_01() :: no_return()
  def cm_01, do: pending("cm-01")

  @spec cm_02() :: no_return()
  def cm_02, do: pending("cm-02")

  defp pending(id), do: flunk("#{id} needs the ledger's fact events, which the ledger stage adds")
end
