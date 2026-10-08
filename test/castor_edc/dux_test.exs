defmodule CastorEDC.DuxTest do
  use ExUnit.Case

  doctest CastorEDC.Dux

  test "greets the world" do
    assert CastorEDC.Dux.hello() == :world
  end
end
