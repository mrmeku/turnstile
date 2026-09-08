defmodule Turnstile.Repo.CallerTest do
  use ExUnit.Case, async: true

  alias Turnstile.Repo.Caller
  alias Turnstile.TestRepos.Sandboxed

  test "library?/1 is true for Turnstile and the modules under it, false for :any and others" do
    assert Caller.library?(Turnstile)
    assert Caller.library?(Turnstile.Repo.Seam)
    refute Caller.library?(:any)
    refute Caller.library?(Enum)
  end

  test "module/1 names the first frame outside the repo, the seam, Ecto, and the standard library" do
    frame = Caller.module(Sandboxed)
    assert frame == __MODULE__
  end

  test "module/1 answers :any when no frame qualifies" do
    assert :any = Task.await(Task.async(Caller, :module, [Sandboxed]))
  end
end
