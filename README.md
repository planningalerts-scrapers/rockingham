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

```
Getting listing page
  Pausing 0.828s
  Fetching detail page: https://rockingham.wa.gov.au/planning-and-building/local-planning/town-planning-advertising-and-submissions/proposed-home-business-lookout-vista,-singleton
Saving record Proposed Home Business Lookout Vista Singleton - Lot 160, 48 Lookout Vista, Singleton, WA
...
Deleting applications scraped before 2025-12-26
Finished! Added 4 applications, and skipped 0 unprocessable applications.
```

Execution time: ~ 10 seconds

## To run style and coding checks

    bundle exec rubocop

## To check for security updates

    gem install bundler-audit
    bundle-audit
