defmodule Gallformers.Phenology.SeasonalClockTest do
  use ExUnit.Case, async: true
  alias Gallformers.Phenology.SeasonalClock, as: Clock

  test "finite latitude support and all interpolated landmarks are ordered" do
    refute Clock.supported_latitude?(nil)
    refute Clock.supported_latitude?(-30)
    refute Clock.supported_latitude?(55.01)

    for i <- 250..550 do
      lat = i / 10
      assert Clock.supported_latitude?(lat) == true
      {spring, autumn} = Clock.anchors(lat)
      assert spring < autumn and autumn < spring + 365

      for day <- [0, 60, 180, 300, 370] do
        assert_in_delta Clock.inverse(Clock.coordinate(day, lat), lat), day, 1.0e-8
      end
    end
  end
end
