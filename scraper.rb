#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
Bundler.require

require "scraperwiki"
require "mechanize"

class Scraper
  BASE_URL = "https://rockingham.wa.gov.au"
  LISTING_URL = "https://yourthoughts.rockingham.wa.gov.au/town-planning-advertising-and-submissions"
  STATE = "WA"

  def clean_whitespace(text)
    text.gsub("\r", " ").gsub("\n", " ").squeeze(" ").strip
  end

  def parse_date(date_string)
    # Parse dates like "27 January 2026"
    Date.parse(date_string).to_s
  rescue ArgumentError
    nil
  end

  # Throttle block to be nice to servers we are scraping
  def throttle_block(extra_delay: 0.5)
    if @pause_duration
      puts "  Pausing #{@pause_duration}s"
      sleep(@pause_duration)
    end
    start_time = Time.now.to_f
    page = yield
    @pause_duration = (Time.now.to_f - start_time + extra_delay).round(3)
    page
  end

  # Cleanup and vacuum database of old records (planning alerts only looks at last 5 days)
  def cleanup_old_records
    cutoff_date = (Date.today - 30).to_s
    vacuum_cutoff_date = (Date.today - 35).to_s

    stats = ScraperWiki.sqliteexecute(
      "SELECT COUNT(*) as count, MIN(date_scraped) as oldest FROM data WHERE date_scraped < ?",
      [cutoff_date]
    ).first

    deleted_count = stats["count"]
    oldest_date = stats["oldest"]

    return unless deleted_count.positive? || ENV["VACUUM"]

    puts "Deleting #{deleted_count} applications scraped between #{oldest_date} and #{cutoff_date}"
    ScraperWiki.sqliteexecute("DELETE FROM data WHERE date_scraped < ?", [cutoff_date])

    # VACUUM roughly once each 33 days or if older than 35 days (first time) or if VACUUM is set
    return unless rand < 0.03 || (oldest_date && oldest_date < vacuum_cutoff_date) || ENV["VACUUM"]

    puts "  Running VACUUM to reclaim space..."
    ScraperWiki.sqliteexecute("VACUUM")
  end

  def generate_council_reference(title)
    # Sanitize: replace non-alphanumeric characters with space, strip
    sanitized = title.gsub(/[^A-Za-z0-9]+/, " ").strip

    # Truncate to 49 chars and add hyphen if truncated
    if sanitized.length > 49
      sanitized[0..48] + "-"
    else
      sanitized
    end
  end

  def extract_address_from_details(agent, info_url, address_snippet)
    detail_page = throttle_block do
      puts "  Fetching detail page: #{info_url}"
      agent.get(info_url)
    end

    # Look for the Proposal section
    proposal_heading = detail_page.search("h2").find { |h2| h2.text.strip =~ /\AProposal\z/i }

    unless proposal_heading
      puts "  No Proposal section found"
      return nil
    end

    # Get the next paragraph after the Proposal heading
    next_p = proposal_heading.next_element
    next_p = next_p.next_element while next_p && next_p.name != "p"

    unless next_p
      puts "  No paragraph after Proposal heading"
      return nil
    end

    content = next_p.text
    escaped_snippet = Regexp.escape(address_snippet)

    if ENV["DEBUG"]
      puts "Matching address snippet: #{address_snippet.inspect}",
           "in paragraph: #{content.inspect}"
    end

    # Match address snippet with "No. NN" (optionally surrounded by brackets, optionally preceded by a Lot
    if content =~ /(Lot\s*\d\w*\s+)?\(?No\.([^)]+)\)?(.*?#{escaped_snippet})/i
      lot = ::Regexp.last_match(1)&.strip
      street_no = ::Regexp.last_match(2).strip
      remaining_address = ::Regexp.last_match(3).strip
      address = "#{lot ? "#{lot}, " : ''}#{street_no} #{remaining_address}"
      puts "  Extracted street address: #{address}" if ENV["DEBUG"]
      return address
    end

    # Match address snippet with "Lot"
    if content =~ /(Lot.*?#{escaped_snippet})/i
      address = ::Regexp.last_match(1)&.strip
      puts "  Extracted Lot address: #{address}" if ENV["DEBUG"]
      return address
    end

    puts "  Unable to find full address ending in #{address_snippet.inspect}"
    nil
  rescue StandardError => e
    puts "  Error fetching detail page #{info_url}: #{e.message}"
    nil
  end

  def run
    agent = Mechanize.new
    agent.verify_mode = OpenSSL::SSL::VERIFY_NONE

    page = throttle_block do
      puts "Getting listing page"
      agent.get(LISTING_URL)
    end

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
        on_notice_to = parse_date(::Regexp.last_match(1)) if text =~ /Submissions close\s+(.+)\./
      end

      # Fetch detail page to get better address
      address = extract_address_from_details(agent, info_url, address_snippet) || address_snippet
      address = "#{address}, #{STATE}" unless address.end_with?(" #{STATE}")

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

    cleanup_old_records
    skipped = found - added
    puts "Finished! Added #{added} applications, and skipped #{skipped} unprocessable applications."
  end
end

Scraper.new.run if __FILE__ == $PROGRAM_NAME
