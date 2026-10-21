defmodule Sprout.Repo do
  @moduledoc "PostgreSQL repository shared by Sprout’s domain contexts."
  use Ecto.Repo,
    otp_app: :sprout,
    adapter: Ecto.Adapters.Postgres
end
