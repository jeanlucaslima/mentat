defmodule Mentat.Repo do
  use Ecto.Repo,
    otp_app: :mentat,
    adapter: Ecto.Adapters.Postgres
end
