iCloudEMS Support Engineer (AI) - Technical Assignment

Database: MySQL (queries are MySQL-compatible; also tested on MariaDB 10.11).

Files
solution_queries.sql - all SQL for Task 1, 2, 3 (and verification queries for Task 4/5), labelled by sub-task
assignment_report.md - findings, root-cause analysis, and written answers for Tasks 1-5
query_output.txt - actual executed query output
screenshot/ - result screenshots from MySQL Workbench
Summary
Task 1: duplicates, outstanding dues, top students/programs, parent-child reconciliation
Task 2: ADM10025 - Exam Fee detail row (Rs 5,000) missing for PAID txn 518 because the detail insert failed and was not rolled back; due job sums details so it showed Rs 5,000 due
Task 3: amount and count reconciliation with MATCH/MISMATCH report
Task 4: API/log analysis for both scenarios
Task 5: stale snapshot in RAG retrieval caused the wrong AI answer
