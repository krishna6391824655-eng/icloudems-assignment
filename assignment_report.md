# iCloudEMS Support Engineer (AI) – Assignment Submission

All SQL was executed on MariaDB 10.11 (MySQL-compatible). Full SQL: `solution_queries.sql`. Full captured output: `query_output.txt`.
Outstanding balance definition used: **DUE − PAID − CONCESSION** per admission number.

## Task 1 – Highlights
| # | Result |
|---|---|
| 1 | departments 5, programs 10, students 305, admissions 300, fee_transactions 516, fee_transaction_details 889 (matches INSERT counts in file) |
| 2 | 5 duplicated admission numbers in `students`: ADM10081, ADM10090, ADM10154, ADM10186, ADM10261 (305 students vs 300 admissions; the extra ids 301–305 are the duplicates, with different names) |
| 3 | 8 duplicate groups (same admission/type/amount/date): ADM10057, 10125, 10136, 10191 (x2 groups), 10201, 10226, 10289. Date matters because the same student can legitimately pay the same amount in the same type on different days (instalments); only same-day repeats are true duplicates. Duplicate ids are 5xx (e.g. 100/511). |
| 4–5 | 125 admission numbers have a positive outstanding balance (listed in output) |
| 6 | Top payer: ADM10226 Myra Malhotra ₹61,000; then ADM10008 / ADM10159 ₹49,000 … |
| 7 | Top program by collection: BCA ₹673,000, then BBA ₹526,000, M.Tech CS ₹446,000 (students de-duplicated by admission_no to avoid double counting) |
| 8 | 16 parents whose amount ≠ sum of details (e.g. txn 96 ₹25,000 vs ₹14,240; txn 518 ₹15,000 vs ₹10,000) |
| 9 | 10 parents with no child rows (txn 34, 83, 110, 128, 179, 201, 253, 287, 427, 514) |
| 10 | 10 orphan child rows (detail 893–902, txn ids 1016–1025) |
| 11 | Reconciliation report in SQL file (shows 7 admissions with a net difference; offsetting errors can hide at admission level, so per-transaction check in #8 is the authoritative one) |

## Task 2 – ADM10025
**Investigation / proof.** Txn 517 (DUE ₹15,000) has details Tuition 10,000 + Exam 5,000. Txn 518 (PAID ₹15,000, 2025-09-15) has only one detail: Tuition 10,000. The Exam Fee 5,000 line is missing.
Due from parents = 0; due from details = ₹5,000 (query in SQL file).

**Root cause.** Inserting the 2nd detail row failed with a duplicate key (`detail_id` 3024 – sequence/ID collision). The generic exception handler swallowed the error and the transaction was not rolled back, leaving a parent without its full set of children. The payment API still returned 200. `DueCalculationJob` computes due from `fee_transaction_details`, so it saw only 10,000 paid and reported ₹5,000 due.

**Plain terms.** The student really paid ₹15,000 and the money was recorded, but one line of the receipt (Exam Fee ₹5,000) failed to save, so the system thinks that part is unpaid.

**Fix.**
```sql
START TRANSACTION;
INSERT INTO fee_transaction_details (detail_id, transaction_id, admission_no, fee_head, amount, status)
VALUES (906, 518, 'ADM10025', 'Exam Fee', 5000, 'Success');
COMMIT;
```
(Verified: both transactions then reconcile at 15,000. In production use AUTO_INCREMENT/next sequence value instead of a hard-coded id; the `detail_id_seq` collision should also be fixed by resetting the sequence above MAX(detail_id).) Re-run DueCalculationJob for ADM10025 afterwards.

**Prevention.** Wrap parent+children inserts in one DB transaction with rollback on any failure; stop catching generic exceptions and return an error/retry; use AUTO_INCREMENT/UUIDs for ids; add foreign key `fee_transaction_details.transaction_id → fee_transactions`; add a post-commit check/nightly reconciliation (parent total = sum of children) with alerts; compute dues from parent totals or validate before using details; add idempotency key on `payment_id`; unit/integration tests for partial-failure paths.

## Task 3 – Highlights
- Row counts: parent 41, child 76 (match file; parent ids unique). Totals: parent ₹546,000 vs child ₹489,462.
- Amount mismatches (6): txn 9, 27, 33, 34, 35, 38.
- Parents with no child (4): txn 7, 22, 36, 40.
- Orphan children (4): detail 79–82 (txn 141–144).
- Count mismatches: ADM20002, ADM20008, ADM20015 (child has one extra txn id = orphan), ADM20005, ADM20016, ADM20027 (parent without child). Note ADM20029 has equal counts (2 vs 2) but is still a MISMATCH: one parent has no child while an orphan child fills its place, so always check amounts too.
- Final report (Admission No | Parent Amount | Child Amount | Difference | Parent Count | Child Count | Status) is in the SQL and output files: 12 MISMATCH, 18 MATCH admissions.

## Task 4 – API troubleshooting
### Scenario A (ADM10025)
1. **Root cause:** Payment gateway succeeded and the parent row (txn 518) was inserted, but the second detail insert failed on a duplicate `detail_id` key. The exception was caught generically, no rollback, and the controller returned HTTP 200 anyway. Result: partial write (parent 15,000, children 10,000). The due job aggregates details, so due = 5,000.
2. **Classification:** Application (error handling/transaction management) with a contributing Database/Data issue (ID sequence collision, no FK/constraint).
3. **Verification SQL:**
```sql
SELECT t.transaction_id, t.total_amount parent_amount, COALESCE(SUM(d.amount),0) child_amount
FROM fee_transactions t LEFT JOIN fee_transaction_details d USING(transaction_id)
WHERE t.admission_no='ADM10025' GROUP BY t.transaction_id, t.total_amount
HAVING parent_amount<>child_amount;
SELECT MAX(detail_id) FROM fee_transaction_details;   -- compare with sequence value
```
4. **Fix and test:** Single DB transaction for parent+all details, rollback and surface error on failure, no blanket catch, use auto-increment/sequence reset, add FK and a parent=sum(children) validation. Test: unit/integration test that forces a duplicate-key failure on the 2nd detail and asserts nothing is committed and the API returns 5xx/failed status; happy-path test with multi-head payment asserting due = 0; re-run the verification query across all data.

### Scenario B (ADM10089, HTTP 500)
5. **Root cause:** Gateway charged the student (SUCCESS) but the insert into `fee_transactions` waited 30 s and failed with a lock wait timeout (another transaction holding locks on the table, e.g. a long-running job or batch). The unhandled exception returned 500, nothing was stored; the payment is "orphaned" and the student may retry and pay twice.
6. **Classification:** Database (locking/concurrency/performance) with Application weakness (no retry/compensation, gateway call and DB write not coordinated).
7. **Fix/test/reconcile:** Find and fix the blocking transaction (`SHOW ENGINE INNODB STATUS`, `information_schema.innodb_trx`), keep transactions short, index/row-level locking, retry with backoff, record the gateway payment in a pending-payments table *before/immediately after* capture and use idempotency on `payment_id`; webhook/reconciliation job to create missing records. Test: simulate lock contention in staging, assert the payment ends up recorded exactly once and the user sees pending/success. To reconcile PAY51190: confirm in the gateway dashboard (RZP_7QW2XZ9), confirm no row exists (`SELECT ... WHERE admission_no='ADM10089'`), then insert PAID txn + detail rows in a single transaction with the gateway reference, recompute due, and tell the student; refund if it is a duplicate. Run a daily gateway-vs-DB reconciliation.

## Task 5 – AI assistant returned ₹12,500 instead of ₹8,500
1. **Possible reasons:** stale snapshot/index in retrieval; cache not invalidated; wrong record retrieved; context older than DB; prompt not instructing to use live data; LLM hallucination/using memory; API returning cached data; DB replica lag; wrong field mapped.
2. **Most likely category: RAG / data-retrieval staleness.** Evidence: the retrieved context was a snapshot generated 2025-09-15 23:00 IST showing ₹12,500 and the LLM faithfully repeated it; the live DB says ₹8,500 (difference ₹4,000, consistent with a payment after the snapshot). The LLM did not invent a number, it reproduced the stale context. It's not a DB bug (DB is correct) and not a hallucination.
3. **Investigation flow:** log the user query → AI app request/trace → retrieval/API call (what was fetched, timestamp, source) → compare against the DB → inspect vector store/snapshot job and cache TTL → look at the final prompt/context sent to the LLM → compare with the LLM output.
4. **Verify DB value:** `SELECT SUM(CASE transaction_type WHEN 'DUE' THEN total_amount ELSE -total_amount END) FROM fee_transactions WHERE admission_no='ADM10501';` run directly (primary, not replica) and compare with the ERP screen/API.
5. **Prevention:** fetch live balances through a tool/API call at query time (not from snapshots); if snapshots are needed, add TTL, event-driven refresh on payment, "as of" timestamp in the answer, and a freshness check (reject context older than N minutes); instruct the model to cite the timestamp or say the data may be stale.
6. **Testing after fix:** automated test cases: change the DB value, ask the same question, expect the new value; test right after a payment; test with stale cache forced; regression suite across several admission numbers; compare AI answers to a SQL ground truth.
