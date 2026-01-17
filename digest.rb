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

Item = Data.define(:title, :link, :date)
FeedResult = Data.define(:title, :link, :items) do
  def empty?
    items.empty?
  end
end

def read_last_run
  return Time.now - (24 * 60 * 60) unless File.exist?(LAST_RUN_FILE)

  Time.parse(File.read(LAST_RUN_FILE).strip)
end

def read_digests
  return {} unless File.exist?(CONFIG_FILE)

  YAML.load_file(CONFIG_FILE).fetch("digests", {})
end

def fetch_feed(url, redirect_limit = 5)
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
    fetch_feed(response["location"], redirect_limit - 1)
  else
    raise "HTTP #{response.code}: #{response.message}"
  end
end

def extract_items(feed, since)
  items = []

  case feed
  when RSS::Atom::Feed
    feed.entries.each do |entry|
      pub_date = entry.updated&.content || entry.published&.content
      next unless pub_date && pub_date > since

      items << Item.new(
        title: (entry.title&.content || "Untitled").gsub(/\s+/, " ").strip,
        link: entry.link&.href || entry.links.first&.href,
        date: pub_date
      )
    end
  when RSS::Rss
    feed.items.each do |item|
      pub_date = item.pubDate || item.date
      next unless pub_date && pub_date > since

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

def generate_digest(name, feed_results)
  title = name.capitalize
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

def fetch_feeds(urls, since)
  threads = urls.map do |url|
    Thread.new do
      content = fetch_feed(url)
      feed = RSS::Parser.parse(content, false)
      items = extract_items(feed, since)
      FeedResult.new(
        title: feed_title(feed, url),
        link: feed_link(feed, url),
        items: items
      )
    rescue => e
      puts "Error fetching #{url}: #{e.message}"
      nil
    end
  end

  threads.map(&:join).map(&:value).compact
end

def write_digest_file(filename, content)
  File.write(filename, content)
  puts "Wrote digest to #{filename}"
end

def update_last_run
  File.write(LAST_RUN_FILE, Time.now.iso8601)
  puts "Updated #{LAST_RUN_FILE}"
end

def generate(dry_run: false)
  since = read_last_run
  puts "Checking for items since: #{since.iso8601}"

  digests = read_digests
  puts "Found #{digests.length} digest(s) in config"

  digests.each do |name, feeds|
    puts "Processing digest: #{name} (#{feeds.length} feeds)"

    feed_results = fetch_feeds(feeds, since)

    if feed_results.all?(&:empty?)
      puts "No new items for #{name}, skipping"
      next
    end

    output_filename = "#{name}.md"
    digest_content = generate_digest(name, feed_results)

    if dry_run
      puts "=== #{output_filename} ==="
      puts digest_content
      puts "=== End of #{output_filename} ==="
      next
    end

    write_digest_file(output_filename, digest_content)
  end
end

dry_run = false
if __FILE__ == $0
  OptionParser.new do |opts|
    opts.on("-n", "--dry-run", "Print to stdout instead of writing files") { dry_run = true }
  end.parse!
end

generate(dry_run:)
update_last_run unless dry_run
