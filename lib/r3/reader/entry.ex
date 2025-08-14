defmodule R3.Reader.Entry do
  use Ecto.Schema
  import Ecto.Changeset

  schema "entries" do
    field :title, :string
    field :author, :string
    field :pub_date, :utc_datetime
    field :description, :string
    field :content, :string
    field :link, :string
    field :read_at, :utc_datetime

    belongs_to :feed, R3.Reader.Feed

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [:title, :author, :pub_date, :description, :content, :link, :read_at])
    |> validate_required([:title, :link])
  end
end
