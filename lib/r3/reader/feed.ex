defmodule R3.Reader.Feed do
  use Ecto.Schema
  import Ecto.Changeset

  schema "feeds" do
    field :title, :string
    field :feed_link, :string
    field :link, :string
    field :feed_kind, :string
    field :refreshed_at, :utc_datetime
    field :etag, :string

    has_many :entries, R3.Reader.Entry

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(feed, attrs) do
    feed
    |> cast(attrs, [:title, :feed_link, :link, :feed_kind, :refreshed_at, :etag])
    |> validate_required([:title, :feed_link, :feed_kind])
    |> validate_inclusion(:feed_kind, ["atom", "rss"])
  end
end
