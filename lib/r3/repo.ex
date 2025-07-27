defmodule R3.Repo do
  use Ecto.Repo,
    otp_app: :r3,
    adapter: Ecto.Adapters.SQLite3
end
