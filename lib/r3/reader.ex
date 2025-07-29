defmodule R3.Reader do
  require Logger
  alias R3.Repo
  alias R3.Reader.{Entry, Feed}
  import Ecto.Query

  def feed_exists?(feed_link) do
    Feed
    |> where([f], f.feed_link == ^feed_link)
    |> select([f], true)
    |> Repo.one()
  end

  def add_feed(parsed_feed, feed_kind, feed_link) do
    Repo.transact(fn ->
      feed =
        %Feed{feed_link: feed_link, feed_kind: Atom.to_string(feed_kind)}
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

  def refresh_feed(feed_id) do
    feed =
      Feed
      |> where([f], f.id == ^feed_id)
      |> select([:id, :feed_link, :latest_etag])
      |> Repo.one!()

    headers = [{"User-Agent", "r3/0.1"}]

    headers =
      if feed.latest_etag do
        [{"If-None-Match", feed.latest_etag} | headers]
      else
        headers
      end

    {:ok, feed_response} =
      Req.get(url: feed.feed_link, headers: headers, http_errors: :raise)

    case feed_response.status do
      304 ->
        Logger.debug("#{feed.feed_link}: got 304, feed is the same")
        {:ok, 0}

      200 ->
        Logger.debug("#{feed.feed_link}: got 200, feed has changed, calculating new entries")

        {:ok, _feed_kind, challenger_feed} = try_to_parse_feed(feed_response.body)

        existing_entries_links =
          Entry
          |> where([e], e.feed_id == ^feed_id)
          |> select([e], e.link)
          |> Repo.all()
          |> MapSet.new()

        new_entries =
          challenger_feed
          |> Map.fetch!("entries")
          |> Enum.reject(fn entry ->
            MapSet.member?(existing_entries_links, Map.fetch!(entry, "link"))
          end)

        Repo.transact(fn ->
          now = DateTime.utc_now()

          feed_query =
            Feed
            |> where([f], f.id == ^feed_id)
            |> update([f], set: [refreshed_at: ^now])

          feed_query =
            if etag = feed_response.headers["etag"] do
              [etag] = etag
              etag = String.replace(etag, "\"", "")
              update(feed_query, [f], set: [latest_etag: ^etag])
            else
              feed_query
            end

          Repo.update_all(feed_query, [])

          new_entry = Ecto.build_assoc(feed, :entries)

          # again N+1, but find because of SQLite
          Enum.each(new_entries, fn entry ->
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

        {:ok, Enum.count(new_entries)}
    end
  end

  def try_to_parse_feed(s) when is_binary(s) do
    case FastRSS.parse_rss(s) do
      {:ok, challenger_feed} ->
        {items, challenger_feed} = Map.pop!(challenger_feed, "items")
        {:ok, :rss, Map.put(challenger_feed, "entries", items)}

      {:error, _} ->
        Logger.debug("could not parse as RSS, trying as Atom")

        {:ok, challenger_feed} = FastRSS.parse_atom(s)

        challenger_feed =
          Map.update!(challenger_feed, "entries", fn entries ->
            Enum.map(entries, fn entry ->
              {links, entry} = Map.pop!(entry, "links")

              link =
                links
                |> List.first()
                |> Map.fetch!("href")

              entry = Map.put(entry, "link", link)

              {pub_date, entry} = Map.pop!(entry, "published")

              entry = Map.put(entry, "pub_date", pub_date)

              {%{"value" => title}, entry} = Map.pop!(entry, "title")

              entry = Map.put(entry, "title", title)

              {%{"value" => content}, entry} = Map.pop!(entry, "content")

              Map.put(entry, "content", content)
            end)
          end)

        {:ok, :atom, challenger_feed}
    end
  end
end
