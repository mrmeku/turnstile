defmodule Mix.Tasks.Turnstile.ReviewTest do
  use ExUnit.Case, async: false

  alias Mix.Tasks.Turnstile.Review

  @golden "test/golden/review.txt"

  setup do
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
  end

  test "it prints the review the reporter named in mix.exs answers, for today" do
    Review.run([])

    assert_received {:mix_shell, :info, [table]}
    assert table == File.read!(@golden)
  end

  test "it takes no arguments, because a date is what point-in-time review adds" do
    assert_raise Mix.Error, ~r/takes no arguments/, fn -> Review.run(["--at", "2026-03-01"]) end
  end
end
