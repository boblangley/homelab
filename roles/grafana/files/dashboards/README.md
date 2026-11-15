# Grafana dashboards

Role `grafana` provisions every `*.json` file here into Grafana, read-only, and removes from Grafana any dashboard
whose file is removed. A subdirectory becomes a Grafana folder (one level only); files at the top level go to the
General folder.

To add or change one:

1. Build it in Grafana, outside these folders (dashboards made in the UI live in Grafana's database).
2. Share → Export → JSON, with **Export for sharing externally** off, so panels keep the data source uid
   `clickhouse` rather than an `${DS_...}` input.
3. Give it a stable `uid` and set `id` to `null`, save it here, and open a pull request.

After the merge, Apply copies it to wtr-pro and Grafana loads it within a minute. Delete the UI copy afterwards.
