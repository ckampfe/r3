defmodule R3Web.ErrorJSONTest do
  use R3Web.ConnCase, async: true

  test "renders 404" do
    assert R3Web.ErrorJSON.render("404.json", %{}) == %{errors: %{detail: "Not Found"}}
  end

  test "renders 500" do
    assert R3Web.ErrorJSON.render("500.json", %{}) ==
             %{errors: %{detail: "Internal Server Error"}}
  end
end
