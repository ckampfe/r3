defmodule Reader do
  alias R3.Repo
  import Ecto.Query
  alias R3.Reader.{Entry, Feed}

  def feed_exists?(feed_link) do
    Feed
    |> where([f], f.feed_link == ^feed_link)
    |> select([f], true)
    |> Repo.one()
  end

  def add_feed(parsed_feed, feed_link) do
    Repo.transact(fn ->
      feed =
        %Feed{feed_link: feed_link, feed_kind: "rss"}
        |> Feed.changeset(parsed_feed)
        |> Repo.insert!()

      new_entry =
        Ecto.build_assoc(feed, :entries)

      parsed_feed
      |> Map.fetch!("items")
      |> Enum.map(fn entry ->
        # TODO where should this go?
        # here or in Entry.changeset/2?
        entry =
          entry
          |> Map.update!("pub_date", fn
            nil ->
              nil

            pub_date ->
              DateTimeParser.parse_datetime!(pub_date)
          end)

        new_entry
        |> Entry.changeset(entry)
        |> Repo.insert!()
      end)

      {:ok, nil}
    end)
  end

  def toggle_read_at(entry_id) do
    now = DateTime.utc_now()

    {1, [read_at]} =
      Entry
      |> where([e], e.id == ^entry_id)
      |> update([e],
        set: [
          read_at: fragment("case when read_at is null then ? else null end", ^now)
        ]
      )
      |> select([e], e.read_at)
      |> Repo.update_all([])

    {:ok, read_at}
  end
end
