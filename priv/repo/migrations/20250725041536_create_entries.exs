defmodule R3.Repo.Migrations.CreateEntries do
  use Ecto.Migration

  def change do
    create_if_not_exists table(:entries) do
      add :title, :text
      add :author, :text
      add :pub_date, :utc_datetime
      add :description, :text
      add :content, :text
      add :link, :text
      add :read_at, :utc_datetime
      add :feed_id, references(:feeds, on_delete: :nothing)

      timestamps(type: :utc_datetime)
    end

    create_if_not_exists index(:entries, [:feed_id])
    create_if_not_exists index(:entries, [:feed_id, :pub_date, :inserted_at])
  end
end
