defmodule Mosaic.Repo do
  use Ecto.Repo,
    otp_app: :mosaic,
    adapter: Ecto.Adapters.Postgres
end
