#!/usr/bin/env ruby
# frozen_string_literal: true

require "yaml"
require "rss"
require "net/http"
require "date"
require "time"
require "uri"
require "optparse"

LAST_RUN_FILE = ".last_run"
CONFIG_FILE = "config.yml"

class FeedFetcher
  Item = Data.define(:title, :link, :date)
  FeedResult = Data.define(:title, :link, :items) do
    def empty? = items.empty?
  end

  def initialize(urls, since)
    @urls = urls
    @since = since
  end

  def fetch_all
    threads = @urls.map do |url|
      Thread.new { fetch_one(url) }
    end

    threads.map(&:join).map(&:value).compact
  end

  private

  def fetch_one(url)
    content = fetch_content(url)
    feed = RSS::Parser.parse(content, false)
    FeedResult.new(
      title: feed_title(feed, url),
      link: feed_link(feed, url),
      items: extract_items(feed)
    )
  rescue => e
    puts "Error fetching #{url}: #{e.message}"
    nil
  end

  def fetch_content(url, redirect_limit = 5)
    raise "Too many redirects" if redirect_limit == 0

    uri = URI.parse(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = 10
    http.read_timeout = 10

    request = Net::HTTP::Get.new(uri.request_uri)
    response = http.request(request)

    case response
    when Net::HTTPSuccess
      response.body
    when Net::HTTPRedirection
      fetch_content(response["location"], redirect_limit - 1)
    else
      raise "HTTP #{response.code}: #{response.message}"
    end
  end

  def extract_items(feed)
    items = []

    case feed
    when RSS::Atom::Feed
      feed.entries.each do |entry|
        pub_date = entry.updated&.content || entry.published&.content
        next unless pub_date && pub_date > @since

        items << Item.new(
          title: (entry.title&.content || "Untitled").gsub(/\s+/, " ").strip,
          link: entry.link&.href || entry.links.first&.href,
          date: pub_date
        )
      end
    when RSS::Rss
      feed.items.each do |item|
        pub_date = item.pubDate || item.date
        next unless pub_date && pub_date > @since

        items << Item.new(
          title: (item.title || "Untitled").gsub(/\s+/, " ").strip,
          link: item.link,
          date: pub_date
        )
      end
    end

    items.sort_by(&:date).reverse
  end

  def feed_title(feed, url)
    case feed
    when RSS::Atom::Feed
      feed.title&.content || url
    when RSS::Rss
      feed.channel&.title || url
    else
      url
    end
  end

  def feed_link(feed, url)
    case feed
    when RSS::Atom::Feed
      feed.links.find { |l| l.rel.nil? || l.rel == "alternate" }&.href || url
    when RSS::Rss
      feed.channel&.link || url
    else
      url
    end
  end
end

class DigestGenerator
  def initialize(name, feeds, since)
    @name = name
    @feeds = feeds
    @since = since
  end

  def generate(dry_run: false)
    puts "Processing digest: #{@name} (#{@feeds.length} feeds)"

    feed_results = FeedFetcher.new(@feeds, @since).fetch_all

    if feed_results.all?(&:empty?)
      puts "No new items for #{@name}, skipping"
      return
    end

    content = build_content(feed_results)

    if !dry_run
      write_file(content)
      return
    end

    puts "=== #{output_filename} ==="
    puts content
    puts "=== End of #{output_filename} ==="
  end

  private

  def output_filename
    "#{@name}.md"
  end

  def build_content(feed_results)
    title = @name.capitalize
    lines = ["# #{title} Digest - #{Date.today}"]
    lines << ""

    feed_results.each do |result|
      next if result.items.empty?

      lines << "- [#{result.title}](#{result.link})"
      result.items.each do |item|
        lines << "  - [#{item.title}](#{item.link})"
      end
    end

    lines.join("\n") + "\n"
  end

  def write_file(content)
    File.write(output_filename, content)
    puts "Wrote digest to #{output_filename}"
  end
end

if __FILE__ == $0
  dry_run = false

  since = if File.exist?(LAST_RUN_FILE)
    Time.parse(File.read(LAST_RUN_FILE).strip)
  else
    Time.now - (24 * 60 * 60)
  end
  puts "Checking for items since: #{since.iso8601}"

  digests = if File.exist?(CONFIG_FILE)
    YAML.load_file(CONFIG_FILE).fetch("digests", {})
  else
    {}
  end
  puts "Found #{digests.length} digest(s) in config"

  OptionParser.new do |opts|
    opts.on("-n", "--dry-run", "Print to stdout instead of writing files") { dry_run = true }
  end.parse!

  digests.each do |name, feeds|
    DigestGenerator.new(name, feeds, since).generate(dry_run:)
  end

  if !dry_run
    File.write(LAST_RUN_FILE, Time.now.iso8601)
    puts "Updated #{LAST_RUN_FILE}"
  end
end
