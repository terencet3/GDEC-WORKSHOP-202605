# Extended Troubleshooting Matrix

This is the long-form companion to Section 6.1 of the runbook. HSE keeps it open during delivery.

## Cortex Code in Snowsight

| Symptom | Diagnosis steps | Fix |
|---|---|---|
| Cortex Code icon missing in workspace | Check account previously opted out of Snowflake Copilot | Open ticket with account team to re-enable; route attendee to backup environment |
| "Model unavailable" error | Region doesn't have Claude available | `ALTER ACCOUNT SET CORTEX_ENABLED_CROSS_REGION = 'AWS_US';` (requires ACCOUNTADMIN) |
| Diff view empty after prompt | Active SQL file not focused | Click into the SQL file tab, then re-issue prompt |
| `@` catalog picker shows no objects | Role lacks USAGE on database | `GRANT USAGE ON DATABASE GDEC_DEMO TO ROLE <role>;` |
| Streamlit app creation fails | Role lacks `CREATE STREAMLIT` on schema | `GRANT CREATE STREAMLIT ON SCHEMA GDEC_DEMO.COMMERCE TO ROLE <role>;` |

## CoCo CLI

| Symptom | Diagnosis steps | Fix |
|---|---|---|
| `cortex: command not found` | New shell hasn't loaded updated PATH | Open new terminal, or `source ~/.zshrc` / `source ~/.bashrc` |
| Setup wizard shows no connections | `~/.snowflake/connections.toml` missing | Create the file with the workshop connection block; HSE has the template |
| "Authentication failed" on first prompt | Wrong default role for the connection | Edit `connections.toml` to set `role = "<workshop_role>"` |
| Generated SQL references wrong DB/schema | Active context not set | In CoCo prompt: `use database GDEC_DEMO; use schema COMMERCE;` then re-ask |
| File diffs not appearing | CoCo running outside the project directory | `cd ~/gdec_lab2` and re-run `cortex` |

## Snowflake Intelligence

| Symptom | Diagnosis steps | Fix |
|---|---|---|
| "Create agent" greyed out | Not on `SNOWFLAKE_INTELLIGENCE_ADMIN` role | Switch role in lower-left of Snowsight |
| Semantic view stuck "Building" | Underlying tables locked or warehouse suspended | Check warehouse status; resume `WH_COCO_AI` if suspended |
| Agent answers "I don't have a tool for that" | Semantic view not attached, or tool description too narrow | Re-check Tools tab; broaden the description |
| Question times out | Warehouse cold or query expensive | Add a date window to the question; increase agent query timeout to 90s |
| Chart doesn't render | `data_to_chart` tool not enabled | Edit agent: Tools \u2192 add `data_to_chart` tool |

## Snowflake Postgres

| Symptom | Diagnosis steps | Fix |
|---|---|---|
| `CREATE POSTGRES INSTANCE` permission denied | Privilege not granted | `GRANT CREATE POSTGRES INSTANCE ON ACCOUNT TO ROLE <role>;` |
| Instance stuck in `CREATING` > 8 min | Region capacity issue | Drop and recreate; if persists, escalate |
| `psql` connection refused / timeout | IP not in network policy | `ALTER NETWORK POLICY GDEC_PG_NETPOL SET ALLOWED_IP_LIST = (..., '<new_ip>');` |
| `psql` "authentication failed" | Wrong password or wrong user (`snowflake_admin` vs. `application`) | Use `application` user; if password lost, regenerate via `ALTER POSTGRES INSTANCE ... RESET CREDENTIALS` |
| `CREATE EXTENSION pg_lake` fails | Burstable instance | Drop and recreate at `STANDARD_S` |
| Catalog integration fails | `POSTGRES_INSTANCE` value mismatch | Run `SHOW POSTGRES INSTANCES` and copy the exact name |
| Iceberg table returns 0 rows in Snowflake | Auto-refresh hasn't polled | `ALTER ICEBERG TABLE <name> REFRESH;` |
| Cleanup blocked: cannot drop instance | Catalog integration or Iceberg table still references it | Drop Iceberg tables first, then catalog integration, then instance |

## Quick reset for an attendee

If an attendee's environment is unrecoverable in <2 min, route them to the backup account:

1. HSE shares backup credentials.
2. Attendee logs into backup Snowsight (different URL).
3. They run lab steps against the pre-loaded `GDEC_DEMO` and the shared `gdec_pg_shared` instance, using their assigned `<NN>` for object naming so they don't collide.
