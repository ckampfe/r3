defmodule R3.Repo.Migrations.CreateFeeds do
  use Ecto.Migration

  def change do
    create_if_not_exists table(:feeds) do
      add :title, :text
      add :feed_link, :text
      add :link, :text
      add :feed_kind, :text
      add :refreshed_at, :utc_datetime
      add :etag, :text

      timestamps(type: :utc_datetime)
    end

    # sqlx::query("CREATE UNIQUE INDEX IF NOT EXISTS feeds_feed_link ON feeds (feed_link)")
    create_if_not_exists unique_index(:feeds, [:feed_link])
  end
end
