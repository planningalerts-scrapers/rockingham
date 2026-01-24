#!/usr/bin/env ruby
# frozen_string_literal: true

require "scraperwiki"
require "mechanize"

class Scraper
  BASE_URL = "https://rockingham.wa.gov.au"
  LISTING_URL = "#{BASE_URL}/planning-and-building/local-planning/town-planning-advertising-and-submissions"
  STATE = "WA"

  attr_accessor :pause_duration

  def initialize
    @pause_duration = 0.0
  end

  def clean_whitespace(text)
    text.gsub("\r", " ").gsub("\n", " ").squeeze(" ").strip
  end

  def parse_date(date_string)
    # Parse dates like "27 January 2026"
    Date.parse(date_string).to_s
  rescue ArgumentError
    nil
  end

  def generate_council_reference(title)
    # Sanitize: replace non-alphanumeric with space, squeeze, strip
    sanitized = title.gsub(/[^A-Za-z0-9]+/, " ").squeeze(" ").strip

    # Truncate to 49 chars and add hyphen if truncated
    if sanitized.length > 49
      sanitized[0..48] + "-"
    else
      sanitized
    end
  end

  def extract_address_from_details(agent, info_url, fallback_address)
    puts "  Pausing #{@pause_duration}s"
    sleep(@pause_duration)

    puts "  Fetching detail page: #{info_url}"
    start_time = Time.now.to_f
    detail_page = agent.get(info_url)
    @pause_duration = (Time.now.to_f - start_time + 0.5).round(3)

    # Look for patterns like "Lot 160 (No.48) Lookout Vista, Singleton"
    # or "No.38 Emerald Court, Singleton"
    # or "Lot 1023 (No.47) Young Road, Baldivis"
    content = detail_page.search("div.content-main").text

    # Pattern 1: Lot XXX (No.YY) Street, Suburb
    if content =~ /Lot\s+\d+\s+\(No\.(\d+)\)\s+([^,\.]+),\s*([^,\.]+)/i
      street_no = ::Regexp.last_match(1)
      street = ::Regexp.last_match(2).strip
      suburb = ::Regexp.last_match(3).strip
      address = "#{street_no} #{street}, #{suburb}, #{STATE}"
      puts "  Extracted address: #{address}"
      return address
    end

    # Pattern 2: No.XX Street, Suburb
    if content =~ /\bNo\.(\d+)\s+([^,\.]+),\s*([^,\.]+)/i
      street_no = ::Regexp.last_match(1)
      street = ::Regexp.last_match(2).strip
      suburb = ::Regexp.last_match(3).strip
      address = "#{street_no} #{street}, #{suburb}, #{STATE}"
      puts "  Extracted address: #{address}"
      return address
    end

    # Pattern 3: Lot XXXX Street, Suburb (without No.)
    if content =~ /Lot\s+\d+\s+([^,\.]+),\s*([^,\.]+)/i
      street = ::Regexp.last_match(1).strip
      suburb = ::Regexp.last_match(2).strip
      address = "#{street}, #{suburb}, #{STATE}"
      puts "  Extracted address: #{address}"
      return address
    end

    puts "  Using fallback address: #{fallback_address}"
    fallback_address
  rescue StandardError => e
    puts "  Error fetching detail page #{info_url}: #{e.message}"
    fallback_address
  end

  def run
    agent = Mechanize.new
    agent.verify_mode = OpenSSL::SSL::VERIFY_NONE

    puts "Getting listing page"
    start_time = Time.now.to_f
    page = agent.get(LISTING_URL)
    @pause_duration = (Time.now.to_f - start_time + 0.5).round(3)

    cards = page.search("a.hotbox")
    added = found = 0

    cards.each do |card|
      found += 1

      href = card["href"]
      info_url = "#{BASE_URL}#{href}"

      # Get title from h4
      title_elem = card.at("h4")
      next unless title_elem

      title = clean_whitespace(title_elem.text)

      # Parse title: "Description - Address" format
      unless title =~ /\A(.+?)\s+-\s+(.+)\z/
        puts "Warning - Unable to parse title format: #{title} (skipped)"
        next
      end

      description = ::Regexp.last_match(1).strip
      address_snippet = ::Regexp.last_match(2).strip

      # Generate council reference from full title
      council_reference = generate_council_reference(title)

      # Extract closing date from paragraph
      on_notice_to = nil
      para = card.at("p")
      if para
        text = clean_whitespace(para.text)
        if text =~ /Submissions close\s+(.+)\./
          on_notice_to = parse_date(::Regexp.last_match(1))
        end
      end

      # Fetch detail page to get better address
      fallback_address = "#{address_snippet}, #{STATE}"
      address = extract_address_from_details(agent, info_url, fallback_address)

      record = {
        "council_reference" => council_reference,
        "address" => address,
        "description" => description,
        "info_url" => info_url,
        "date_scraped" => Date.today.to_s,
      }
      record["on_notice_to"] = on_notice_to if on_notice_to

      added += 1
      puts "Saving record #{council_reference} - #{address}"
      ScraperWiki.save_sqlite(["council_reference"], record)
    end

    # Clean up applications older than 30 days
    cutoff_date = (Date.today - 30).to_s
    puts "Deleting applications scraped before #{cutoff_date}"
    deleted_count = ScraperWiki.sqliteexecute(
      "SELECT COUNT(*) FROM data WHERE date_scraped < ?",
      [cutoff_date]
    ).first.values.first
    ScraperWiki.sqliteexecute("DELETE FROM data WHERE date_scraped < ?", [cutoff_date])

    puts "  Deleted #{deleted_count} applications" if deleted_count.positive?
    skipped = found - added
    puts "Finished! Added #{added} applications, and skipped #{skipped} unprocessable applications."
  end
end

Scraper.new.run if __FILE__ == $PROGRAM_NAME
