# Trial run: method 2 plans

These files come from a trial run of the same queries on the same machine, earlier on the same day as the published run in `../pg16/`. The trial used `setup.sql` before the `SET TimeZone` line was added; the server time zone was Europe/Prague, which follows the same rules as Europe/Berlin, and the result hashes are identical to the published run (`2e045ca9`, `50241c24`).

They are kept only to document one observation quoted in the article: with freshly sampled statistics, the planner chose a different plan for the `DISTINCT ON` query (a parallel index scan on `shipment_pkey` with an incremental sort, no spill to disk) instead of the full sort used in the published run. The timings here are not used anywhere else in the article.
