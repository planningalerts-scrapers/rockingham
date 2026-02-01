# City of Rockingham - Town planning advertising and submissions

* Cookie tracking - No
* Pagnation - none obvious
* JavaScript - No
* Clearly defined data within a row - Clear enough in HTML dom, with additional address details in free text in details page
* System - custom

This is a scraper that runs on [Morph](https://morph.io).
To get started [see the documentation](https://morph.io/documentation)

Add any issues to https://github.com/planningalerts-scrapers/issues/issues

## To run the scraper

    bundle exec ruby scraper.rb

### Expected output

    Getting listing page
      Pausing 4.057s
      Fetching detail page: https://rockingham.wa.gov.au/planning-and-building/local-planning/town-planning-advertising-and-submissions/proposed-oilseed-processing-plant-patterson-road,-
    Saving record Proposed Oilseed Processing Plant Patterson Road - - Lot 9008 Patterson Road, East Rockingham, WA
    ...
      Pausing 3.815s
      Fetching detail page: https://rockingham.wa.gov.au/planning-and-building/local-planning/town-planning-advertising-and-submissions/proposed-holiday-house-emerald-court,-singleton
    Saving record Proposed Holiday House Emerald Court Singleton - 38 Emerald Court, Singleton, WA
    Deleting 0 applications scraped between  and 2025-12-28
      Running VACUUM to reclaim space...
    Finished! Added 3 applications, and skipped 0 unprocessable applications.

Execution time: ~ 30 seconds

## To run style and coding checks

    bundle exec rubocop

## To check for security updates

    gem install bundler-audit
    bundle-audit
